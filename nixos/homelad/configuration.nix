{
  modulesPath,
  config,
  pkgs,
  ...
}: {
  imports = [
    # Include the default lxc/lxd configuration.
    "${modulesPath}/virtualisation/lxc-container.nix"
    (builtins.getFlake "/home/steven/src/keen-mind").nixosModules.default
    ./cachix.nix
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
    users.steven = {
      isNormalUser = true;
      hashedPassword = "!";
      extraGroups = ["wheel"];
      shell = pkgs.zsh;
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

  # AI
  services.ollama.enable = true;
  services.ollama.package = pkgs.ollama-cuda;

  # Allow dynamically linked binaries (like the VS Code server)
  programs.nix-ld.enable = true;


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
