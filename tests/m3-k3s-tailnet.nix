# Roadmap M3, stage 2: K3s with the Headscale tailnet as its only underlay.
#
#   nix build .#checks.x86_64-linux.m3-k3s-tailnet -L
#
# Nodes join the tailnet like production (tagged single-use keys, no tailnet DNS,
# NixOS firewall in charge). The K3s ports are open on tailscale0 only and closed on
# eth1, so the cluster can only form over the tailnet. Checks: agent join, node IPs
# on the tailnet, cross-node Pod traffic, a 2 MB transfer through VXLAN-over-WireGuard
# (MTU), and that the Headscale ACL blocks a port the firewall leaves open.
{ pkgs, lib, ... }:
let
  k3s = pkgs.k3s;
  workload = import ./lib/poc-workload.nix { inherit pkgs; };
  tokenFile = pkgs.writeText "k3s-token" "m3-poc-token";

  tls = pkgs.runCommand "headscale-test-tls" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
      -out cert.pem -keyout key.pem -subj '/CN=headscale' \
      -addext "subjectAltName=DNS:headscale"
    mkdir -p $out && cp cert.pem key.pem $out
  '';

  # Same shape as containers/headscale/acl.hujson: tagged nodes, default deny.
  # 9999/tcp is open in every node firewall but not here, to prove the ACL bites.
  policy = pkgs.writeText "acl.hujson" (builtins.toJSON {
    tagOwners."tag:k3s" = [ ];
    acls = [{
      action = "accept";
      src = [ "tag:k3s" ];
      dst = [ "tag:k3s:6443" "tag:k3s:10250" "tag:k3s:8472" ];
    }];
  });

  serverIP = "100.64.0.1"; # sequential allocation: the server enrolls first
  agentIP = "100.64.0.2";

  node = role: ip: { ... }: {
    virtualisation = {
      memorySize = if role == "server" then 2048 else 1536;
      diskSize = 4096;
    };
    environment.systemPackages = with pkgs; [ kubectl jq socat ];
    environment.sessionVariables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    security.pki.certificateFiles = [ "${tls}/cert.pem" ];

    services.tailscale = {
      enable = true;
      openFirewall = true;
    };

    services.k3s = {
      enable = true;
      package = k3s;
      inherit role tokenFile;
      images = [ k3s.airgap-images workload.image ];
      nodeIP = ip;
      extraFlags = [
        "--pause-image ${workload.imageRef}"
        "--flannel-iface tailscale0"
      ] ++ lib.optionals (role == "server") [
        "--disable traefik"
        "--disable servicelb"
        "--disable local-storage"
        "--write-kubeconfig-mode 0600"
        "--tls-san ${ip}"
      ];
    } // lib.optionalAttrs (role == "agent") {
      serverAddr = "https://${serverIP}:6443";
    };
    # Started by the test once the node is on the tailnet.
    systemd.services.k3s.wantedBy = lib.mkForce [ ];

    networking.firewall = {
      enable = true;
      # K3s only over the tailnet; eth1 carries WireGuard and Headscale traffic only.
      interfaces.tailscale0 = {
        allowedTCPPorts = [ 10250 9999 ] ++ lib.optionals (role == "server") [ 6443 ];
        allowedUDPPorts = [ 8472 ];
      };
      trustedInterfaces = [ "cni0" "flannel.1" ];
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "m3-k3s-tailnet";

  nodes = {
    headscale = {
      services.headscale = {
        enable = true;
        port = 8080;
        settings = {
          server_url = "https://headscale";
          prefixes.v4 = "100.64.0.0/10";
          prefixes.allocation = "sequential";
          derp = {
            server = {
              enabled = true;
              region_id = 999;
              stun_listen_addr = "0.0.0.0:3478";
            };
            urls = [ ];
          };
          dns = {
            magic_dns = false;
            override_local_dns = false;
          };
          policy.path = policy;
        };
      };
      services.nginx = {
        enable = true;
        virtualHosts.headscale = {
          addSSL = true;
          sslCertificate = "${tls}/cert.pem";
          sslCertificateKey = "${tls}/key.pem";
          locations."/" = {
            proxyPass = "http://127.0.0.1:8080";
            proxyWebsockets = true;
          };
        };
      };
      networking.firewall = {
        allowedTCPPorts = [ 80 443 ];
        allowedUDPPorts = [ 3478 ];
      };
      environment.systemPackages = [ pkgs.headscale pkgs.jq ];
    };
    server = node "server" serverIP;
    agent = node "agent" agentIP;
  };

  testScript = ''
    start_all()
    headscale.wait_for_unit("headscale")
    headscale.wait_for_open_port(443)

    def enroll(m, ip):
        key = headscale.succeed("headscale preauthkeys create --tags tag:k3s --expiration 10m -o json | jq -r .key").strip()
        m.wait_for_unit("tailscaled")
        m.succeed(f"tailscale up --login-server=https://headscale --auth-key={key} "
                  f"--hostname={m.name} --accept-dns=false --netfilter-mode=off --timeout=60s")
        t.assertEqual(m.succeed("tailscale ip -4").strip(), ip)

    with subtest("nodes join the tailnet with tagged single-use keys"):
        enroll(server, "${serverIP}")
        enroll(agent, "${agentIP}")
        server.wait_until_succeeds("tailscale ping -c 1 ${agentIP}", timeout=60)

    with subtest("K3s forms only over the tailnet"):
        server.succeed("systemctl start k3s")
        server.wait_until_succeeds("kubectl get node server", timeout=300)
        agent.succeed("systemctl start k3s")
        server.wait_until_succeeds(
            "[ $(kubectl get nodes -o json | jq '[.items[] | select(.status.conditions[] | select(.type==\"Ready\" and .status==\"True\"))] | length') -eq 2 ]",
            timeout=300,
        )
        ips = server.succeed("kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type==\"InternalIP\")].address}'").split()
        t.assertEqual(sorted(ips), sorted(["${serverIP}", "${agentIP}"]))
        server.wait_until_succeeds("kubectl get serviceaccount default")

    with subtest("cross-node Pod traffic and a 2 MB transfer through VXLAN over WireGuard"):
        mtu = server.succeed("cat /sys/class/net/flannel.1/mtu").strip()
        print(f"M3-MEASURE flannel.1 mtu={mtu} tailscale0 mtu={server.succeed('cat /sys/class/net/tailscale0/mtu').strip()}")
        server.succeed("kubectl apply -f ${workload.daemonset}")
        server.wait_until_succeeds("[ $(kubectl get ds echo -o json | jq .status.numberReady) -eq 2 ]", timeout=300)
        pods = server.succeed("kubectl get po -l app=echo -o json | jq -r '.items[] | .metadata.name + \" \" + .status.podIP + \" \" + .spec.nodeName'").splitlines()
        for line in pods:
            name, ip, node_name = line.split()
            for other in pods:
                other_name, _, other_node = other.split()
                reply = server.succeed(f"kubectl exec {other_name} -- socat -T5 TCP:{ip}:8000 -").strip()
                t.assertEqual(reply, node_name)
                # Same node first: proves the bulk listener works before blaming the path.
                out = server.succeed(f"kubectl exec {other_name} -- bash -c 'socat -T10 -u TCP:{ip}:8001 - | wc -c'").strip()
                print(f"M3-BULK {other_node} -> {node_name}: {out}")
                t.assertEqual(out.splitlines()[0], "2000000", f"{other_node} -> {node_name}")

    with subtest("the Headscale ACL blocks a port the firewall leaves open"):
        server.succeed("systemd-run --unit=probe9999 socat TCP4-LISTEN:9999,bind=${serverIP},fork SYSTEM:'echo open'")
        server.wait_for_open_port(9999, addr="${serverIP}")
        agent.fail("socat -T3 TCP:${serverIP}:9999,connect-timeout=3 -")
        # The API port, which the ACL allows, still answers from the agent.
        agent.succeed("socat -T3 TCP:${serverIP}:6443,connect-timeout=3 - </dev/null")
  '';
}
