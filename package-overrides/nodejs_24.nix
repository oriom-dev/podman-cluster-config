{ system }:
let
  # Temporary official Nixpkgs backport for CVE-2026-111497.
  # Delete this override after the primary nixpkgs provides requiredVersion.
  requiredVersion = "24.22.1";
  nixpkgsSource = builtins.fetchTree {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "62ef8c83d850a195c2dfc95975ac1d4b915e6086";
    narHash = "sha256-QSDhcx1tmOpxeWf2NZcP/O6bpB8EFNCow3QIXEd90Yw=";
  };
  overridePkgs = import nixpkgsSource.outPath { inherit system; };
in
{
  inherit requiredVersion;
  package = overridePkgs.nodejs_24;
}
