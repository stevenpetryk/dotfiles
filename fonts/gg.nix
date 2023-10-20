{ pkgs, ... }:

with pkgs;

(stdenvNoCC.mkDerivation
rec {
  pname = "gg-mono";
  version = "20231018";

  src = builtins.fetchGit {
    url = "git@github.com:Colophon-Foundry/discord-text-type.git";
    ref = "HEAD";
    rev = "eea82d9006edf69c565d32a00374678044caf46c";
  };

  installPhase = ''
    mkdir -p $out/share/fonts/truetype
    cp -r betas/20231018/*.ttf $out/share/fonts/truetype
  '';
})
