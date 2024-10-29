{ config, pkgs, system, username, homeDirectory, isWork, ... }:

{
  home.username = username;
  home.homeDirectory = homeDirectory;

  home.stateVersion = "23.05";

  home.packages = with pkgs; [
    asciiquarium
    coreutils
    ffmpeg
    hyperfine
    imagemagick
    lz4
    ncdu
    neofetch
    neovim
    nixpkgs-fmt
    pngquant
    pure-prompt
    ripgrep
    tig
    tree
    watch
    youtube-dl

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

  programs.home-manager.enable = true;

  programs.zsh.enable = true;
  programs.zsh.enableSyntaxHighlighting = true;
  programs.zsh.enableAutosuggestions = true;
  programs.zsh.autocd = true;
  programs.zsh.defaultKeymap = "emacs";

  programs.zsh.initExtra = ''
    fpath+=("${pkgs.pure-prompt}/share/zsh/site-functions")
    autoload -U promptinit; promptinit
    prompt pure

    export PATH="$HOME/Library/pnpm/global/5/node_modules/.bin:$PATH"

    ${if isWork then ''
      . "$HOME/.cargo/env"
    '' else ""}

    ${if isWork && system == "aarch64-darwin" then ''
      source $HOME/.nix-profile/etc/profile.d/nix.sh
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
  programs.fzf.enableZshIntegration = true;

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
