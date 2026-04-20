{ config, pkgs, lib, ... }:

let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "mc-whitelist-auth";
in
{
  podman.activeServices = [ "mc-whitelist-db" "${appName}-build" appName ];

  home.file =
    helper.mkQuadlet {
      name = appName;
      type = "build";
      templatePath = ./${appName}.build;
    } //
    helper.mkQuadlet {
      name = appName;
      templatePath = ./${appName}.container.in;
    } //
    {
      ".config/containers/build/${appName}/Containerfile".source = ./Containerfile;
    };

  home.activation."copy_${appName}_src" = lib.hm.dag.entryAfter ["linkGeneration"] ''
    BUILD_DIR="$HOME/.config/containers/build/${appName}/src"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cp -rL ${./src}/* "$BUILD_DIR"/
    chmod -R u+w "$BUILD_DIR"
  '';
}
