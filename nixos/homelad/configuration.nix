{
  modulesPath,
  config,
  pkgs,
  lib,
  ...
}: let
  # Keen Mind collaborators. To add a new lad, append an entry here — they
  # automatically join `keen-mind-dev` (scoped sudo) and `systemd-journal`
  # (journalctl access). Empty `sshKeys` = account exists but no SSH login.
  lads = {
    chris.sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDlsmYohoJZEudjDOnn1sOWjQUXKkHy5HCSB9m3dxoFe"
    ];
    jacob.sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINCmmlPZ75SGKwviVk4/tz3z7ANYvwrCK3oGQ6qbS3Nb"
    ];
  };
  ladUsers = lib.mapAttrs (_: lad: {
    isNormalUser = true;
    hashedPassword = "!";
    extraGroups = ["keen-mind-dev" "systemd-journal"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = lad.sshKeys;
  }) lads;
in {
  imports = [
    # Include the default lxc/lxd configuration.
    "${modulesPath}/virtualisation/lxc-container.nix"
    (builtins.getFlake "git+file:///srv/keen-mind").nixosModules.default
    ./cachix.nix
    ./lad-default.nix
  ];

  networking.hostName = "homelad";

  # Graphics
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = ["nvidia"];
  hardware.nvidia.open = false;  # Proprietary driver needed for nvidia-uvm (CUDA compute)
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.latest;
  hardware.nvidia.nvidiaSettings = true;
  hardware.nvidia.modesetting.enable = true;
  hardware.nvidia.nvidiaPersistenced = true;  # Keep GPU initialized

  # Nix
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.nixPath = [
    "nixos-config=/home/steven/dotfiles/nixos/homelad/configuration.nix"
    "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
    "/nix/var/nix/profiles/per-user/root/channels"
  ];

  boot.isContainer = true;

  environment.systemPackages = with pkgs; [
    neovim
    neofetch
    git
    rsync
  ];

  programs.direnv.enable = true;

  # Allow SSH access
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  programs.zsh.enable = true;

  users = {
    mutableUsers = false;
    groups.keen-mind-dev = {};
    users = ladUsers // {
      steven = {
        isNormalUser = true;
        hashedPassword = "!";
        extraGroups = ["wheel" "docker" "keen-mind-dev"];
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = [
          # Sync with https://github.com/stevenpetryk.keys
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA8MKWpnZktvAr8y1IKj2xXcHE+3/lLUPKvuFgBkhS0"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM4g7jMEeIdC2kBUJhAzlsytXEJcAFADQ7lDgm6OgfkK petryk.steven@gmail.com"
        ];
      };
    };
  };

  # System-wide CLAUDE.md picked up by Claude Code for every account on the
  # host. Keep it to the minimum a lad needs on first SSH-in: how to install
  # tools, what their sudo scope is, where the project lives, where logs go.
  # Project-specific guidance belongs in /srv/keen-mind/CLAUDE.md (or the
  # lad's own clone), not here. Per-user overrides go in ~/CLAUDE.md.
  environment.etc."claude-code/CLAUDE.md".text = ''
    ## Environment

    You are on NixOS in an LXC container (`homelad`). The system is
    declaratively configured — software is not installed with apt/dnf/brew.

    - Ad-hoc tools: `nix shell nixpkgs#<pkg> -c <cmd>` (or `nix-shell -p
      <pkg>` for a transient shell).
    - `direnv` is enabled; many projects auto-load their toolchain via
      `.envrc` when you `cd` in — no manual shell entry needed.
    - System config lives under `~steven/dotfiles` and is owned by steven.
      Surface needed changes to him rather than editing.

    ## Keen Mind project

    The Keen Mind project is the main work on this host.

    - Production checkout: `/srv/keen-mind` (mode 0750, owned by the
      `keen-mind` service user). You cannot read or write it.
    - To develop: clone `https://github.com/stevenpetryk/keen-mind` into
      your home directory and work from there. Project-specific guidance
      lives in that repo's `CLAUDE.md`.
    - Production data: `/var/lib/keen-mind` (mode 2750, owned
      `keen-mind:keen-mind-dev`). You can **read** it (point a local dev
      server at it via `KEEN_MIND_DATA_DIR=/var/lib/keen-mind`) but writes
      will fail with `EACCES` — that's intentional. If your task needs
      writable data, copy what you need to `~/keen-mind-data-dev/` or
      ask steven about the OverlayFS staging pattern used by the bot.

    ## Permissions (`keen-mind-dev` group)

    Your account is in `keen-mind-dev`. Passwordless sudo is scoped to:

    - `sudo systemctl start keen-mind-deploy` — pulls `origin/main` into
      `/srv/keen-mind` and rebuilds/restarts only what changed. This is how
      merged work reaches production.
    - `sudo systemctl restart keen-mind` / `keen-mind-web`

    You do not have general sudo. To ship: PR → merge → `keen-mind-deploy`.

    ## Logs

    `journalctl -u <unit>` works without sudo (`systemd-journal` group):

    - `journalctl -u keen-mind` — Discord bot
    - `journalctl -u keen-mind-web` — transcript viewer
    - `journalctl -u keen-mind-deploy` — last deploy
  '';

  security.sudo.extraRules = [
    {
      users = ["steven"];
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD"];
        }
      ];
    }
    {
      groups = ["keen-mind-dev"];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl restart keen-mind";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart keen-mind-web";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  # Supress systemd units that don't work because of LXC.
  # https://blog.xirion.net/posts/nixos-proxmox-lxc/#configurationnix-tweak
  systemd.suppressedSystemUnits = [
    "dev-mqueue.mount"
    "sys-kernel-debug.mount"
    "sys-fs-fuse-connections.mount"
  ];

  # Tailscale
  services.tailscale.enable = true;
  services.tailscale.interfaceName = "userspace-networking";

  # AI
  services.ollama.enable = true;
  services.ollama.package = pkgs.ollama-cuda;

  # Docker with GPU support (for Riva ASR)
  virtualisation.docker = {
    enable = true;
    daemon.settings.features.cdi = true;
  };
  hardware.nvidia-container-toolkit.enable = true;

  # Allow dynamically linked binaries (like the VS Code server)
  programs.nix-ld.enable = true;

  # Foundry VTT
  systemd.services.vtt = let
    launcher = pkgs.writeShellApplication {
      name = "launch-vtt";
      runtimeInputs = with pkgs; [ nodejs_20 ];
      text = ''
        cd /home/steven/src/vtt-private/resources/app/
        node main.js --port=3006 --dataPath=/var/lib/vtt --proxySSL=true --hostname=vtt.lads.games
      '';
    };
  in {
    description = "Foundry Virtual Tabletop";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "steven";
      ExecStart = "${launcher}/bin/launch-vtt";
      Restart = "always";
      RestartSec = "5";
      StateDirectory = "vtt";
    };
  };

  system.stateVersion = "24.05";

  time.timeZone = "America/Los_Angeles";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };
}
