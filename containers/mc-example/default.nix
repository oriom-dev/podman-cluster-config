{ config, pkgs, lib, ... }:

let
  worldFactory = import ../../templates/mc-world/default.nix { inherit config pkgs lib; };
in
worldFactory.mkWorld {
  serverName = "example";

  extraEnv = {
    MOTD = "Welcome to the Oriom Network Example World!";
  };
}
