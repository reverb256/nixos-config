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
    ../../modules/security/cluster-mesh.nix
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

  system.stateVersion = "25.11";
  networking.hostName = "krash3";
  networking.hostId = "deadbeef";

  time.timeZone = "America/Winnipeg";

  # ── Users ───────────────────────────────────────────────
  users.users.j_kro = {
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
    ports = [2222];
    openFirewall = true;
    startWhenNeeded = true;
  };

  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [2222];

  # ── Nix ─────────────────────────────────────────────────
  nix = {
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
        stateVersion = lib.mkForce "25.11";
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
  services.cluster-mesh.enable = true;
}
