# Node.js 24 used by the Mosimo services (mosimo-pds, the BSAF sidecar of
# happyview). Imported by each of those modules; the module system deduplicates it.
{ lib, packageOverrides, pkgs, ... }:
{
  nixpkgs.overlays = [
    (_final: _prev: {
      nodejs_24 = packageOverrides.nodejs_24.package;
    })
  ];
  assertions = [{
    assertion = lib.versionAtLeast pkgs.nodejs_24.version packageOverrides.nodejs_24.requiredVersion;
    message = "Mosimo services require Node.js >= ${packageOverrides.nodejs_24.requiredVersion}";
  }];
  warnings = lib.optional
    (lib.versionOlder pkgs.nodejs_24.version packageOverrides.nodejs_24.fixedVersion)
    "nodejs_24 ${pkgs.nodejs_24.version} is below ${packageOverrides.nodejs_24.fixedVersion} (CVE-2026-111497); see package-overrides/nodejs_24.nix";
}
