{ config, pkgs, ... }:

{
  programs.zsh.initExtra = ''
    source ${../discord/fix-coder-ssh.sh}
  '';
}
