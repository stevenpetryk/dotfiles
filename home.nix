{ config, pkgs, ... }:

{
  home.username = "steven";
  home.homeDirectory = "/Users/steven";

  home.stateVersion = "23.05";

  home.packages = with pkgs; [
    coreutils
    ffmpeg
    hyperfine
    imagemagick
    lz4
    ncdu
    neovim
    nixpkgs-fmt
    ripgrep
    tig
    tree
    watch
    youtube-dl
  ];

  home.shellAliases = {
    gs = "git status -sb";
    ga = "git add -A";
    gc = "git commit";
    gd = "git diff";
    ghpdf = "git push && gh pr create -df";
    ghlfg = "gh pr ready && gh pr comment -b '/merge'";
    claw = "WEB_ENTRY_ONLY=1 clyde app watch prod";
    b = "fzfbranch";
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
  programs.zsh.initExtra = ''
    source /Users/steven/.nix-profile/etc/profile.d/nix.sh
    fzfbranch() {
      git rev-parse --is-inside-work-tree >/dev/null
      branch=$(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads/ | fzf -q "$1")
      git switch $branch
    }
  '';

  programs.git.enable = true;
  programs.git.diff-so-fancy.enable = true;
  programs.git.extraConfig = {
    user.name = "Steven Petryk";
    user.email = "petryk.steven@gmail.com";
    init.defaultBranch = "main";
    push.default = "current";
    branch.autosetupmerge = true;
    core.editor = "vim";
  };
  programs.gh.enable = true;

  programs.fzf.enable = true;
  programs.fzf.enableZshIntegration = true;

  programs.bat.enable = true;

  programs.autojump.enable = true;
  programs.autojump.enableZshIntegration = true;

  programs.zsh.prezto.enable = true;
  programs.zsh.prezto.prompt.theme = "pure";
}
