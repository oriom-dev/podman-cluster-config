# Mosimo physical PDS and Nostr relay (pds.oriom.dev), from jphacks/sd_2607.
# Independent of the other Mosimo services; it only happens to share their repository.
{ config, inputs, lib, ... }:
let
  cfg = config.services.mosimo-pds;
in
{
  imports = [
    (inputs.mosimo + "/pds")
    ../../modules/nodejs-override.nix
  ];

  config = lib.mkIf cfg.enable {
    services.mosimo-pds.settings = {
      groups = [
        { id = "oriom"; endpoint = "https://pds.oriom.dev"; }
      ];
      relays = [ "wss://relay.damus.io" ];
      publicInformation = (builtins.fromJSON
        (builtins.readFile ./public-information.json)).publicInformation;
    };

    # Catch-all; containers/happyview adds the BSAF trust snapshot path on this host.
    services.caddy.virtualHosts."pds.oriom.dev".extraConfig = ''
      handle {
        reverse_proxy 127.0.0.1:2583
      }
    '';
  };
}
