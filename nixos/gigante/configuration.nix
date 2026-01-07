{ config, pkgs, lib, ... }:

rec {
  imports =
    [
      ./hardware-configuration.nix
      ./cachix.nix
    ];

  system.stateVersion = "25.05"; # See https://nixos.org/nixos/options.html

  # Users
  users.users.steven = {
    isNormalUser = true;
    description = "Steven Petryk";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      kdePackages.kate
      cachix
      home-manager
    ];
    shell = pkgs.zsh;
  };

  services.displayManager = {
    autoLogin.enable = true;
    autoLogin.user = "steven";
  };

  # Shell setup - we use Home Manager's ZSH
  programs.zsh.enable = true;
  environment.shells = [ "/home/steven/.nix-profile/bin/zsh" ];

  #
  # Software and services
  #

  # Nix
  nix.extraOptions = "experimental-features = nix-command flakes";
  nixpkgs.config.allowUnfree = true;
  nix.nixPath = [
    "nixos-config=/home/steven/.config/dotfiles/nixos/gigante/configuration.nix"
    "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
    "/nix/var/nix/profiles/per-user/root/channels"
  ];

  # Non-module packages
  environment.systemPackages = with pkgs; [
    # Gaming
    mangohud
    protonup-qt
    lutris
    bottles

    # General
    discord
    spotify

    # Display control
    ddcutil # For manual brightness control via DDC/CI

    # LED control that OpenRGB doesn't manage
    liquidctl
  ];

  # Browser
  programs.firefox.enable = true;

  # SSH
  services.openssh.enable = true;

  # LAN
  services.tailscale.enable = true;

  # Allow dynamically linked binaries
  programs.nix-ld.enable = true;

  # AI
  # services.ollama.enable = true;
  # services.ollama.acceleration = "cuda";
  # services.open-webui.enable = true;
  # services.open-webui.port = 8080;
  # services.open-webui.openFirewall = true;

  # Gaming
  programs.steam.enable = true;
  programs.steam.gamescopeSession.enable = true;
  programs.gamemode.enable = true;

  # Streaming
  services.sunshine.enable = true;
  services.sunshine.openFirewall = true;
  services.sunshine.capSysAdmin = true;
  services.sunshine.package = pkgs.sunshine.override { cudaSupport = true; };


  #
  # Homelab-adjacent stuff
  #

  # Advertise at gigante.local
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };

  #
  # Low-level stuff
  #

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "gigante"; # Define your hostname.
  networking.networkmanager.enable = true;
  networking.interfaces.enp4s0.wakeOnLan.enable = true;

  # Timezone
  time.timeZone = "America/Los_Angeles";

  # Internationalization
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
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

  # Desktop environment
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Printing
  services.printing.enable = true;

  # Sound
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Make LG UltraFine display dimmable
  hardware.i2c.enable = true;

  # GPU
  hardware.nvidia.open = false; # Use proprietary driver to avoid pageflip timeout bug
  hardware.graphics.enable = true;
  hardware.nvidia.modesetting.enable = true;
  hardware.nvidia.powerManagement.enable = true;
  hardware.nvidia.nvidiaSettings = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
  services.xserver.videoDrivers = [ "nvidia" ];

  # Wayland-specific NVIDIA workarounds
  environment.variables = {
    # Force NVIDIA to use the proprietary driver for Wayland
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    # Disable hardware cursors which can cause pageflip issues
    WLR_NO_HARDWARE_CURSORS = "1";
  };
}
