{ pkgs, ... }:
{
  imports = [ ../../modules/container-policy.nix ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
  };

  networking.firewall = {
    enable = true;
    allowPing = false;
    checkReversePath = "loose";
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
  };

  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
    # Drop unused images weekly, keeping the last week so a rollback to the previous
    # generation still finds its locally built images. Volumes are never pruned.
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" "--filter=until=168h" ];
    };
  };

  # Bound the journal; unbounded growth reached 3.4 GiB on kagoya-vps.
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    MaxRetentionSec=1month
  '';

  environment.systemPackages = with pkgs; [ git podman tailscale ];
}
