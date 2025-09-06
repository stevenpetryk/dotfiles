{
  modulesPath,
  config,
  pkgs,
  ...
}: {
  imports = [
    # Include the default lxc/lxd configuration.
    "${modulesPath}/virtualisation/lxc-container.nix"
  ];

  networking.hostName = "homelad";

  # Nix
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
  ];

  # Allow SSH access
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users = {
    mutableUsers = false;
    users.steven = {
      isNormalUser = true;
      hashedPassword = "!";
      extraGroups = ["wheel"];
      openssh.authorizedKeys.keys = [
        # Sync with https://github.com/stevenpetryk.keys
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA8MKWpnZktvAr8y1IKj2xXcHE+3/lLUPKvuFgBkhS0"
      ];
    };
  };

  # Enable passwordless sudo.
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

  # Allow dynamically linked binaries (like the VS Code server)
  programs.nix-ld.enable = true;

  # Keen Mind Discord Bot
  systemd.services.keen-mind = {
    description = "Keen Mind Discord Bot";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [ nodejs_24 python312 pnpm ];

    environment = {
      KEEN_MIND_DATA_DIR = "/var/lib/keen-mind/recordings";
      KEEN_MIND_CACHE_DIR = "/var/cache/keen-mind";
      KEEN_MIND_RUNTIME_DIR = "/run/keen-mind";
    };

    serviceConfig = {
      Type = "simple";
      User = "steven";
      Group = "users";

      WorkingDirectory = "/srv/keen-mind/recorder_bot";

      # Create FHS dirs with correct perms
      StateDirectory = "keen-mind/recordings";
      CacheDirectory = "keen-mind";
      LogsDirectory = "keen-mind";
      RuntimeDirectory = "keen-mind";
      StateDirectoryMode = "0700";

      # Sandboxing: keep /home hidden; OS read-only
      ProtectHome = "yes";
      ProtectSystem = "strict";

      # Allow read of the repo; allow writes only to these dirs
      ReadOnlyPaths = [ "/srv/keen-mind" ];
      ReadWritePaths = [
        "/var/lib/keen-mind"
        "/var/cache/keen-mind"
        "/var/log/keen-mind"
        "/run/keen-mind"
      ];
      UMask = "0077";

      ExecStart = "${pkgs.nodejs_24}/bin/node --experimental-strip-types --env-file=../.env ./src/index.ts";
      Restart = "always";
      RestartSec = "10";
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
