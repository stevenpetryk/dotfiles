{ config, pkgs, ... }:

{
  programs.zsh.initExtra = ''
    source ${../discord/fix-coder-ssh.sh}

    eval "$(ssh-agent -s)" > /dev/null 2>&1
  '';
}
