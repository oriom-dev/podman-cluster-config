{
  description = "Hybrid Podman Cluster Management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix }: {
    homeConfigurations = {
      "ubuntu@kagoya_vps" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { system = "x86_64-linux"; };
        modules = [
          sops-nix.homeManagerModules.sops
          ./hosts/kagoya_vps/default.nix
        ];
      };
      "ubuntu@home_desktop" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { system = "x86_64-linux"; };
        modules = [
          sops-nix.homeManagerModules.sops
          ./hosts/home_desktop/default.nix
        ];
      };
    };
  };
}
