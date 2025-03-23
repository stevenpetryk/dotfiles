{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    pkgs.nodejs_20
    pkgs.rustup
  ];

  home.shellAliases = {
    ghpdf = "git push && gh pr create -df";
    ghlfg = "gh pr ready && gh pr merge";
  };

  programs.git.extraConfig = {
    user.email = "petryk.steven@gmail.com";
    fetch.all = true;
  };
}
