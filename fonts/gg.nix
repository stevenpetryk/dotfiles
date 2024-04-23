{ pkgs, ... }:

with pkgs;

(stdenvNoCC.mkDerivation
rec {
  pname = "gg-mono";
  version = "20231211";

  src = builtins.fetchGit {
    url = "git@github.com:Colophon-Foundry/discord-text-type.git";
    ref = "HEAD";
    rev = "ee4aab6888f4e8996cf099f0066eebb7c72db451";
  };

  installPhase = ''
    mkdir -p $out/share/fonts/truetype
    cp -r release/Mono/20231211-v1.001/TTF/*.ttf $out/share/fonts/truetype
  '';
})
