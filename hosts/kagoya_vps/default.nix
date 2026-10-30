{ ... }:
{
  imports = [
    ../common
    ./disko.nix
    ../../containers/headscale
    ../../containers/caddy
    ../../containers/cluster-hello
    ../../containers/jpost-api
    ../../containers/mc-whitelist-auth
    ../../containers/omni-tcp-probe
    ../../containers/mosimo
  ];

  services.jpost-api.enable = true;
  services.mc-whitelist-auth.enable = true;

  networking = {
    hostName = "kagoya-vps";
    useDHCP = false;
    interfaces.enp3s0.ipv4.addresses = [
      { address = "133.18.180.180"; prefixLength = 23; }
      { address = "10.150.11.1"; prefixLength = 24; }
    ];
    interfaces.enp3s0.ipv6.addresses = [
      { address = "2406:8c00:0:3462:133:18:180:180"; prefixLength = 64; }
    ];
    defaultGateway = "133.18.180.1";
    defaultGateway6 = {
      address = "2406:8c00:0:3462::1";
      interface = "enp3s0";
    };
    nameservers = [ "1.1.1.1" "1.0.0.1" ];
    firewall = {
      allowedTCPPorts = [ 22 80 443 ];
      allowedUDPPorts = [ 443 ];
    };
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" ];

  users.users.operator = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN/h11zIoUgksb0ETTk8aTeo5Ehcmv8uw349rACSIbUO dell2"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4uhy8T5GnGe+G53esadrdShscQvJruH+Gwa53WxCEm desktop1"
      "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/lEksFJK7AcZQMKRi2sYcQiPPs0puCe8o9cBXrxZnt desktop1 wsl-ubuntu"
    ];
  };
  users.users.yoyochinese = {
    isNormalUser = true;
    extraGroups = [ "systemd-journal" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJkxwuOH/EFWeLTw5FQ04ykp4gsBdBIPyQCLLsEQNwCf"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvSkRVaE6QpiU4lZ9ZHduRA2yBt4OSw9rnxdlsOCk8A"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOkXaezMsjAGbyjfJ6QQ0lT1UPx07ADGGqQtcivbyz0h"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICDgqjOdYvZurHyY7gNdZhrQGP+rDPeAjBUd8GofzoxQ"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "26.05";
}
