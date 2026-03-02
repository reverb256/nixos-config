# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, inputs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Enable nix-command and flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ============================================================================
  # NVIDIA Graphics Drivers (RTX 3090, RTX 3060 Ti)
  # ============================================================================
  # Enable OpenGL
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Modesetting is required for Wayland
    modesetting.enable = true;

    # Power management (optional, can cause suspend issues)
    powerManagement.enable = false;

    # Use beta drivers (560+) for best Wayland/Plasma 6 support
    # RTX 30 series (Ampere) is fully supported
    package = config.boot.kernelPackages.nvidiaPackages.beta;

    # Open source kernel module (optional for Turing+)
    # Set to false for proprietary (recommended for gaming/CUDA)
    open = false;

    # Enable nvidia-settings
    nvidiaSettings = true;
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_zen;

  networking.hostName = "zephyr"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Winnipeg";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_CA.UTF-8";

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable dbus-broker
  services.dbus = {
    enable = true;
    implementation = "broker";
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.j_kro = {
    isNormalUser = true;
    description = "Jeremy Kroeker";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" "render" "video" "libinput"];
    packages = with pkgs; [
      kdePackages.kate
      gh  # GitHub CLI
      nodejs  # Node.js runtime
      kdePackages.audiotube
    ];
  };

  # Home Manager configuration
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

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Binary caches
  nix.settings.substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://cache.nixos-cuda.org"
    "https://ezkea.cachix.org"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
  ];
  nix.settings.trusted-users = [ "root" "j_kro" ];

  # Fish shell configuration with aliases
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      # Initialize zoxide for smart cd
      if type -q zoxide
        zoxide init fish | source
      end

      # Set greeting to empty
      set -g fish_greeting ""
    '';
    shellAliases = {
      # List aliases - modern replacements
      ll = "eza -lh --group-directories-first --icons=auto";
      la = "eza -la --group-directories-first --icons=auto";
      l = "eza --group-directories-first --icons=auto";
      lt = "eza --tree --level=2 --long --icons --git";

      # NixOS aliases
      update = "sudo nixos-rebuild switch --flake /etc/nixos";
      build = "sudo nixos-rebuild build --flake /etc/nixos";
      test = "sudo nixos-rebuild test --flake /etc/nixos";

      # Git aliases
      g = "git";
      gs = "git status";
      gc = "git commit";
      gp = "git push";
      gl = "git log --oneline -10";
    };
  };

  # Allow passwordless sudo for j_kro
  security.sudo = {
    enable = true;
    extraConfig = "j_kro ALL=(ALL) NOPASSWD: ALL";
  };

  # Install packages
  environment.systemPackages = with pkgs; [
    # Shell & CLI replacements
    fish  # Fish shell
    starship  # Shell prompt
    zoxide  # Smart cd
    fzf  # Fuzzy finder
    eza  # Modern ls replacement
    btop  # Modern htop replacement

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
    gh  # GitHub CLI
    inputs.claude-native.packages.x86_64-linux.claude  # Claude Code

    # AI & ML
    llama-cpp  # Local LLM inference
    whisper-cpp  # Speech-to-text

    # Mining
    xmrig  # CPU mining
    lolminer  # GPU mining

    # Desktop apps
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable Tailscale
  services.tailscale.enable = true;

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Anime Game Launchers (aagl-gtk-on-nix)
  programs.anime-game-launcher.enable = true;
  programs.sleepy-launcher.enable = true;
  programs.honkers-railway-launcher.enable = true;
  programs.wavey-launcher.enable = true;

  # Starship prompt
  programs.starship = {
    enable = true;
    settings = {
      format = "$all$character";
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
      };
    };
  };

  system.stateVersion = "26.05";

}
