{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  meshKeys = import ../../mesh-keys.nix;
in {
  imports = [
    ./hardware-configuration.nix
    inputs.NixOS-WSL.nixosModules.wsl
    inputs.home-manager.nixosModules.home-manager
  ];

  # ── WSL ─────────────────────────────────────────────────
  wsl.enable = true;
  wsl.defaultUser = "nixos";

  # Share Windows SSH agent with WSL (no separate key management)
  wsl.ssh-agent.enable = true;

  # Add NixOS to Windows Start menu
  wsl.startMenuLaunchers = true;

  wsl.wslConf = {
    automount.root = "/mnt";
    network.generateHosts = false;
    interop.appendWindowsPath = false; # Clean PATH — no Windows cruft
  };

  # Required by home-manager xdg.portal integration
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  # ── System ──────────────────────────────────────────────
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = false;

  system.stateVersion = "26.05";
  networking.hostName = "krash3-krash";
  networking.hostId = "cafebabe";

  time.timeZone = "America/Winnipeg";

  # ── Users ───────────────────────────────────────────────
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
    openssh.authorizedKeys.keys = meshKeys;
    initialPassword = "nixos";
    shell = pkgs.zsh;
  };

  security.sudo.wheelNeedsPassword = false;

  # ── SSH ─────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
      PermitRootLogin = "no";
    };
    ports = [22224];
    openFirewall = true;
    startWhenNeeded = false;
  };

  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22224];

  # ── Nix ─────────────────────────────────────────────────
  nix = {
    settings = {
      trusted-users = ["nixos" "root"];
      experimental-features = ["nix-command" "flakes"];
      accept-flake-config = true;
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    optimise.automatic = true;
    nixPath = lib.mkForce [];
    extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';
  };

  # ── Packages ────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # Core
    git
    curl
    wget
    vim
    htop
    jq
    bash
    coreutils
    findutils
    gnused
    gawk
    unzip
    xz
    file
    which

    # Shell & interop
    wslu

    # Nix tooling
    nix-output-monitor
    nvd
    nix-tree
    nh

    # Network
    bind.dnsutils
    mtr
    iperf3
    traceroute
    tcpdump
    nmap

    # Dev
    gh
    ripgrep
    fd
    bat
    eza
    delta
    tmux
    rsync
    fastfetch
  ];

  # ── Programs ────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [
        "git"
        "docker"
        "systemd"
        "history"
        "command-not-found"
      ];
    };
  };

  # ── Home Manager ────────────────────────────────────────
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.nixos = {pkgs, ...}: {
      home = {
        stateVersion = lib.mkForce "26.05";
        username = "nixos";
        homeDirectory = "/home/nixos";
      };

      programs = {
        bash.enable = true;
        zsh.enable = true;
        git = {
          enable = true;
          userName = lib.mkForce "krash";
          userEmail = lib.mkForce "krash@lan";
        };
        htop.enable = true;
        tmux.enable = true;
        starship = {
          enable = true;
          settings = {
            add_newline = false;
            character = {
              success_symbol = "[➜](bold.green)";
              error_symbol = "[➜](bold.red)";
            };
          };
        };
      };

      home.packages = with pkgs; [
        wl-clipboard
        _7zz
      ];

      home.sessionVariables = {
        EDITOR = "vim";
        VISUAL = "vim";
      };

      # Link .ssh from Windows for seamless key access
    };
  };

  # ── SSH key from Windows ────────────────────────────
  # Copy SSH private key from Windows mounted drive for seamless auth
  systemd.services.copy-wsl-ssh-key = {
    description = "Copy SSH key from Windows to WSL";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    before = ["sshd.service"];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      mkdir -p /home/nixos/.ssh
      if [ -f /mnt/c/Users/krash/.ssh/id_ed25519 ] && [ ! -f /home/nixos/.ssh/id_ed25519 ]; then
        cp /mnt/c/Users/krash/.ssh/id_ed25519 /home/nixos/.ssh/id_ed25519
        chmod 600 /home/nixos/.ssh/id_ed25519
        cp /mnt/c/Users/krash/.ssh/id_ed25519.pub /home/nixos/.ssh/id_ed25519.pub 2>/dev/null || true
        chown -R nixos:users /home/nixos/.ssh
        echo "SSH key copied from Windows"
      fi
    '';
  };
}
