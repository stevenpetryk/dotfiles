{
  description = "My dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      createConfiguration = { system, username, homeDirectory, isWork }: home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules = [ ./home.nix ];
        extraSpecialArgs = {
          inherit system username homeDirectory isWork;
        };
      };
    in
    {
      # Personal
      homeConfigurations."steven" = createConfiguration rec {
        system = "aarch64-darwin";
        username = "steven";
        homeDirectory = "/Users/${username}";
        isWork = false;
      };
      # Work Mac
      homeConfigurations."steven.petryk" = createConfiguration rec {
        system = "aarch64-darwin";
        username = "steven.petryk";
        homeDirectory = "/Users/${username}";
        isWork = true;
      };
      # Work Coder
      homeConfigurations."discord" = createConfiguration rec {
        system = "x86_64-linux";
        username = "discord";
        homeDirectory = "/home/${username}";
        isWork = true;
      };

      # Ensure Coder has a home-manager flake
      apps.x86_64-linux.home-manager = {
        type = "app";
        program = "${nixpkgs.legacyPackages.x86_64-linux.home-manager}/bin/home-manager";
      };

      # Manage personal system with flakes too
      apps.aarch64-darwin.home-manager = {
        type = "app";
        program = "${nixpkgs.legacyPackages.aarch64-darwin.home-manager}/bin/home-manager";
      };
    };
}
