{ ... }:
{
  imports = [
    ../common
  ];

  wsl = {
    enable = true;
    defaultUser = "operator";
    wslConf.network.hostname = "home-desktop";
  };

  users.users.operator = {
    isNormalUser = true;
    extraGroups = [ "wheel" "podman" ];
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3000 ];

  system.stateVersion = "26.05";
}