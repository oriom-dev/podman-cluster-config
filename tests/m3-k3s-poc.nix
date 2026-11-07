# Roadmap M3, stage 1: disposable two-node K3s (server + agent) without Internet.
#
#   nix build .#checks.x86_64-linux.m3-k3s-poc -L
#
# Verifies agent join, cross-node Pod traffic, cluster DNS and metrics-server with
# the firewall enabled and only the K3s ports open, and reports the server's K3s
# memory use for the M1 budget. Later stages add the tailnet underlay, OCI digest
# parity with Podman and the Caddy handoff.
{ pkgs, lib, ... }:
let
  k3s = pkgs.k3s;
  tokenFile = pkgs.writeText "k3s-token" "m3-poc-token";

  imageEnv = pkgs.buildEnv {
    name = "m3-poc-image-env";
    paths = with pkgs; [ tini bashInteractive coreutils socat getent ];
  };
  # Pause image and test workload in one: replies with the Pod's node name.
  pocImage = pkgs.dockerTools.buildImage {
    name = "test.local/poc";
    tag = "local";
    copyToRoot = imageEnv;
    config.Entrypoint = [ "/bin/tini" "--" "/bin/sleep" "inf" ];
  };

  echoDaemonset = pkgs.writeText "echo.yaml" ''
    apiVersion: apps/v1
    kind: DaemonSet
    metadata:
      name: echo
    spec:
      selector:
        matchLabels: { app: echo }
      template:
        metadata:
          labels: { app: echo }
        spec:
          containers:
            - name: echo
              image: test.local/poc:local
              imagePullPolicy: Never
              env:
                - name: NODE
                  valueFrom: { fieldRef: { fieldPath: spec.nodeName } }
              command: ["socat", "TCP4-LISTEN:8000,fork", "SYSTEM:echo $NODE"]
              resources:
                limits: { memory: 32Mi }
  '';

  node = role: { config, ... }: {
    virtualisation = {
      memorySize = if role == "server" then 2048 else 1536;
      diskSize = 4096;
    };
    environment.systemPackages = with pkgs; [ kubectl jq ];
    environment.sessionVariables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";

    services.k3s = {
      enable = true;
      package = k3s;
      inherit role tokenFile;
      images = [ k3s.airgap-images pocImage ];
      nodeIP = config.networking.primaryIPAddress;
      extraFlags = [
        "--pause-image test.local/poc:local"
        "--flannel-iface eth1"
      ] ++ lib.optionals (role == "server") [
        "--disable traefik"
        "--disable servicelb"
        "--disable local-storage"
        "--write-kubeconfig-mode 0600"
      ];
    } // lib.optionalAttrs (role == "agent") {
      serverAddr = "https://server:6443";
    };

    # Production-like: firewall on, only what K3s needs between nodes.
    networking.firewall = {
      enable = true;
      interfaces.eth1 = {
        allowedTCPPorts = [ 10250 ] ++ lib.optionals (role == "server") [ 6443 ];
        allowedUDPPorts = [ 8472 ];
      };
      # Pod and Service CIDRs reach the host through cni0/flannel.1.
      trustedInterfaces = [ "cni0" "flannel.1" ];
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "m3-k3s-poc";

  nodes = {
    server = node "server";
    agent = node "agent";
  };

  testScript = ''
    start_all()
    server.wait_for_unit("k3s")
    agent.wait_for_unit("k3s")

    with subtest("agent joins and both nodes become Ready"):
        server.wait_until_succeeds("kubectl get node agent", timeout=300)
        server.wait_until_succeeds(
            "[ $(kubectl get nodes -o json | jq '[.items[] | select(.status.conditions[] | select(.type==\"Ready\" and .status==\"True\"))] | length') -eq 2 ]",
            timeout=300,
        )
        server.wait_until_succeeds("kubectl get serviceaccount default")

    with subtest("cross-node Pod traffic"):
        server.succeed("kubectl apply -f ${echoDaemonset}")
        server.wait_until_succeeds("[ $(kubectl get ds echo -o json | jq .status.numberReady) -eq 2 ]", timeout=300)
        pods = server.succeed("kubectl get po -l app=echo -o json | jq -r '.items[] | .metadata.name + \" \" + .status.podIP + \" \" + .spec.nodeName'").splitlines()
        for line in pods:
            name, ip, node_name = line.split()
            for other in pods:
                other_name = other.split()[0]
                reply = server.succeed(f"kubectl exec {other_name} -- socat -T5 TCP:{ip}:8000 -").strip()
                t.assertEqual(reply, node_name)

    with subtest("cluster DNS"):
        server.wait_until_succeeds("kubectl -n kube-system rollout status deploy/coredns --timeout=10s", timeout=300)
        pod = pods[0].split()[0]
        server.wait_until_succeeds(f"kubectl exec {pod} -- getent hosts kubernetes.default.svc.cluster.local", timeout=120)

    with subtest("metrics-server"):
        server.wait_until_succeeds("kubectl top nodes", timeout=300)

    with subtest("memory for the M1 budget"):
        # MemoryCurrent includes page cache from importing the airgap images; the
        # budget needs anonymous + kernel memory that cannot be reclaimed.
        def usage(m, cgroup):
            stat = dict(l.split() for l in m.succeed(f"cat /sys/fs/cgroup/{cgroup}/memory.stat").splitlines())
            return (int(stat["anon"]) + int(stat["kernel"])) // 2**20, int(stat["file"]) // 2**20
        for m in (server, agent):
            m.succeed("sync; echo 3 > /proc/sys/vm/drop_caches")
            k3s_anon, k3s_file = usage(m, "system.slice/k3s.service")
            pods_cg = m.succeed("for d in kubepods.slice kubepods; do [ -d /sys/fs/cgroup/$d ] && echo $d && break; done").strip()
            pods_anon, pods_file = usage(m, pods_cg)
            print(f"M3-MEASURE {m.name}: k3s.service anon+kernel={k3s_anon}MiB (file {k3s_file}MiB), "
                  f"kubepods anon+kernel={pods_anon}MiB (file {pods_file}MiB)")
  '';
}
