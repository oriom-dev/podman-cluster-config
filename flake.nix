{
  description = "NixOS configuration for the Oriom multi-region Podman cluster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    nixvim.url = "github:nix-community/nixvim";

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
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, disko, nixos-wsl, sops-nix, ... }:
    let
      # All cluster nodes run x86_64-linux. Host outputs stay system-independent
      # (`.#nixosConfigurations.<host>`) because bin/vps-* and nixos-rebuild use that path.
      hostSystem = "x86_64-linux";

      mkHost = modules: nixpkgs.lib.nixosSystem {
        system = hostSystem;
        specialArgs = {
          inherit inputs;
          packageOverrides = {
            nodejs_24 = import ./package-overrides/nodejs_24.nix { system = hostSystem; };
          };
        };
        modules = modules ++ [{
          system.configurationRevision = self.rev or self.dirtyRev or null;
        }];
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

      perSystem = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          packages.vps = pkgs.buildEnv {
            name = "oriom-vps-cli";
            paths = with pkgs; [
              age
              bash
              coreutils
              curl
              git
              gnugrep
              nix
              openssh
              sops
              util-linux
            ];
          };

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              age
              curl
              git
              nil
              nixos-rebuild
              openssh
              podman
              python3
              sops
            ];

            shellHook = ''
              export SOPS_AGE_KEY_FILE="$(pwd)/.config/age.txt"
            '';
          };
        });
    in
    perSystem // {
      inherit nixosConfigurations;

      # `nix flake check` evaluates and builds every host system closure.
      checks = nixpkgs.lib.recursiveUpdate perSystem.checks or { } {
        ${hostSystem} = nixpkgs.lib.mapAttrs
          (_: host: host.config.system.build.toplevel)
          nixosConfigurations;
      };
    };
}
