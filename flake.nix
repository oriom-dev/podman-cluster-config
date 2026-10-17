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
  };

  outputs = inputs@{ nixpkgs, disko, nixos-wsl, sops-nix, ... }:
    let
      system = "x86_64-linux";
      mkHost = modules: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = modules;
      };
    in {
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