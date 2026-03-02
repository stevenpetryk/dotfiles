{
  description = "My dotfiles";

  inputs = {
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
  };

  outputs = { nixpkgs-stable, nixpkgs-unstable, home-manager, ... }:
    let
      createConfiguration = { system, username, homeDirectory, dotfilesPath, extraModules, pkgs }: home-manager.lib.homeManagerConfiguration {
        pkgs = pkgs.legacyPackages.${system};

        modules = [
          ./modules/shared.nix
          ./modules/programs/git.nix
          ./modules/programs/slync.nix
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
        dotfilesPath = "${homeDirectory}/.config/home-manager";
        extraModules = [ ./modules/personal.nix ./modules/mac-shared.nix ];
        pkgs = nixpkgs-stable;
      };
      # Gigante NixOS
      homeConfigurations."steven@gigante" = createConfiguration rec {
        system = "x86_64-linux";
        username = "steven";
        homeDirectory = "/home/${username}";
        dotfilesPath = "${homeDirectory}/dotfiles";
        extraModules = [ ./modules/personal.nix ];
        pkgs = nixpkgs-stable;
      };
      # Homelad NixOS LXC - uses unstable to support the Proxmox host's newer NVIDIA kernel driver
      homeConfigurations."steven@homelad" = createConfiguration rec {
        system = "x86_64-linux";
        username = "steven";
        homeDirectory = "/home/${username}";
        dotfilesPath = "${homeDirectory}/dotfiles";
        extraModules = [ ./modules/personal.nix ];
        pkgs = nixpkgs-unstable;
      };

      apps.x86_64-linux.home-manager = {
        type = "app";
        program = "${nixpkgs-stable.legacyPackages.x86_64-linux.home-manager}/bin/home-manager";
      };

      apps.aarch64-darwin.home-manager = {
        type = "app";
        program = "${nixpkgs-stable.legacyPackages.aarch64-darwin.home-manager}/bin/home-manager";
      };
    };
}
