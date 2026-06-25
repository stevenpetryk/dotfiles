# gpulad — NixOS GPU appliance, the consolidated keen-mind host.
# PVE VM 102, RTX 5060 Ti (GB206/Blackwell) via PCIe passthrough (hostpci 01:00).
#
# Runs the full keen-mind / lads / services stack on VM boot with the open
# Blackwell nvidia driver. (This replaced the old homelad LXC, which has been
# decommissioned.)
{ config, pkgs, lib, ... }:
let
  # Keen Mind collaborators.
  lads = {
    chris.sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDlsmYohoJZEudjDOnn1sOWjQUXKkHy5HCSB9m3dxoFe"
    ];
    jacob.sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINCmmlPZ75SGKwviVk4/tz3z7ANYvwrCK3oGQ6qbS3Nb"
    ];
    bill.sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO/3b6bqPsuEZbMW3UIsZx32F2/RaD6h/fp+eFfnyJRX billspc-to-workstation"
    ];
    zach.sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOidWXi8sgA25CFz/N62jOCmf+gYsBkTK6g3HrP41XEB"
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
    ./hardware-configuration.nix
    (builtins.getFlake "git+file:///srv/keen-mind").nixosModules.default
    ./cachix.nix
    ./lad-default.nix
  ];

  # --- Boot: BIOS GRUB (matches the nixos-generators image disk layout) ---
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.efiSupport = false;

  networking.hostName = "gpulad";
  networking.useDHCP = lib.mkDefault true;

  # --- NVIDIA: RTX 5060 Ti (Blackwell GB206), real VFIO passthrough ---
  # The VM loads the actual kernel driver (unlike the LXC, which borrowed
  # /dev/nvidia* from the pve host), so Blackwell needs the OPEN modules + beta
  # package. nvidiaPersistenced keeps the GPU initialized for the always-on
  # inference/ollama loads.
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = ["nvidia"];
  hardware.nvidia = {
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.beta;
    modesetting.enable = true;
    nvidiaSettings = false;
    nvidiaPersistenced = true;
  };

  # Nix
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.nixPath = [
    "nixos-config=/home/steven/dotfiles/nixos/gpulad/configuration.nix"
    "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
    "/nix/var/nix/profiles/per-user/root/channels"
  ];

  environment.systemPackages = with pkgs; [
    neovim neofetch git rsync htop pciutils nvtopPackages.nvidia uv
  ];

  # --- Collaborative NAS share (TrueNAS, NFS over the 40G path) ---
  # Browsed/edited by the "Files" tab via keen-mind-web, which writes here as
  # the keen-mind user through its `users` supplementary group (see the
  # keen-mind module's keen-mind-web unit). That unit's RequiresMountsFor holds
  # it until this mount is up, so land this and the unit change in one switch.
  fileSystems."/mnt/nas-media" = {
    device = "10.40.40.2:/mnt/Bulk/CT_Media";
    fsType = "nfs";
    options = ["nfsvers=4.2" "hard" "noatime" "_netdev" "rsize=1048576" "wsize=1048576"];
  };

  # Grant keen-mind-dev read access to the Agent SDK session transcripts the
  # bot/coordinator write under their homes (0700 keen-mind, jsonl 0600).
  system.activationScripts.keen-mind-agent-home-acls = ''
    for home in /var/lib/keen-mind-bot-home /var/lib/keen-mind-coordinator-home; do
      projects="$home/.claude/projects"
      [ -d "$projects" ] || continue
      ${pkgs.acl}/bin/setfacl -R -m g:keen-mind-dev:rX "$projects"
      ${pkgs.findutils}/bin/find "$projects" -type d -exec \
        ${pkgs.acl}/bin/setfacl -d -m g:keen-mind-dev:rX {} +
    done
  '';

  programs.direnv.enable = true;

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
        extraGroups = ["wheel" "keen-mind-dev"];
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = [
          # Sync with https://github.com/stevenpetryk.keys
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA8MKWpnZktvAr8y1IKj2xXcHE+3/lLUPKvuFgBkhS0"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM4g7jMEeIdC2kBUJhAzlsytXEJcAFADQ7lDgm6OgfkK petryk.steven@gmail.com"
        ];
      };
    };
  };

  # System-wide CLAUDE.md for every account on the host — kept deliberately
  # minimal so it orients without drowning agents in detail.
  environment.etc."claude-code/CLAUDE.md".text = ''
    ## Environment

    You are on NixOS in a Proxmox VM (`gpulad`, the GPU host). The system is
    declaratively configured — software is not installed with apt/dnf/brew.

    - Ad-hoc tools: `nix shell nixpkgs#<pkg> -c <cmd>` (or `nix-shell -p
      <pkg>` for a transient shell).
    - `direnv` is enabled; many projects auto-load their toolchain via
      `.envrc` when you `cd` in — no manual shell entry needed.
    - System config (NixOS + home-manager) is published read-only at
      `/srv/dotfiles` (a bind mount of steven's working tree; `~steven`
      itself stays private). `cat`, `grep`, and `find` there to answer
      "how is X configured on this host" — writes will fail with EROFS.
      Surface needed changes to steven rather than trying to apply them
      yourself.

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
    - `sudo systemctl restart keen-mind` / `keen-mind-web` /
      `keen-mind-scheduler` / `keen-mind-ingress`

    You do not have general sudo. To ship: PR → merge → `keen-mind-deploy`.

    ## Logs

    `journalctl -u <unit>` works without sudo (`systemd-journal` group):

    - `journalctl -u keen-mind` — Discord bot
    - `journalctl -u keen-mind-web` — transcript viewer
    - `journalctl -u keen-mind-scheduler` — schedule firing loop
    - `journalctl -u keen-mind-ingress` — webhook ingress (hooks.lads.games)
    - `journalctl -u nats` — firehose broker (NATS JetStream)
    - `journalctl -u keen-mind-deploy` — last deploy

    ## Firehose

    A NATS JetStream event bus runs on `127.0.0.1:4222` carrying Discord,
    recording, pipeline, deploy, cron, and GitHub-webhook events. A read-only
    debugging credential is shared with the group:

    `nats sub --server nats://127.0.0.1:4222 --nkey /var/secrets/keen-mind/dev-shared/nats-dev.nk '>'`

    See the keen-mind repo's CLAUDE.md ("Firehose") and SECURITY.md for the
    subject catalog and trust rules.
  '';

  security.sudo.extraRules = [
    {
      users = ["steven"];
      commands = [
        { command = "ALL"; options = ["NOPASSWD"]; }
      ];
    }
    {
      groups = ["keen-mind-dev"];
      commands = [
        { command = "/run/current-system/sw/bin/systemctl restart keen-mind"; options = ["NOPASSWD"]; }
        { command = "/run/current-system/sw/bin/systemctl restart keen-mind-web"; options = ["NOPASSWD"]; }
        { command = "/run/current-system/sw/bin/systemctl restart keen-mind-scheduler"; options = ["NOPASSWD"]; }
        { command = "/run/current-system/sw/bin/systemctl restart keen-mind-ingress"; options = ["NOPASSWD"]; }
      ];
    }
  ];

  # Tailscale — real kernel networking on the VM (no userspace-networking).
  services.tailscale.enable = true;

  # Eternal Terminal — remote shell that survives network drops and IP roams.
  # Auth piggybacks on SSH (et bootstraps over port 22, then holds the session
  # on 2022). Exposed on the tailnet only, matching how lads reach this host.
  services.eternal-terminal.enable = true;
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 2022 ];
  # The upstream module runs etserver with --daemon (Type=forking) but sets no
  # PIDFile, so systemd loses the double-forked daemon and marks the unit dead —
  # breaking restart-on-failure and spawning duplicates on restart. etserver
  # writes /run/etserver.pid by default; point systemd at it.
  systemd.services.eternal-terminal.serviceConfig.PIDFile = "/run/etserver.pid";

  programs.nix-ld.enable = true;

  services.qemuGuest.enable = true;

  # Foundry VTT — vtt.lads.games
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

  # gpulad was installed at 25.11 (per-host; governs stateful defaults).
  system.stateVersion = "25.11";

  # Pacific — the scheduler's cron semantics assume this timezone.
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
