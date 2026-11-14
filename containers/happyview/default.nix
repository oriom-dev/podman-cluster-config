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
      # The BSAF importer's two signing keys (PKCS#8 PEM, written by `mosimo-ca credentials`;
      # sd_2607 appview/bsaf/PUBLISHER.md "Key placement"). Only these leaf keys are here: root,
      # CA and PLC rotation keys stay offline in sd_2607 ca/keys.
      mosimo_importer_nostr_pem = {
        sopsFile = ./secrets.yaml;
        format = "yaml";
        restartUnits = [ "mosimo-bsaf-publisher.service" ];
      };
      mosimo_importer_atproto_pem = {
        sopsFile = ./secrets.yaml;
        format = "yaml";
        restartUnits = [ "mosimo-bsaf-publisher.service" ];
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
      # documents checked 2026-10-18.
      authors = [
        "did:plc:vwi7zhfyamyvrg5v6ycjgzxi"
        "did:plc:kxwz5cz7o6g4jlmxh6doyfsm"
      ];
      publisher = {
        enable = true;
        selectJmaDefaults = true;
        selectKikikuruDefaults = true;
        # Public files from `mosimo-ca credentials` (the importer's DID, key-attestation chain, root).
        identityFile = ./mosimo-importer/identity.json;
        chainFile = ./mosimo-importer/chain.cbor;
        trustFile = ./mosimo-importer/roots.json;
        nostrKeyFile = config.sops.secrets.mosimo_importer_nostr_pem.path;
        atprotoKeyFile = config.sops.secrets.mosimo_importer_atproto_pem.path;
        relayUrl = "wss://pds.oriom.dev";
      };
    };

    services.caddy.virtualHosts = {
      "appview.oriom.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:3000
      '';
      # Revocation list of the Oriom Mosimo CA (issuerDomain pds.oriom.dev): a CA-signed, static
      # file that changes only when a key is revoked (attest.revocation.list). Relays and the
      # publisher fetch it periodically; it carries no secrets. Update it by committing the CA's
      # _revocation-list/revocations.cbor from sd_2607 ca/keys after `mosimo-ca publish`.
      "pds.oriom.dev".extraConfig = ''
        handle /.well-known/mosimo/attest/revocations {
          root * ${./mosimo-trust}
          rewrite * /revocations.cbor
          header Content-Type application/cbor
          header Cache-Control "max-age=300"
          file_server
        }
      '';
    };

  };
}
