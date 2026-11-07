# home-desktop: NixOS Hyper-V Gen2 VM on the desktop-1 Windows host.
#
# Isolation (see hosts/home_desktop/README.md): the VM sits on its own internal
# switch behind WinNAT, and host-enforced Hyper-V port ACLs only let it reach the
# Internet. It cannot reach desktop-1 itself, the home LAN, the Windows Tailscale
# tailnet, or any private range, even as root. The only inbound path is SSH from the
# Windows host (10.250.0.1) for bootstrap and management.
{ lib, modulesPath, ... }:
let
  address = "10.250.0.2";
  gateway = "10.250.0.1";
in
{
  imports = [
    ../common
    "${modulesPath}/virtualisation/hyperv-image.nix"
  ];

  virtualisation.hypervGuest.enable = true;
  # Built image size; the VHDX is resized to 64 GB on the host and the root
  # partition grows on first boot (boot.growPartition from hyperv-image.nix).
  virtualisation.diskSize = 8 * 1024;

  networking = {
    hostName = "home-desktop";
    usePredictableInterfaceNames = false;
    useDHCP = false;
    # The internal switch has no IPv6 uplink; link-local would only reach the host.
    enableIPv6 = false;
    interfaces.eth0.ipv4.addresses = [{ inherit address; prefixLength = 24; }];
    defaultGateway = gateway;
    nameservers = [ "1.1.1.1" "9.9.9.9" ];
    firewall.interfaces.eth0.allowedTCPPorts = [ 22 ];
  };

  # Data disk (512 GB VHDX on the host's S: HDD) for backup repositories and bulk
  # data. Formatted once with `mkfs.ext4 -L data /dev/sdb`; nofail keeps the node
  # bootable if the disk is detached.
  fileSystems."/srv/data" = {
    device = "/dev/disk/by-label/data";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=10s" ];
  };

  users.users.operator = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN/h11zIoUgksb0ETTk8aTeo5Ehcmv8uw349rACSIbUO dell2"
    ];
  };
  # Remote nixos-rebuild runs as operator; there is no password to type.
  security.sudo.wheelNeedsPassword = false;

  services.openssh.settings.PermitRootLogin = lib.mkForce "no";

  time.timeZone = "UTC";

  system.stateVersion = "26.05";
}
