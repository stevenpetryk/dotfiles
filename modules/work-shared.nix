{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    (pkgs.writeScriptBin "track" ''
      git fetch origin $1:$1
      git switch $1
    '')
  ];

  home.shellAliases = {
    ghlfg = "gh pr ready && gh pr comment -b '/merge'";
    claw = "WEB_ENTRY_ONLY=1 clyde app watch prod";
    unjamfme = "sudo protectctl diagnostics -d 10 -l debug";
    codeown = "clyde codeowners set-ownership --team client-developer-experience";
  };

  programs.zsh.initExtra = ''
    . "$HOME/.cargo/env"
  '';

  programs.git.extraConfig = {
    user.email = "steven.petryk@discordapp.com";
  };
}
