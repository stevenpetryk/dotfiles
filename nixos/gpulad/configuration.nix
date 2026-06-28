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
  ladUsers = lib.mapAttrs
    (_: lad: {
      isNormalUser = true;
      hashedPassword = "!";
      extraGroups = [ "keen-mind-dev" "systemd-journal" ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = lad.sshKeys;
    })
    lads;
in
{
  imports = [
    ./hardware-configuration.nix
    (builtins.getFlake "git+file:///srv/keen-mind").nixosModules.default
    (builtins.getFlake "git+file:///srv/clad").nixosModules.default
    ./cachix.nix
    ./lad-default.nix
    ./clad-egress.nix
  ];

  # Clad — Claude's Discord harness (module + code at /srv/clad, runs as the
  # `clad` user). Watches #hackathon + the dogfood channel.
  services.clad.watchChannels = [
    "1361455253769158914" # #hackathon
    "1513218557494952046" # #keen-mind-dreams (dogfood)
  ];

  # Surface clad's Claude Agent SDK transcripts in the lads.games debug tab.
  # keen-mind stays clad-agnostic; this host-side env points keen-mind-web at
  # clad's home (read access granted by the ACL in clad's nixos module).
  systemd.services.keen-mind-web.environment.KEEN_MIND_EXTRA_AGENT_HOMES =
    builtins.toJSON [
      { label = "clad"; home = "/var/lib/clad"; color = "#a78bfa"; }
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
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.beta;
    modesetting.enable = true;
    nvidiaSettings = false;
    nvidiaPersistenced = true;
  };

  # Nix
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.nixPath = [
    "nixos-config=/home/steven/dotfiles/nixos/gpulad/configuration.nix"
    "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
    "/nix/var/nix/profiles/per-user/root/channels"
  ];

  environment.systemPackages = with pkgs; [
    neovim
    neofetch
    git
    rsync
    htop
    pciutils
    nvtopPackages.nvidia
    uv
  ];

  # --- 40G storage link to the TrueNAS (10.40.40.0/29) ---
  # Static, because the storage segment has no DHCP. This used to be set
  # imperatively (`ip addr add 10.40.40.3/29 dev ens19`), which silently
  # vanished on the 2026-06-25 reboot and took both NAS mounts below down with
  # it. Declared here so a reboot can't drop it again. useDHCP=false also stops
  # the NIC pointlessly soliciting a lease that never comes.
  networking.interfaces.ens19 = {
    useDHCP = false;
    mtu = 9000; # jumbo frames, matches the NAS side
    ipv4.addresses = [{ address = "10.40.40.3"; prefixLength = 29; }];
  };

  # --- Collaborative NAS share (TrueNAS, NFS over the 40G path) ---
  # Browsed/edited by the "Files" tab via keen-mind-web, which writes here as
  # the keen-mind user through its `users` supplementary group (see the
  # keen-mind module's keen-mind-web unit). That unit's RequiresMountsFor holds
  # it until this mount is up, so land this and the unit change in one switch.
  fileSystems."/mnt/nas-media" = {
    device = "10.40.40.2:/mnt/Bulk/CT_Media";
    fsType = "nfs";
    options = [ "nfsvers=4.2" "hard" "noatime" "_netdev" "rsize=1048576" "wsize=1048576" ];
  };

  # --- App-data backups (TrueNAS, same 40G NFS path as nas-media) ---
  # Holds the encrypted restic repo for /var/lib/keen-mind. The restic unit
  # below RequiresMountsFor this path, so they land in one switch.
  fileSystems."/mnt/nas-backups" = {
    device = "10.40.40.2:/mnt/Bulk/Nixos_Backups";
    fsType = "nfs";
    options = [ "nfsvers=4.2" "hard" "noatime" "_netdev" ];
  };

  # Daily encrypted, versioned, deduplicated backup of the keen-mind data dir.
  # Denylist, not allowlist: back up the whole tree and exclude only what we
  # can regenerate, so a new data dir is captured automatically rather than
  # silently dropped. SQLite DBs are excluded live and captured as consistent
  # `.backup` dumps under db-dumps/ (never a raw WAL copy). Repo is encrypted
  # at rest, so the NAS can push it offsite to B2 without leaking voice data.
  services.restic.backups.keen-mind = {
    repository = "/mnt/nas-backups/keen-mind/restic";
    passwordFile = "/var/secrets/keen-mind/restic-password";
    initialize = true;
    backupPrepareCommand = ''
      mkdir -p /var/lib/keen-mind/db-dumps
      for db in rag analytics scheduler; do
        ${pkgs.sqlite}/bin/sqlite3 /var/lib/keen-mind/$db.db \
          ".backup '/var/lib/keen-mind/db-dumps/$db.db'"
      done
    '';
    paths = [ "/var/lib/keen-mind" ];
    exclude = [
      "node_modules"
      "venvs"
      "nltk_data"
      "models"
      # /var/lib/keen-mind doubles as the service's $HOME, so its home-dir
      # caches (HF/uv/pip models, bun, etc.) land here — all regenerable.
      ".cache"
      ".bun"
      ".nv"
      "/var/lib/keen-mind/.local"
      "/var/lib/keen-mind/recordings/combined"
      "/var/lib/keen-mind/soundboard/normalized"
      "/var/lib/keen-mind/soundboard/embeddings.bin"
      "/var/lib/keen-mind/soundboard/upload-drafts"
      "/var/lib/keen-mind/rag.db"
      "/var/lib/keen-mind/analytics.db"
      "/var/lib/keen-mind/scheduler.db"
      "*.backup-pre-*"
      "*.pre-*-bak"
      "*-wal"
      "*-shm"
    ];
    timerConfig = { OnCalendar = "daily"; RandomizedDelaySec = "1h"; };
    pruneOpts = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 12" ];
  };

  # The restic module doesn't know its repo lives on NFS — hold the unit until
  # the mount is up so a slow-NFS boot can't initialize an empty repo.
  systemd.services.restic-backups-keen-mind.unitConfig.RequiresMountsFor = "/mnt/nas-backups";

  # Daily encrypted backup of the Foundry VTT data dir (worlds/systems/modules/
  # Config). This is the safety net for the 12→14 upgrade: world migrations are
  # one-way on first launch, so a snapshot must exist before anyone pulls the
  # trigger. Same NFS repo path + offsite story as keen-mind above.
  services.restic.backups.vtt = {
    repository = "/mnt/nas-backups/vtt/restic";
    passwordFile = "/var/secrets/vtt/restic-password";
    initialize = true;
    paths = [ "/var/lib/vtt" ];
    exclude = [
      "node_modules"
      ".cache"
      ".nix-defexpr"
      # Foundry's own rotating logs — regenerable.
      "/var/lib/vtt/Logs"
      "*-wal"
      "*-shm"
    ];
    timerConfig = { OnCalendar = "daily"; RandomizedDelaySec = "1h"; };
    pruneOpts = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 12" ];
  };
  systemd.services.restic-backups-vtt.unitConfig.RequiresMountsFor = "/mnt/nas-backups";

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
    groups.keen-mind-dev = { };
    groups.vtt = { };
    users = ladUsers // {
      # Foundry VTT service user. Primary group `vtt`, but the unit runs with
      # supplementary group `keen-mind-dev` (see systemd.services.vtt) so the
      # app + data dirs are group-owned by the dev group and the lads can run
      # the update end-to-end (swap app, migrate worlds) without steven.
      vtt = {
        isSystemUser = true;
        group = "vtt";
        home = "/var/lib/vtt";
        description = "Foundry Virtual Tabletop";
      };
      steven = {
        isNormalUser = true;
        hashedPassword = "!";
        extraGroups = [ "wheel" "keen-mind-dev" ];
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
    - Production data: `/var/lib/keen-mind` (mode 2770, owned
      `keen-mind:keen-mind-dev`). Your group can **read and write** it —
      point a local dev server at it via
      `KEEN_MIND_DATA_DIR=/var/lib/keen-mind`, and edit/curate it in place.
      The data dir is backed up daily (restic), which is what makes the
      writable posture safe; still, treat destructive edits with care since
      everyone in the group shares this tree and the live services read it.

    ## Permissions (`keen-mind-dev` group)

    Your account is in `keen-mind-dev`. Passwordless sudo is scoped to:

    - `sudo systemctl start keen-mind-deploy` — pulls `origin/main` into
      `/srv/keen-mind` and rebuilds/restarts only what changed. This is how
      merged work reaches production.
    - `sudo systemctl restart keen-mind` / `keen-mind-web` /
      `keen-mind-scheduler`
    - `sudo systemctl restart vtt` — Foundry VTT (vtt.lads.games)

    You do not have general sudo. To ship: PR → merge → `keen-mind-deploy`.

    ## Foundry VTT (vtt.lads.games)

    A patched Foundry checkout. App code at `/srv/vtt` and data at
    `/var/lib/vtt` are both group-owned `vtt:keen-mind-dev`, mode 2770 — your
    group can **read and write** both, and restart the unit (see above). The
    data dir is backed up daily (restic), so the worlds survive the one-way
    migration the 12→14 upgrade triggers. Logs: `journalctl -u vtt`.

    ## Logs

    `journalctl -u <unit>` works without sudo (`systemd-journal` group):

    - `journalctl -u keen-mind` — Discord bot
    - `journalctl -u keen-mind-web` — transcript viewer
    - `journalctl -u keen-mind-scheduler` — schedule firing loop
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
      users = [ "steven" ];
      commands = [
        { command = "ALL"; options = [ "NOPASSWD" ]; }
      ];
    }
    {
      groups = [ "keen-mind-dev" ];
      commands = [
        { command = "/run/current-system/sw/bin/systemctl restart keen-mind"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl restart keen-mind-web"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl restart keen-mind-scheduler"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl restart vtt"; options = [ "NOPASSWD" ]; }
      ];
    }
    # Clad's scoped NOPASSWD set. Declared HERE (steven-owned, clad-unwritable)
    # rather than in clad's own module (/srv/clad, which clad can edit) so clad
    # cannot rewrite the definition of its own privileges. See the TRUST POSTURE
    # comment in clad's nixos/module.nix. Deliberately EXCLUDES `nixos-rebuild
    # switch` (clad must not apply host config / widen its own grant) and
    # `keen-mind-deploy-force` (clad must not bypass the pre-deploy security
    # review) — clad deploys keen-mind only via the reviewed `keen-mind-deploy`.
    {
      users = [ "clad" ];
      commands = [
        { command = "/run/current-system/sw/bin/systemctl start keen-mind-deploy"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl restart keen-mind"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl restart keen-mind-web"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl restart keen-mind-scheduler"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl restart keen-mind-coordinator"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl restart clad"; options = [ "NOPASSWD" ]; }
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
  # keen-mind dev servers (vite browser-facing :800x + proxied API) run in the
  # 8000-8049 range and are meant to be reached over MagicDNS. The native
  # nftables backend (enabled in clad-egress.nix) stopped honoring tailscale's
  # accept-all-on-tailscale0 rule, so dev ports must be allowed explicitly.
  networking.firewall.interfaces.tailscale0.allowedTCPPortRanges = [
    { from = 8000; to = 8999; }
  ];
  # The upstream module runs etserver with --daemon (Type=forking) but sets no
  # PIDFile, so systemd loses the double-forked daemon and marks the unit dead —
  # breaking restart-on-failure and spawning duplicates on restart. etserver
  # writes /run/etserver.pid by default; point systemd at it.
  systemd.services.eternal-terminal.serviceConfig.PIDFile = "/run/etserver.pid";

  programs.nix-ld.enable = true;

  services.qemuGuest.enable = true;

  # Foundry VTT — vtt.lads.games
  #
  # App code lives at /srv/vtt (group-owned vtt:keen-mind-dev, mode 2770) — a
  # patched Foundry checkout, the source of truth for what's running. The unit
  # runs as the `vtt` user with supplementary group `keen-mind-dev`, and the
  # data dir /var/lib/vtt (StateDirectory, mode 2770) is owned vtt:keen-mind-dev.
  # Both group-writable so the lads can run the 12→14 update end-to-end (swap the
  # app, migrate worlds) without steven's hands — see security.sudo.extraRules
  # for the restart scope and services.restic.backups.vtt for the daily backup.
  systemd.services.vtt =
    let
      launcher = pkgs.writeShellApplication {
        name = "launch-vtt";
        runtimeInputs = with pkgs; [ nodejs_20 ];
        text = ''
          cd /srv/vtt/resources/app/
          node main.js --port=3006 --dataPath=/var/lib/vtt --proxySSL=true --hostname=vtt.lads.games
        '';
      };
    in
    {
      description = "Foundry Virtual Tabletop";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "vtt";
        Group = "keen-mind-dev";
        ExecStart = "${launcher}/bin/launch-vtt";
        Restart = "always";
        RestartSec = "5";
        StateDirectory = "vtt";
        StateDirectoryMode = "2770";
        # Files Foundry writes under the data dir inherit group rw, so the dev
        # group can read/write the migrated worlds.
        UMask = "0007";
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
