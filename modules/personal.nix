{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    pkgs.nodejs_20
    pkgs.rustup
  ];

  programs.git.extraConfig = {
    user.email = "petryk.steven@gmail.com";
  };
}
