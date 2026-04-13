{ config, pkgs, lib }:

{
  mkQuadlet = { name, type ? "container", templatePath, vars ? {} }: 
    let
      keys = builtins.attrNames vars;
      values = builtins.attrValues vars;
      templateContent = builtins.readFile templatePath;
    in {
      ".config/containers/systemd/${name}.${type}".text = 
        if vars == {} then templateContent
        else builtins.replaceStrings keys values templateContent;
    };

  mkBuildFile = { name, path, source }: {
    ".config/containers/build/${name}/${path}".source = source;
  };
}
