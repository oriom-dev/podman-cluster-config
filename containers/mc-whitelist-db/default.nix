{ config, pkgs, lib, ... }:

let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "mc-whitelist-db";
in
{
  podman.activeServices = [ "${appName}-tailscale" appName ];

  home.file =
    helper.mkQuadlet {
      name = "${appName}-tailscale";
      templatePath = ./tailscale.container;
      vars = {
        "@TS_SECRET_PATH@" = config.podman.tailscaleAuthKeyPath;
        "@TS_LOGIN_SERVER@" = config.podman.tailscaleLoginServer;
      };
    } //
    helper.mkQuadlet {
      name = appName;
      templatePath = ./mc-whitelist-db.container;
    };
}
