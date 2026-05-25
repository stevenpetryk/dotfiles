{ config, pkgs, lib, ... }:

# Distilled shell experience for keen-mind-dev "lads" (chris, jacob, …).
# Everything here is system-wide so it lights up the moment a lad logs in,
# with no per-user home-manager setup needed. Anything they want to override
# goes in their own ~/.zshrc — zsh sources /etc/zshrc first.
#
# Welcome banner art lives in ./keen-mind.txt next to this file and is
# installed declaratively to /etc/keen-mind.txt.

let
  # Used to seed an empty ~/.zshrc per lad (see systemd.tmpfiles below).
  # Auto-extends when a new lad is added to configuration.nix. Excludes
  # wheel members so steven's home-manager-managed ~/.zshrc is left
  # alone (tmpfiles's `f` is no-op on existing files anyway, but the
  # rule shouldn't even mention steven's home).
  lads = lib.filterAttrs
    (_: u:
      builtins.elem "keen-mind-dev" (u.extraGroups or [])
      && !builtins.elem "wheel" (u.extraGroups or []))
    config.users.users;
in
{
  # CLI ergonomics for everyone on the box.
  environment.systemPackages = with pkgs; [
    eza
    fd
    ripgrep
    bat
    jq
    fzf
    tig
    tldr
    gh
    delta
    direnv
    pure-prompt
  ];

  # Zsh defaults that apply to every interactive shell. Steven's home-manager
  # re-declares most of these for his own shell, which wins because his
  # ~/.zshrc is sourced after /etc/zshrc.
  programs.zsh = {
    syntaxHighlighting.enable = true;
    autosuggestions.enable = true;
    shellAliases = {
      ll = "eza -l";
      la = "eza -la";
      gs = "git status -sb";
      gd = "git diff";
      vim = "nvim";
    };
  };

  # System-wide pure prompt — same one steven uses in his home-manager
  # setup. promptInit runs after interactiveShellInit in /etc/zshrc; steven
  # re-runs `prompt pure` in his own ~/.zshrc, which is a harmless no-op.
  programs.zsh.promptInit = ''
    fpath+=("${pkgs.pure-prompt}/share/zsh/site-functions")
    autoload -U promptinit
    promptinit
    prompt pure
  '';

  # Welcome banner ascii art, declared so /etc/keen-mind.txt survives
  # rebuilds and lives in the nix store.
  environment.etc."keen-mind.txt".source = ./keen-mind.txt;

  # Seed an empty ~/.zshrc for each lad so zsh doesn't fire its first-run
  # `zsh-newuser-install` wizard on their first shell (which would block
  # the welcome MOTD waiting for keyboard input).
  systemd.tmpfiles.rules = lib.mapAttrsToList
    (name: _: "f /home/${name}/.zshrc 0644 ${name} users -")
    lads;

  # Pre-whitelist each lad's keen-mind clone with direnv so they don't
  # have to run `direnv allow` before the dev shell loads on first cd.
  # Only seeded if no direnv.toml exists — once they've customized, we
  # leave it alone. Steven is excluded (he manages his own direnv config).
  system.activationScripts.ladDirenvConfig.text = lib.concatStringsSep "\n"
    (lib.mapAttrsToList
      (name: _: ''
        if [ -d /home/${name} ]; then
          # install -d only applies ownership to leaf paths it creates, so
          # pass both ~/.config and ~/.config/direnv explicitly. Then chown
          # the parent unconditionally to heal hosts where .config was
          # already created root-owned (which leaves tools that write into
          # ~/.config — gcloud, etc. — failing with EACCES).
          ${pkgs.coreutils}/bin/install -d -o ${name} -g users -m 0755 \
            /home/${name}/.config /home/${name}/.config/direnv
          ${pkgs.coreutils}/bin/chown ${name}:users /home/${name}/.config
          if [ ! -e /home/${name}/.config/direnv/direnv.toml ]; then
            ${pkgs.coreutils}/bin/install -o ${name} -g users -m 0644 \
              ${pkgs.writeText "direnv.toml" ''
                [whitelist]
                prefix = [ "/home/${name}/src/keen-mind" ]
              ''} \
              /home/${name}/.config/direnv/direnv.toml
          fi
        fi
      '')
      lads);

  # Expose the dotfiles repo at /srv/dotfiles so lads can read it without
  # any traversal rights on /home/steven (which stays 0700 — `.ssh`, shell
  # history, anything else under it stays invisible). Read-only bind mount
  # so even if perms drift on the source, nothing here is writable through
  # this path. `nofail` keeps the system bootable if /home/steven/dotfiles
  # is missing during a migration.
  fileSystems."/srv/dotfiles" = {
    device = "/home/steven/dotfiles";
    fsType = "none";
    options = [ "bind" "ro" "nofail" ];
  };

  # ------------------------------------------------------------------
  # Welcome + startup checks for keen-mind-dev members. Runs once per
  # shell session — the HOMELAD_GREETED env var carries across spawned
  # subshells (tmux panes, nested zsh, etc.) so it doesn't spam.
  # ------------------------------------------------------------------
  # Wrapped in a function so internal `return`s exit the greeting, not the
  # whole /etc/zshrc — NixOS appends interactiveShellInit at the top of
  # /etc/zshrc, and later lines (direnv hook, syntax highlighting, etc.)
  # would otherwise be skipped for non-keen-mind-dev or repeat-shell cases.
  programs.zsh.interactiveShellInit = ''
    _homelad_greeting() {
    # Everyone in keen-mind-dev gets the welcome (steven included — once
    # per session, gated by HOMELAD_GREETED below).
    if ! groups | grep -qw keen-mind-dev; then return; fi

    # Put ~/.local/bin on PATH — that's where the Claude Code installer
    # drops `claude`, and steven's home-manager does this for him already.
    case ":$PATH:" in
      *":$HOME/.local/bin:"*) ;;
      *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac

    # Interactive tty, once per session.
    [[ $- == *i* && -t 1 && -z "$HOMELAD_GREETED" ]] || return
    export HOMELAD_GREETED=1

    mkdir -p ~/src

    # 256-color pink (~#d787ff) — closest cube match to #EA8AF6 that
    # renders consistently on dark and light terminal backgrounds. Skip
    # the art if /etc/keen-mind.txt is missing for some reason.
    if [ -r /etc/keen-mind.txt ]; then
      print -P "%F{177}"
      cat /etc/keen-mind.txt
      print -P "%f"
    fi

    print -P "%F{177}Welcome to %Bhomelad%b, home of %BKeen Mind%b!%f"
    print

    # Step 1: SSH agent forwarding (also covers the website's step 2
    # "connect" — if the agent is working, they connected via a working
    # config; if not, we hand them a config and tell them to reconnect).
    # Skip the github round-trip if no keys are loaded, so a shell without
    # agent forwarding stays snappy.
    gh_user=""
    if [ -n "$SSH_AUTH_SOCK" ] && ssh-add -l >/dev/null 2>&1; then
      gh_user=$(ssh -o ConnectTimeout=3 -o BatchMode=yes -T git@github.com 2>&1 \
        | sed -n 's/.*Hi \([^!]*\)!.*/\1/p')
    fi
    if [ -n "$gh_user" ]; then
      print -P "  %F{green}✓%f SSH agent forwarded (GitHub: $gh_user)"
    else
      print -P "  %F{yellow}!%f SSH agent not forwarded. Recommended ~/.ssh/config on your local machine:"
      print
      tailnet=$(tailscale status --self --json 2>/dev/null \
        | jq -r '.Self.DNSName // empty' 2>/dev/null \
        | sed 's/\.$//')
      : "''${tailnet:=homelad}"
      bat --plain --paging=never --color=always --language=ssh_config <<EOF | sed 's/^/    /'
    Host homelad
            HostName $tailnet
            User $USER
            ForwardAgent yes
    EOF
      print
      print -P "    Then %F{cyan}exit%f and reconnect with %F{cyan}ssh homelad%f."
    fi

    # Step 3: Claude Code installed (binary lives at ~/.local/bin/claude,
    # which the PATH export above makes discoverable).
    if command -v claude >/dev/null 2>&1; then
      print -P "  %F{green}✓%f Claude Code installed"
    else
      print -P "  %F{yellow}!%f Claude Code not installed — run:"
      print -P "       %F{cyan}curl -fsSL https://claude.ai/install.sh | bash%f"
    fi

    # Step 4: keen-mind cloned (direnv is pre-whitelisted for the path).
    if [ -d ~/src/keen-mind ]; then
      print -P "  %F{green}✓%f keen-mind cloned at ~/src/keen-mind"
    else
      print -P "  %F{yellow}!%f keen-mind not cloned — run:"
      print -P "       %F{cyan}git clone git@github.com:stevenpetryk/keen-mind ~/src/keen-mind%f"
    fi

    print
    print "Orientation: /etc/claude-code/CLAUDE.md"
    print

    # Land them where the work is.
    if [ -d ~/src/keen-mind ]; then
      cd ~/src/keen-mind
    else
      cd ~/src
    fi
    }
    _homelad_greeting
    unset -f _homelad_greeting
  '';
}
