{ config, pkgs, lib, ... }:

let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "mc-whitelist-db";
in
{
  sops.secrets."${appName}_env" = { sopsFile = ./secrets.yaml; format = "yaml"; };
  podman.activeServices = [ "${appName}-tailscale" appName ];

  home.file =
    helper.mkQuadlet {
      name = "${appName}-tailscale";
      templatePath = ../../templates/http/tailscale.container.in;
      vars = {
        "@APP_NAME@" = appName;
        "@TS_SECRET_PATH@" = config.podman.tailscaleAuthKeyPath;
        "@TS_LOGIN_SERVER@" = config.podman.tailscaleLoginServer;
      };
    } //
    helper.mkQuadlet {
      name = appName;
      templatePath = ./mc-whitelist-db.container;
      vars = {
        "@SECRETS_PATH@" = config.sops.secrets."${appName}_env".path;
      };
    } //
    {
      ".config/containers/mc-whitelist-db/entrypoint.sh" = {
        source = ./entrypoint.sh;
        executable = true;
      };
    };
}
