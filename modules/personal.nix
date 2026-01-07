{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    pkgs.nodejs_22
    pkgs.rustup
    pkgs.python312
    pkgs.uv
  ];

  home.shellAliases = {
    ghpdf = "git push && gh pr create -df";
    ghlfg = "gh pr ready && gh pr merge";
    keen-mind = "~/src/keen-mind/keen-mind";
  };

  programs.git.settings = {
    user.name = "Steven Petryk";
    user.email = "petryk.steven@gmail.com";
    fetch.all = true;
  };
}
