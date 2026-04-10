{ config, pkgs, ... }:

{
  home.file = {
    ".config/containers/systemd/headscale.container".source = ./headscale.container;
    # config.yaml を配置
    ".config/headscale/config.yaml".source = ./config.yaml;
  };
}
