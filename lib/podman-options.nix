{ lib, ... }:
{
  options.podman.activeServices = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "自動起動するPodmanサービスのリスト";
  };
}
