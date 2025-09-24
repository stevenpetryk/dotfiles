{ config, pkgs, system, username, homeDirectory, isWork, ... }:

{
  home.username = username;
  home.homeDirectory = homeDirectory;

  home.stateVersion = "24.11";

  home.packages = with pkgs; [
    coreutils
    ffmpeg
    hyperfine
    imagemagick
    ncdu
    neovim
    nixpkgs-fmt
    openssl
    pure-prompt
    ripgrep
    tig
    watch

    (pkgs.writeScriptBin "fzfbranch" ''
      git branch --sort=-committerdate --format="%(refname:short)" |
      fzf \
        --ansi \
        --bind "enter:execute(echo {} | xargs git checkout)+abort" \
        --bind "ctrl-o:execute(echo {} | xargs | pbcopy)" \
        --bind "ctrl-p:execute(echo {} | xargs gh pr view --web)" \
        --preview="echo {} | xargs -I{} git diff --stat --color \$(git merge-base {} main) {}" \
        --preview-window 'right,70%'
    '')

    (pkgs.writeScriptBin "cheat" ''
      curl -s "cht.sh/$1" | less -R
    '')

    (pkgs.writeScriptBin "ql" ''
      nohup qlmanage -p $1 >/dev/null 2>&1 &
    '')
  ];

  home.shellAliases = {
    gs = "git status -sb";
    ga = "git add -A";
    gc = "git commit";
    gd = "git diff";
    ghw = "gh pr view --web";
    b = "fzfbranch";
    vim = "nvim";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  programs.home-manager.enable = true;

  programs.zsh.enable = true;
  programs.zsh.syntaxHighlighting.enable = true;
  programs.zsh.autosuggestion.enable = true;
  programs.zsh.autocd = true;
  programs.zsh.defaultKeymap = "emacs";

  programs.zsh.initExtra = ''
    fpath+=("${pkgs.pure-prompt}/share/zsh/site-functions")
    autoload -U promptinit; promptinit
    prompt pure

    export PATH="$HOME/.local/bin:$PATH"

    export OPENSSL_DIR="${pkgs.openssl.dev}"
    export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig"
    export OPENSSL_NO_VENDOR=1
    export OPENSSL_LIB_DIR="${pkgs.lib.getLib pkgs.openssl}/lib"
  '';

  programs.fzf.enable = true;

  programs.atuin.enable = true;
  programs.atuin.enableZshIntegration = true;
  programs.atuin.flags = [
    "--disable-up-arrow"
  ];

  programs.htop.enable = true;

  programs.bat.enable = true;

  programs.zoxide.enable = true;
  programs.zoxide.enableZshIntegration = true;

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}
