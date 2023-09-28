{ pkgs, ... }:

with pkgs;

(stdenvNoCC.mkDerivation
rec {
  pname = "gg-mono";
  version = "1.8.0";

  src = builtins.fetchGit {
    url = "https://github.com/Colophon-Foundry/discord-text-type";
    ref = "main";
    narHash = "sha256-A9Uo7P8G8m+zehcHB2wgOfNW7iUsXzMXAUZ7sH7AM84=";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/truetype
    cp -r monospace/betas/20230712-v1.001/*.ttf $out/share/fonts/truetype

    runHook postInstall
  '';
})
