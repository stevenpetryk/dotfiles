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
    in {
      # Personal
      homeConfigurations."steven" = createConfiguration rec {
        system = "x86_64-darwin";
        username = "steven";
        homeDirectory = "/Users/${username}";
        isWork = false;
      };
      # Work Mac
      homeConfigurations."steven.petryk" = createConfiguration rec {
        system = "x86_64-darwin";
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
    };
}
