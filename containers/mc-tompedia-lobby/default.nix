{ config, pkgs, lib, ... }:

let
  worldFactory = import ../../templates/mc-world/default.nix { inherit config pkgs lib; };
in
worldFactory.mkWorld {
  serverName = "tompedia-lobby";

  extraEnv = {
    MOTD = "Welcome to the Tompedia_Labo!";
  };
}
