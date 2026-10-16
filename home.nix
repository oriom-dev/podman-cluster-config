{ config, pkgs, isServer, serverTsIp, ... }: {
  home.username = "user";
  home.homeDirectory = "/home/user";
  home.stateVersion = "24.05";

  home.packages = with pkgs; [
    k3s
    tailscale
  ];

  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    age.keyFile = "/home/user/.config/sops/age/keys.txt";
    secrets = {
      k3s_token = {};
      tailscale_authkey = {};
    };
    templates."vpn-auth.conf".content = ''
      name=tailscale,joinKey=${config.sops.placeholder.tailscale_authkey}
    '';
  };

  imports = [
    ./configs/k3s.nix
  ];
}
