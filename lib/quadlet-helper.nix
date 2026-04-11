{ config, pkgs, lib }:

{
  # テンプレートからQuadletファイルを生成し配置する共通関数
  mkQuadlet = { name, templatePath, vars ? {} }: 
    let
      # @HOGE@ のようなプレースホルダーと、置き換える値のリストを生成
      keys = builtins.attrNames vars;
      values = builtins.attrValues vars;
      templateContent = builtins.readFile templatePath;
    in {
      ".config/containers/systemd/${name}.container".text = 
        if vars == {} then templateContent
        else builtins.replaceStrings keys values templateContent;
    };
    
  # systemdがQuadletを認識するための必須設定
  quadletGenerator = {
    ".config/systemd/user-generators/podman-user-generator" = {
      source = "${pkgs.podman}/lib/systemd/user-generators/podman-user-generator";
      executable = true;
    };
  };
}
