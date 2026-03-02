# Zephyr Host Configuration
# RTX 3090, Quest Pro, 4K HDR TV
{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Hardware modules (NVIDIA GPU)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix

    # Modules (all other modules)
    ../../modules/default.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "zephyr";
  networking.networkmanager.enable = true;

  # Timezone and locale
  time.timeZone = "America/Winnipeg";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # Zephyr-specific kernel params for gaming
  boot.kernelParams = [
    "split_lock_detect=off"
    "threadirqs"
    "preempt=full"
    "processor.max_cstate=1"
    "intel_idle.max_cstate=1"
    "iommu=pt"
  ];

  # ============================================================================
  # GAMING + VR (Full support - RTX 3090)
  # ============================================================================
  services.gaming = {
    enable = true;
    vr.enable = true; # WiVRn for Quest Pro
    hdr.enable = true; # HDR for 4K HDR TV
  };

  # ============================================================================
  # SCOPEBUDDY - Gamescope wrapper
  # ============================================================================
  programs.scopebuddy = {
    enable = true;
    autoDetect = {
      resolution = true;
      hdr = true;
      vrr = true;
    };
  };

  # ============================================================================
  # ANIME GAME LAUNCHERS
  # ============================================================================
  programs.anime-game-launcher.enable = true;
  programs.sleepy-launcher.enable = true;
  programs.honkers-railway-launcher.enable = true;
  programs.wavey-launcher.enable = true;

  # ============================================================================
  # TAILSCALE
  # ============================================================================
  services.tailscale.enable = true;

  # ============================================================================
  # ADDITIONAL PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    # Shell & CLI
    fish
    starship
    zoxide
    fzf
    eza
    btop

    # Version control
    tmux
    mosh
    git

    # Networking
    tailscale
    networkmanager
    dbus-broker

    # Development
    nodejs
    gh
    inputs.claude-native.packages.x86_64-linux.claude

    # AI & ML
    llama-cpp
    whisper-cpp

    # Mining (manual only, no auto-start)
    xmrig
    lolminer

    # Desktop
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
  ];

  # ============================================================================
  # HOME MANAGER - Zen Browser with Extensions
  # ============================================================================
  home-manager.users.j_kro = { pkgs, lib, ... }: {
    imports = [ inputs.zen-browser.homeModules.twilight ];
    home.stateVersion = "26.05";
    programs.zen-browser = {
      enable = true;
      suppressXdgMigrationWarning = true;
      policies = {
        DisableAppUpdate = true;
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DisableFeedbackCommands = true;
        DisablePocket = true;
        NoDefaultBookmarks = true;
        OfferToSaveLogins = false;
        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };

        # Dark Reader extension
        ExtensionSettings = {
          "addon@darkreader.org" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
          };
        };
      };
      profiles.default = {
        extensions.packages = with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
          ublock-origin
          bitwarden
          privacy-badger
          decentraleyes
          noscript
          clearurls
          cookie-autodelete
          privacy-pass
        ];
      };
    };
  };

  # ============================================================================
  # FIREWALL
  # ============================================================================
  networking.firewall = {
    allowedTCPPorts = [
      9757  # WiVRn
      18789
      18790
      19898
    ];
    allowedUDPPorts = [
      9757  # WiVRn
      9758
      9759
      27031
      27036
      5353  # mDNS
      9947  # WiVRn
    ];
    interfaces."tailscale0".allowedTCPPorts = [
      18789
      18790
    ];
  };

  # ============================================================================
  # SYSTEM STATE
  # ============================================================================
  system.stateVersion = "26.05";
}
