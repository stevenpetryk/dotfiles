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
    pkg-config
    pure-prompt
    ripgrep
    tig
    watch

    (import ./fonts/gg.nix { inherit pkgs; })

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
  ] ++ (if !isWork then [
    pkgs.nodejs_20
    pkgs.rustup
  ] else [
    (pkgs.writeScriptBin "track" ''
      git fetch origin $1:$1
      git switch $1
    '')
  ]);

  home.shellAliases = {
    gs = "git status -sb";
    ga = "git add -A";
    gc = "git commit";
    gd = "git diff";
    ghpdf = "git push && gh pr create -df";
    ghlfg = "gh pr ready && gh pr merge";
    b = "fzfbranch";
    vim = "nvim";
  } // pkgs.lib.optionalAttrs isWork {
    ghpdf = "git push --no-verify && gh pr create -df";
    ghpdfv = "git push --no-verify && gh pr create -df && gh pr view -w";
    ghlfg = "gh pr ready && gh pr comment -b '/merge'";
    claw = "WEB_ENTRY_ONLY=1 clyde app watch prod";
    unjamfme = "sudo protectctl diagnostics -d 10 -l debug";
    codeown = "clyde codeowners set-ownership --team client-developer-experience";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  # Fix 403 from outdated git source
  manual.manpages.enable = false;

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

    export PATH="$HOME/Library/pnpm/global/5/node_modules/.bin:$PATH"

    export OPENSSL_DIR="${pkgs.openssl.dev}"
    export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig"
    export OPENSSL_NO_VENDOR=1
    export OPENSSL_LIB_DIR="${pkgs.lib.getLib pkgs.openssl}/lib"

    ${if isWork then ''
      . "$HOME/.cargo/env"
    '' else ""}

    ${if isWork && system == "aarch64-darwin" then ''
      if [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        source $HOME/.nix-profile/etc/profile.d/nix.sh
      fi
      export PATH="$HOME/src/discord/.local/bin:$PATH"
    '' else ""}

    ${if isWork && system == "x86_64-linux" then ''
      source ${./discord/fix-coder-ssh.sh}
    '' else ""}
  '';

  programs.git.enable = true;
  programs.git.delta.enable = true;
  programs.git.extraConfig = {
    user.name = "Steven Petryk";
    user.email = if isWork then "steven.petryk@discordapp.com" else "petryk.steven@gmail.com";

    core.editor = "nvim";

    init.defaultBranch = "main";
    push.default = "current";
    push.autoSetupRemote = true;
    branch.autosetupmerge = true;
    fetch.prune = true;
  };
  programs.gh.enable = true;
  programs.gh.settings.git_protocol = "ssh";

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

  programs.neovim.plugins = with pkgs.vimPlugins; [
    vim-easymotion
  ];

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  fonts.fontconfig.enable = true;
}
