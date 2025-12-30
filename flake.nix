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
      createConfiguration = { system, username, homeDirectory, dotfilesPath, extraModules }: home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};

        modules = [
          ./modules/shared.nix
          ./modules/programs/git.nix
        ] ++ extraModules;

        extraSpecialArgs = {
          inherit system username homeDirectory dotfilesPath;
        };
      };
    in
    {
      # Personal Mac
      homeConfigurations."steven@stevens-mbp-14" = createConfiguration rec {
        system = "aarch64-darwin";
        username = "steven";
        homeDirectory = "/Users/${username}";
        dotfilesPath = "${homeDirectory}/dotfiles";
        extraModules = [ ./modules/personal.nix ./modules/mac-shared.nix ];
      };
      # Gigante NixOS
      homeConfigurations."steven@gigante" = createConfiguration rec {
        system = "x86_64-linux";
        username = "steven";
        homeDirectory = "/home/${username}";
        dotfilesPath = "${homeDirectory}/dotfiles";
        extraModules = [ ./modules/personal.nix ];
      };
      # Homelad NixOS LXC
      homeConfigurations."steven@homelad" = createConfiguration rec {
        system = "x86_64-linux";
        username = "steven";
        homeDirectory = "/home/${username}";
        dotfilesPath = "${homeDirectory}/dotfiles";
        extraModules = [ ./modules/personal.nix ];
      };

      apps.x86_64-linux.home-manager = {
        type = "app";
        program = "${nixpkgs.legacyPackages.x86_64-linux.home-manager}/bin/home-manager";
      };

      apps.aarch64-darwin.home-manager = {
        type = "app";
        program = "${nixpkgs.legacyPackages.aarch64-darwin.home-manager}/bin/home-manager";
      };
    };
}
