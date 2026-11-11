# HappyView AppView (appview.oriom.dev) with its BSAF sidecar, from jphacks/sd_2607.
#
# The BSAF collector and publisher write into HappyView's SQLite database and are
# bound to podman-happyview (partOf/requires), so they are one unit, like a pod:
# enabling happyview enables the sidecar.
{ config, inputs, lib, ... }:
let
  cfg = config.services.happyview;
in
{
  imports = [
    (inputs.mosimo + "/appview/bsaf") # also imports appview/happyview
    ../../modules/nodejs-override.nix
    ./jetstream-watchdog.nix
  ];

  config = lib.mkIf cfg.enable {
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
    sops.templates."happyview.env" = {
      content = ''
        SESSION_SECRET=${config.sops.placeholder.happyview_session_secret}
        TOKEN_ENCRYPTION_KEY=${config.sops.placeholder.happyview_token_encryption_key}
      '';
      # The container reads this file only at start; without this a rotated secret
      # stays inactive until an unrelated restart.
      restartUnits = [ "podman-happyview.service" ];
    };

    services.happyview = {
      publicUrl = "https://appview.oriom.dev";
      environmentFile = config.sops.templates."happyview.env".path;
    };

    # Sidecar: imports BSAF posts into HappyView and publishes them to the PDS relay.
    services.mosimo-bsaf = {
      enable = true;
      # jma-alert-bot.bsky.social and bsaf-kikikuru-bot.bsky.social (unofficial); handles and PLC
      # documents checked 2026-10-18. Credentials/roots come from bin/mosimo-trust-install.sh.
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

    services.caddy.virtualHosts = {
      "appview.oriom.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:3000
      '';
      # Revocation list of the Oriom Mosimo CA (issuerDomain pds.oriom.dev): a CA-signed, static
      # file that changes only when a key is revoked (attest.revocation.list). Relays and the
      # publisher fetch it periodically; it carries no secrets.
      "pds.oriom.dev".extraConfig = ''
        handle /.well-known/mosimo/attest/revocations {
          root * /var/lib/mosimo-trust
          rewrite * /revocations.cbor
          header Content-Type application/cbor
          header Cache-Control "max-age=300"
          file_server
        }
      '';
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/mosimo-importer 0700 root root -"
      "d /var/lib/mosimo-trust 0750 root caddy -"
    ];
  };
}
