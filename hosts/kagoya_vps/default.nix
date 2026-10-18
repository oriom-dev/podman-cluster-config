{ config, inputs, ... }:
{
  imports = [
    ../common
    ./disko.nix
    ../../containers/headscale
    ../../containers/caddy
    (inputs.happyview + "/appview/happyview")
    (inputs.mosimo + "/pds")
    (inputs.mosimo + "/appview/bsaf")
    (inputs.mosimo + "/apps/web")
  ];

  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.secrets = {
    happyview_session_secret = {
      sopsFile = ../../containers/happyview/secrets.yaml;
      format = "yaml";
    };
    happyview_token_encryption_key = {
      sopsFile = ../../containers/happyview/secrets.yaml;
      format = "yaml";
    };
  };
  sops.templates."happyview.env".content = ''
    SESSION_SECRET=${config.sops.placeholder.happyview_session_secret}
    TOKEN_ENCRYPTION_KEY=${config.sops.placeholder.happyview_token_encryption_key}
  '';

  services.happyview = {
    enable = true;
    publicUrl = "https://appview.oriom.dev";
    environmentFile = config.sops.templates."happyview.env".path;
  };

  services.mosimo-web = {
    enable = true;
    domain = "mosimo.oriom.dev";
  };

  services.mosimo-bsaf = {
    enable = true;
    # jma-alert-bot.bsky.social (unofficial); handle and PLC document checked 2026-10-18.
    authors = [
      "did:plc:vwi7zhfyamyvrg5v6ycjgzxi"
      "did:plc:kxwz5cz7o6g4jlmxh6doyfsm"
    ];
    publisher = {
      enable = true;
      selectJmaDefaults = true;
      selectKikikuruDefaults = true;
      credentialsFile = "/var/lib/mosimo-importer/credentials.json";
      trustFile = "/var/lib/mosimo-importer/roots.json";
      relayUrl = "wss://pds.oriom.dev";
    };
  };

  services.mosimo-pds = {
    enable = true;
    settings = {
      groups = [
        { id = "oriom"; endpoint = "https://pds.oriom.dev"; }
      ];
      relays = [ "wss://relay.damus.io" ];
      publicInformation = (builtins.fromJSON
        (builtins.readFile ./mosimo-public-information.json)).publicInformation;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/mosimo-importer 0700 root root -"
    "d /var/lib/mosimo-trust 0750 root caddy -"
  ];

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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN/h11zIoUgksb0ETTk8aTeo5Ehcmv8uw349rACSIbUO"
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