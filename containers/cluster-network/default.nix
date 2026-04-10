{ config, pkgs, ... }:
{
  home.file.".config/containers/systemd/cluster.network".source = ./cluster.network;
}
