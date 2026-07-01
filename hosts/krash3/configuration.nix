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
  wsl.defaultUser = "j_kro";
  wsl.wslConf.automount.root = "/mnt";
  wsl.wslConf.automount.options = "metadata,uid=1000,gid=100";
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
  networking.hostName = "krash3";
  networking.hostId = "deadbeef";

  time.timeZone = "America/Winnipeg";

  # ── Users ───────────────────────────────────────────────
  users.users.j_kro = {
uid = 1001;
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
    ports = [22222];
    openFirewall = true;
    startWhenNeeded = false;
  };

  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22222];

  # ── Nix ─────────────────────────────────────────────────
  nix = {
    registry.nixpkgs.to.path = lib.mkForce inputs.nixpkgs-2605.outPath;
    settings = {
      trusted-users = ["j_kro" "root"];
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
    users.j_kro = {pkgs, ...}: {
      home = {
        stateVersion = lib.mkForce "26.05";
        username = "j_kro";
        homeDirectory = "/home/j_kro";
      };
      programs = {
        bash.enable = true;
        git = {
          enable = true;
          userName = lib.mkForce "j_kro";
          userEmail = lib.mkForce "j_kro@lan";
        };
        htop.enable = true;
        tmux.enable = true;
      };
    };
  };

  # ── Cluster mesh ────────────────────────────────────────
}
