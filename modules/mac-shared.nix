{ pkgs, ... }:

{
  home.packages = with pkgs; [
    pkg-config
  ];

  home.shellAliases = {
    # Reveal in Finder
    reveal = "open -R";
  };
}
