{ config, pkgs, system, username, ... }:

{
  home.username = username;
  home.homeDirectory = "/Users/${username}";

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

    (import ./pkgs/ast-grep.nix { inherit pkgs system; })

    (pkgs.writeScriptBin "fzfbranch" ''
      git rev-parse --is-inside-work-tree >/dev/null
      branch=$(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads/ | fzf -q "$1")
      git switch $branch
    '')

    (pkgs.writeScriptBin "cheat" ''
      curl -s "cht.sh/$1" | less -R
    '')
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
  programs.zsh.defaultKeymap = "emacs";
  programs.zsh.plugins = [
    {
      name = "zsh-k";
      file = "k.sh";
      src = pkgs.fetchFromGitHub {
        owner = "supercrabtree";
        repo = "k";
        rev = "e2bfbaf3b8ca92d6ffc4280211805ce4b8a8c19e";
        sha256 = "sha256-32rJjBzqS2e6w/L78KMNwQRg4E3sqqdAmb87XEhqbRQ=";
      };
    }
  ];

  programs.zsh.initExtra = ''
    source $HOME/.nix-profile/etc/profile.d/nix.sh

    fpath+=("${pkgs.pure-prompt}/share/zsh/site-functions")
    autoload -U promptinit; promptinit
    prompt pure

    export PATH="$HOME/src/discord/.local/bin:$PATH"
    export PATH="$HOME/Library/pnpm/global/5/node_modules/.bin:$PATH"
  '';

  programs.git.enable = true;
  programs.git.diff-so-fancy.enable = true;
  programs.git.extraConfig = {
    user.name = "Steven Petryk";
    user.email = "petryk.steven@gmail.com";

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

  fonts.fontconfig.enable = true;
}
