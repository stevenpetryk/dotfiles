{ config, pkgs, ... }:

{
  programs.zsh.initExtra = ''
    if [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      source $HOME/.nix-profile/etc/profile.d/nix.sh
    fi
    export PATH="$HOME/src/discord/.local/bin:$PATH"
  '';
}
