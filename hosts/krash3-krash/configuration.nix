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
  wsl.wslConf.automount.root = "/mnt";
  wsl.wslConf.network.generateHosts = false;

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
    ports = [2223];
    openFirewall = true;
    startWhenNeeded = true;
  };

  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [2223];

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
    registry.nixpkgs.flake = inputs.nixpkgs;
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

    # Dev
    gh
    ripgrep
    fd
    bat
    eza
    delta
    tmux
  ];

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
        git = {
          enable = true;
          userName = lib.mkForce "nixos";
          userEmail = lib.mkForce "nixos@lan";
        };
        htop.enable = true;
        tmux.enable = true;
      };
    };
  };

  # ── Cluster mesh ────────────────────────────────────────
}
