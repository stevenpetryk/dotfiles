{ pkgs, ... }:

with pkgs;

(stdenvNoCC.mkDerivation
rec {
  pname = "gg-mono";
  version = "1.8.0";

  src = fetchFromGitHub {
    owner = "Colophon-Foundry";
    repo = "discord-text-type";
    rev = "92ab008a1864e394fa9bbc72c4ef0e36a481abc6";
    sha256 = "sha256-A9Uo7P8G8m+zehcHB2wgOfNW7iUsXzMXAUZ7sH7AM84=";
  };

  installPhase = ''
    mkdir -p $out/share/fonts/truetype
    cp -r monospace/betas/20230712-v1.001/*.ttf $out/share/fonts/truetype
  '';
})
