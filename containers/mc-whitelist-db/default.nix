{ config, pkgs, lib, ... }:

let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "mc-whitelist-db";
in
{
  podman.activeServices = [ appName ];

  home.file = helper.mkQuadlet {
    name = appName;
    templatePath = ./mc-whitelist-db.container;
  };
}
