{
  description = "My dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      createConfiguration = { system, username, homeDirectory, extraModules, purpose }: home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};

        modules = [
          ./modules/shared.nix
        ] ++ extraModules;

        extraSpecialArgs = {
          inherit system username homeDirectory purpose;
        };
      };
    in
    {
      # Personal
      homeConfigurations."steven" = createConfiguration rec {
        system = "aarch64-darwin";
        username = "steven";
        homeDirectory = "/Users/${username}";
        purpose = "personal";
        extraModules = [ ./modules/personal.nix ];
      };
      # Work Mac
      homeConfigurations."steven.petryk" = createConfiguration rec {
        system = "aarch64-darwin";
        username = "steven.petryk";
        homeDirectory = "/Users/${username}";
        purpose = "work-mac";
        extraModules = [ ./modules/work-shared.nix ./modules/work-mac.nix ];
      };
      # Work Coder
      homeConfigurations."discord" = createConfiguration rec {
        system = "x86_64-linux";
        username = "discord";
        homeDirectory = "/home/${username}";
        purpose = "work-coder";
        extraModules = [ ./modules/work-shared.nix ./modules/work-coder.nix ];
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
