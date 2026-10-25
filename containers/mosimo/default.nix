{ config, inputs, lib, packageOverrides, pkgs, ... }:
{
  imports = [ (inputs.mosimo + "/nixos") ];

  nixpkgs.overlays = [
    (_final: _prev: {
      nodejs_24 = packageOverrides.nodejs_24.package;
    })
  ];
  assertions = [{
    assertion = lib.versionAtLeast pkgs.nodejs_24.version packageOverrides.nodejs_24.requiredVersion;
    message = "Mosimo requires Node.js >= ${packageOverrides.nodejs_24.requiredVersion} for CVE-2026-111497";
  }];

  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.secrets = {
    happyview_session_secret = {
      sopsFile = ./secrets.yaml;
      format = "yaml";
    };
    happyview_token_encryption_key = {
      sopsFile = ./secrets.yaml;
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
    appviewUrl = "https://appview.oriom.dev";
    clientKey = "hvc_c15d9393de6ace328d65633d07d00278";
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
        (builtins.readFile ./public-information.json)).publicInformation;
    };
  };

  services.caddy.virtualHosts = {
    "pds.oriom.dev".extraConfig = ''
      handle /.well-known/mosimo/trust/snapshot.cbor {
        root * /var/lib/mosimo-trust
        rewrite * /snapshot.cbor
        header Content-Type application/cbor
        header Cache-Control "no-store"
        file_server
      }
      handle {
        reverse_proxy 127.0.0.1:2583
      }
    '';
    "appview.oriom.dev".extraConfig = ''
      reverse_proxy 127.0.0.1:3000
    '';
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/mosimo-importer 0700 root root -"
    "d /var/lib/mosimo-trust 0750 root caddy -"
  ];
}
