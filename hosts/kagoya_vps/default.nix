{ ... }:
{
  imports = [
    ../common
    ./disko.nix
    ../../containers/headscale
    ../../containers/caddy
  ];

  networking = {
    hostName = "kagoya-vps";
    useDHCP = false;
    interfaces.enp3s0.ipv4.addresses = [
      { address = "133.18.180.180"; prefixLength = 23; }
      { address = "10.150.11.1"; prefixLength = 24; }
    ];
    defaultGateway = "133.18.180.1";
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN/h11zIoUgksb0ETTk8aTeo5Ehcmv8uw349rACSIbUO"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "26.05";
}