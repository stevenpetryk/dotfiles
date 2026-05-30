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
    bill.sshKeys = [];
    zach.sshKeys = [];
  };
  ladUsers = lib.mapAttrs (_: lad: {
    isNormalUser = true;
    hashedPassword = "!";
    extraGroups = ["keen-mind-dev" "systemd-journal"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = lad.sshKeys;
  }) lads;

  # Reads lads.json and upserts each lad into calibre-web's user db as a full
  # admin (username = their name, login keyed on email). Runs as root because
  # calibre-web deliberately stays out of keen-mind-dev — it must not be able to
  # read /var/lib/keen-mind — so it can't read lads.json itself.
  calibreSeederPython = pkgs.python3.withPackages (ps: [ps.werkzeug]);
  calibreSeeder = pkgs.writeText "calibre-web-seed.py" ''
    import json, sqlite3, secrets
    from werkzeug.security import generate_password_hash

    APP_DB = "/var/lib/calibre-web/app.db"
    LADS = "/var/lib/keen-mind/lads.json"

    # constants.ADMIN_USER_ROLES (all roles except ROLE_ANONYMOUS) and
    # constants.ADMIN_USER_SIDEBAR ((SIDEBAR_LIST << 1) - 1) from calibre-web.
    ALL_ROLES = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 6) | (1 << 7) | (1 << 8)
    ALL_SIDEBAR = (1 << 18) - 1

    lads = json.load(open(LADS))
    # Open existing-only: never create the db ourselves (calibre-web owns it and
    # creates it on first start; a root-created file would lock calibre-web out).
    db = sqlite3.connect(f"file:{APP_DB}?mode=rw", uri=True)
    for lad in lads:
        name, email = lad["name"], lad["email"]
        row = db.execute("SELECT id FROM user WHERE lower(email) = lower(?)", (email,)).fetchone()
        if row:
            db.execute("UPDATE user SET name = ?, role = ? WHERE id = ?", (name, ALL_ROLES, row[0]))
        else:
            db.execute(
                "INSERT INTO user (name, email, password, role, sidebar_view, locale, "
                "default_language, denied_tags, allowed_tags, denied_column_value, "
                "allowed_column_value, view_settings, kindle_mail, kobo_only_shelves_sync) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (name, email, generate_password_hash(secrets.token_urlsafe(32)), ALL_ROLES,
                 ALL_SIDEBAR, "en", "all", "", "", "", "", "{}", "", 0),
            )
    # Retire the bootstrap admin calibre-web auto-creates (known default
    # password); the seeded lads are all admins, so one is always left.
    db.execute("DELETE FROM user WHERE name = 'admin'")
    db.commit()
    db.close()
    print(f"Seeded {len(lads)} calibre-web users")
  '';
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
        {
          command = "/run/current-system/sw/bin/systemctl restart keen-mind-scheduler";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart keen-mind-ingress";
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

  # Calibre-Web — ebook library at calibre.lads.games. Loopback-only; the
  # Cloudflare tunnel + Access front it like the other web apps, and reverse-
  # proxy auth trusts the Access-verified email header (same pattern Grafana
  # uses above). Kobo sync is deliberately not wired up yet.
  services.calibre-web = {
    enable = true;
    listen.ip = "127.0.0.1";
    listen.port = 3007;
    dataDir = "/var/lib/calibre-web";
    # Reverse-proxy login matches the header against username by default; patch
    # it to match the email column instead so usernames stay friendly (the
    # lad's name) while login keys off Cf-Access-Authenticated-User-Email.
    package = pkgs.calibre-web.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace src/calibreweb/cps/usermanagement.py \
          --replace-fail 'func.lower(ub.User.name) == rp_header_username.lower()' \
                         'func.lower(ub.User.email) == rp_header_username.lower()'
      '';
    });
    options = {
      calibreLibrary = "/var/lib/calibre-library";
      enableBookConversion = true;
      enableBookUploading = true;
      enableKepubify = true;
      reverseProxyAuth = {
        enable = true;
        header = "Cf-Access-Authenticated-User-Email";
      };
    };
  };

  # Keep the lads' calibre-web accounts in sync with lads.json. WantedBy +
  # After calibre-web so it re-runs on every (re)start; restart this unit after
  # editing lads.json to force a re-sync.
  systemd.services.calibre-web-seed-users = {
    description = "Seed calibre-web users from lads.json";
    after = ["calibre-web.service"];
    wantedBy = ["calibre-web.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${calibreSeederPython}/bin/python3 ${calibreSeeder}";
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
