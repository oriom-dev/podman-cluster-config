{ system }:
let
  # Node.js 24 from the newest nixos-unstable that Hydra has cached (checked 2026-11-07).
  #
  # SECURITY GAP: CVE-2026-111497 is fixed in 24.22.1, which is not in any nixpkgs
  # branch yet (nixos-unstable, -small and master are at 24.21.0). The previous pin to
  # an unmerged backport (62ef8c83, 24.22.1) had no binary cache and took over an hour
  # to compile, so this temporarily accepts 24.21.0. When nixos-unstable reaches
  # 24.22.1, point `rev` at it and raise `requiredVersion` back to "24.22.1".
  requiredVersion = "24.21.0";
  fixedVersion = "24.22.1";
  nixpkgsSource = builtins.fetchTree {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "1d060086d60cb76a40cf37109f979d88a5bd6396";
    narHash = "sha256-jQp1wKvbwWdLBASTXkSi/VYmDJ5AbBi1WvcMt9HWJC8=";
  };
  overridePkgs = import nixpkgsSource.outPath { inherit system; };
in
{
  inherit requiredVersion fixedVersion;
  package = overridePkgs.nodejs_24;
}
