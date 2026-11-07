# Roadmap M3, stage 3: the same OCI image in Podman and K3s containerd.
#
#   nix build .#checks.x86_64-linux.m3-oci-parity -L
#
# One node runs Podman, a single-node K3s and a local OCI registry, offline.
#  1. `podman build --timestamp 0` twice from the same context gives the same image
#     (reproducible build identity).
#  2. Two ways into containerd, compared by config and manifest digest:
#     A. `podman save --format oci-archive` + `k3s ctr images import` (no registry);
#     B. `podman push` to the registry + a Pod pulling `@sha256:<manifest>`.
#  3. User, working directory, environment and entrypoint behave the same under
#     Podman and as a Kubernetes Pod.
{ pkgs, lib, ... }:
let
  k3s = pkgs.k3s;
  workload = import ./lib/poc-workload.nix { inherit pkgs; };
  registry = "registry.test:5000";

  # Build context: only metadata on top of the offline base, so no RUN is needed.
  context = pkgs.runCommand "m3-oci-context" { } ''
    mkdir -p $out/app
    echo "m3-parity-1" > $out/app/version
    cat > $out/Containerfile <<'EOF'
    FROM ${workload.imageRef}
    COPY app/ /app/
    WORKDIR /app
    ENV PARITY=same-everywhere
    USER 1000:1000
    ENTRYPOINT ["bash", "-c", "echo uid=$(id -u) gid=$(id -g) pwd=$(pwd) env=$PARITY version=$(cat version)"]
    EOF
  '';

in
pkgs.testers.runNixOSTest {
  name = "m3-oci-parity";

  nodes.node = { config, ... }: {
    virtualisation = {
      memorySize = 3072;
      diskSize = 6144;
    };
    environment.systemPackages = with pkgs; [ kubectl jq skopeo ];
    environment.sessionVariables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    networking.hosts."127.0.0.1" = [ "registry.test" ];

    virtualisation.podman.enable = true;
    # The test registry is plain HTTP on loopback.
    virtualisation.containers.registries.insecure = [ registry ];

    services.dockerRegistry = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 5000;
    };

    services.k3s = {
      enable = true;
      package = k3s;
      role = "server";
      images = [ k3s.airgap-images workload.image ];
      extraFlags = [
        "--pause-image ${workload.imageRef}"
        "--disable traefik"
        "--disable servicelb"
        "--disable local-storage"
        "--disable metrics-server"
        "--write-kubeconfig-mode 0600"
      ];
    };
    environment.etc."rancher/k3s/registries.yaml".text = ''
      mirrors:
        "${registry}":
          endpoint:
            - "http://${registry}"
    '';
  };

  testScript = ''
    import json

    def run_pod(name, image, explicit_ids=True):
        # Kubernetes applies the UID from the image's USER but not the GID: without
        # runAsGroup the process runs with gid 0. Manifests must set both (M5).
        policy = "Always" if "@sha256:" in image else "Never"
        security = "      securityContext: { runAsUser: 1000, runAsGroup: 1000 }\n" if explicit_ids else ""
        manifest = (
            "apiVersion: v1\nkind: Pod\nmetadata:\n  name: " + name + "\n"
            "spec:\n  restartPolicy: Never\n  containers:\n"
            "    - name: parity\n      image: " + image + "\n"
            "      imagePullPolicy: " + policy + "\n" + security
        )
        node.succeed(f"cat > /tmp/{name}.yaml <<'EOF'\n{manifest}EOF")
        node.succeed(f"kubectl apply -f /tmp/{name}.yaml")
        node.wait_until_succeeds(f"[ $(kubectl get pod {name} -o jsonpath='{{.status.phase}}') = Succeeded ]", timeout=180)
        return node.succeed(f"kubectl logs {name}").strip()

    node.wait_for_unit("docker-registry")
    node.wait_for_unit("k3s")
    node.wait_until_succeeds("kubectl get serviceaccount default", timeout=300)

    # The offline base image goes into Podman the same way it went into containerd.
    node.succeed("podman load -i ${workload.image}")

    with subtest("podman build is reproducible"):
        build = "podman build --timestamp 0 --pull=never -q -t {tag} ${context}"
        first = node.succeed(build.format(tag="localhost/parity:a")).strip()
        second = node.succeed(build.format(tag="localhost/parity:b") + " --no-cache").strip()
        t.assertEqual(first, second, "two builds of the same context differ")
        config_digest = "sha256:" + first.removeprefix("sha256:")
        print(f"M3-PARITY podman image id (config digest) {config_digest}")

    with subtest("A: OCI archive imported into containerd keeps the digests"):
        node.succeed("podman save --format oci-archive -o /tmp/parity.tar localhost/parity:a")
        node.succeed("k3s ctr -n k8s.io images import /tmp/parity.tar")
        images = json.loads(node.succeed("k3s crictl images -o json"))["images"]
        imported = [i for i in images if any("parity" in t for t in i.get("repoTags", []))]
        t.assertEqual(len(imported), 1, f"expected one imported image: {imported}")
        t.assertEqual(imported[0]["id"], config_digest, "containerd config digest differs from Podman")
        # The name containerd gives an imported archive is not necessarily the Podman
        # tag; Pods must use what containerd reports (or a digest).
        archive_ref = imported[0]["repoTags"][0]
        print(f"M3-PARITY archive imported as {imported[0]['repoTags']}")
        archive_out = run_pod("parity-archive", archive_ref)

    with subtest("B: registry push, Pod pulls by manifest digest"):
        node.succeed("podman push --tls-verify=false localhost/parity:a docker://${registry}/parity:a")
        manifest = node.succeed("skopeo inspect --tls-verify=false --format '{{.Digest}}' docker://${registry}/parity:a").strip()
        remote_config = json.loads(node.succeed("skopeo inspect --tls-verify=false --raw docker://${registry}/parity:a"))["config"]["digest"]
        t.assertEqual(remote_config, config_digest, "registry config digest differs from Podman")
        print(f"M3-PARITY registry manifest digest {manifest}")
        registry_out = run_pod("parity-registry", f"${registry}/parity@{manifest}")
        pulled = node.succeed("kubectl get pod parity-registry -o jsonpath='{.status.containerStatuses[0].imageID}'").strip()
        t.assertTrue(pulled.endswith(manifest), f"Pod ran {pulled}, expected {manifest}")
        after = [i["repoTags"] + i.get("repoDigests", []) for i in json.loads(node.succeed("k3s crictl images -o json"))["images"] if i["id"] == config_digest]
        print(f"M3-PARITY CRI references for the image after the registry pull: {after}")

    with subtest("runtime behaviour matches between Podman and the Pods"):
        podman_out = node.succeed("podman run --rm localhost/parity:a").strip()
        print(f"M3-PARITY podman:   {podman_out}")
        print(f"M3-PARITY archive:  {archive_out}")
        print(f"M3-PARITY registry: {registry_out}")
        t.assertEqual(podman_out, "uid=1000 gid=1000 pwd=/app env=same-everywhere version=m3-parity-1")
        t.assertEqual(archive_out, podman_out)
        t.assertEqual(registry_out, podman_out)

    with subtest("known difference: without runAsGroup a Pod gets gid 0"):
        implicit = run_pod("parity-implicit", archive_ref, explicit_ids=False)
        print(f"M3-PARITY implicit: {implicit}")
        t.assertEqual(implicit, podman_out.replace("gid=1000", "gid=0"))
  '';
}
