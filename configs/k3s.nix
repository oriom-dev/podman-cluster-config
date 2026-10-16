{ config, pkgs, nodeRole, hostName, bootstrapHost, ... }:
let
  # 役割に基づくK3sの起動引数の生成
  k3sArgs =
    if nodeRole == "init-server" then
      "server --cluster-init --tls-san=${hostName}"
    else if nodeRole == "server" then
      "server --server https://${bootstrapHost}:6443 --tls-san=${hostName}"
    else if nodeRole == "agent" then
      "agent --server https://${bootstrapHost}:6443"
    else
      "";
in {
  home.file.".config/rancher/k3s/registries.yaml".text = ''
    mirrors:
      "registry.kube-system.svc.cluster.local:5000":
        endpoint:
          - "http://registry.kube-system.svc.cluster.local:5000"
  '';

  systemd.user.services.k3s = {
    Unit = {
      Description = "K3s Node over Tailscale";
      After = [ "network.target" "tailscaled.service" ];
    };
    Service = {
      Environment = [ "PATH=${pkgs.tailscale}/bin:${pkgs.k3s}/bin:/usr/bin:/bin" ];
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c ' \
          TS_IP=$(tailscale ip -4) && \
          exec k3s ${k3sArgs} \
            --private-registry /home/user/.config/rancher/k3s/registries.yaml
            --token-file=${config.sops.secrets.k3s_token.path} \
            --vpn-auth-file=${config.sops.templates."vpn-auth.conf".path} \
            --node-external-ip=$TS_IP \
        '
      '';
      Restart = "always";
      RestartSec = "10";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
