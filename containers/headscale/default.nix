{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
in
{
  podman.activeServices = [ "headscale" ];

  home.file = helper.mkQuadlet {
    name = "headscale";
    templatePath = ./headscale.container;
  } // {
    ".config/headscale/config.yaml".source = ./config.yaml;
    ".local/share/headscale/tailscale/.keep".text = "";
    ".local/share/headscale/.keep".text = "";
  };
}
