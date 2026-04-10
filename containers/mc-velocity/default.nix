{ config, pkgs, ... }:
{
  home.file = {
    ".config/containers/systemd/mc-velocity.container".source = ./mc-velocity.container;
    ".config/containers/systemd/tailscale.container".source = ./tailscale.container;
    ".config/velocity/velocity.toml".source = ./velocity.toml;
  };
}
