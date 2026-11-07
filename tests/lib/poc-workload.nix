# Shared pieces for the M3 PoC tests: an offline image that doubles as the pause
# image, and a DaemonSet that answers with the name of the node it runs on.
{ pkgs }:
let
  imageEnv = pkgs.buildEnv {
    name = "m3-poc-image-env";
    paths = with pkgs; [ tini bashInteractive coreutils socat getent ];
  };
in
{
  image = pkgs.dockerTools.buildImage {
    name = "test.local/poc";
    tag = "local";
    copyToRoot = imageEnv;
    config.Entrypoint = [ "/bin/tini" "--" "/bin/sleep" "inf" ];
  };
  imageRef = "test.local/poc:local";

  # :8000 replies with the node name; :8001 streams 2 MB, used to catch MTU /
  # fragmentation black holes across nodes. The image has no /tmp, so the data is
  # generated per connection.
  daemonset = pkgs.writeText "echo.yaml" ''
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
              command: ["bash", "-c"]
              args:
                - |
                  socat TCP4-LISTEN:8001,fork,reuseaddr SYSTEM:'head -c 2000000 /dev/zero' &
                  exec socat TCP4-LISTEN:8000,fork,reuseaddr SYSTEM:'echo $NODE'
              resources:
                limits: { memory: 48Mi }
  '';
}
