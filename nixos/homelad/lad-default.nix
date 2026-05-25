{ config, pkgs, lib, ... }:

# Distilled shell experience for keen-mind-dev "lads" (chris, jacob, …).
# Everything here is system-wide so it lights up the moment a lad logs in,
# with no per-user home-manager setup needed. Anything they want to override
# goes in their own ~/.zshrc — zsh sources /etc/zshrc first.
#
# Welcome banner art lives in ./keen-mind.txt next to this file and is
# installed declaratively to /etc/keen-mind.txt.

let
  # Anyone in keen-mind-dev without wheel. Auto-extends when steven adds a
  # new lad to configuration.nix without needing to touch this file.
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

  # ------------------------------------------------------------------
  # Lad welcome + startup checks.
  #
  # Runs in /etc/zshrc on every interactive shell, but the gate at the top
  # bails for anyone with `wheel` (steven and any future full-admin), so it
  # only fires for keen-mind-dev members. Runs once per shell session — the
  # HOMELAD_GREETED env var carries across spawned subshells (tmux panes,
  # nested zsh, etc.) so it doesn't spam.
  # ------------------------------------------------------------------
  programs.zsh.interactiveShellInit = ''
    # Lad-only: must be in keen-mind-dev, must NOT have full sudo.
    if ! groups | grep -qw keen-mind-dev; then return; fi
    if   groups | grep -qw wheel;         then return; fi

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

    # GitHub SSH agent — skip the network round-trip if no keys are loaded,
    # so a shell without agent forwarding stays snappy.
    gh_user=""
    if [ -n "$SSH_AUTH_SOCK" ] && ssh-add -l >/dev/null 2>&1; then
      gh_user=$(ssh -o ConnectTimeout=3 -o BatchMode=yes -T git@github.com 2>&1 \
        | sed -n 's/.*Hi \([^!]*\)!.*/\1/p')
    fi
    if [ -n "$gh_user" ]; then
      print -P "  %F{green}✓%f GitHub SSH ($gh_user)"
    else
      print -P "  %F{yellow}!%f GitHub SSH not reachable. Recommended ~/.ssh/config on your local machine:"
      print
      # Pull homelad's tailnet DNSName dynamically so a future tailnet
      # rename doesn't silently leave a stale hostname in the snippet.
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
      print -P "    Then connect with %F{cyan}ssh homelad%f — agent forwarding will be on automatically."
    fi

    # CUDA reachable? nvidia-smi -L is ~50ms.
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
      gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
      print -P "  %F{green}✓%f CUDA visible ($gpu)"
    else
      print -P "  %F{yellow}!%f CUDA not reachable"
    fi

    # keen-mind clone status.
    if [ -d ~/src/keen-mind ]; then
      print -P "  %F{green}✓%f keen-mind cloned — run %F{cyan}direnv allow%f inside if you haven't"
    else
      print -P "  %F{yellow}!%f keen-mind not cloned — try:"
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
  '';
}
