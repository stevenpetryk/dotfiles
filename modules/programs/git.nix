{ programs, ... }:
{
  programs.git = {
    enable = true;

    # Largely taken from # https://blog.gitbutler.com/how-git-core-devs-configure-git/
    settings = {
      column.ui = "auto";
      branch.sort = "-committerdate";
      tag.sort = "version:refname";
      init.defaultBranch = "main";
      help.autocorrect = "prompt";
      commit.verbose = true;
      pull.rebase = true;
      merge.conflictStyle = "diff3";

      diff = {
        algorithm = "histogram";
        colorMoved = "plain";
        mnemonicPrefix = true;
        renames = true;
      };

      fetch.prune = true;
      maintenance.auto = true;

      push = {
        default = "simple";
        autoSetupRemote = true;
      };

      rerere = {
        enabled = true;
        autoupdate = true;
      };

      rebase = {
        autoSquash = true;
        autoStash = true;
        updateRefs = true;
      };
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      dark = true;
      theme = "GitHub";
      hyperlinks-file-link-format = "vscode://file/{path}:{line}";
    };
  };

  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };
}
