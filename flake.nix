{
  description = "NixOS configuration for the Oriom multi-region Podman cluster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    mosimo = {
      url = "github:jphacks/sd_2607/main";
      flake = false;
    };
    happyview = {
      url = "github:jphacks/sd_2607/main";
      flake = false;
    };
  };

  outputs = inputs@{ nixpkgs, disko, nixos-wsl, sops-nix, ... }:
    let
      system = "x86_64-linux";
      packageOverrides = {
        nodejs_24 = import ./package-overrides/nodejs_24.nix { inherit system; };
      };
      mkHost = modules: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs packageOverrides; };
        modules = modules ++ [{
          system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
        }];
      };
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages.${system}.vps = pkgs.buildEnv {
        name = "oriom-vps-cli";
        paths = with pkgs; [ bash coreutils curl git gnugrep nix openssh util-linux ];
      };

      nixosConfigurations = {
        kagoya-vps = mkHost [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/kagoya_vps
        ];
        home-desktop = mkHost [
          nixos-wsl.nixosModules.default
          sops-nix.nixosModules.sops
          ./hosts/home_desktop
        ];
      };
    };
}