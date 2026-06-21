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
  wsl.wslConf.automount.options = "metadata";
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

  networking.extraHosts = ''
    search.lan 10.1.1.100
    ai-inference.lan 10.1.1.100
    auth.lan 10.1.1.100
    qdrant.lan 10.1.1.100
    n8n.lan 10.1.1.100
    searxng.lan 10.1.1.100
    mission-control.lan 10.1.1.100
    grafana.lan 10.1.1.100
    privacy-filter.lan 10.1.1.100
    vaultwarden.lan 10.1.1.100
    workspace.lan 10.1.1.100
    dashboard.lan 10.1.1.100
    maplespike.lan 10.1.1.100
    api.maplespike.lan 10.1.1.100
    mcp.maplespike.lan 10.1.1.100
    status.maplespike.lan 10.1.1.100
    uptime.maplespike.lan 10.1.1.100
    haven.lan 10.1.1.100
    mosiac.lan 10.1.1.100
    mining.lan 10.1.1.100
    gitea.lan 10.1.1.100
    hermes.lan 10.1.1.100
    api.hermes.lan 10.1.1.100
    monitoring.lan 10.1.1.100
    prometheus.lan 10.1.1.100
    alertmanager.lan 10.1.1.100
    vane.lan 10.1.1.100
  '';

  time.timeZone = "America/Winnipeg";

  # ── Users ───────────────────────────────────────────────
  users.users.j_kro = {
    uid = 1001;
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
    openssh.authorizedKeys.keys = meshKeys;
    initialPassword = "nixos";
  };

  users.users.krash = {
    uid = 1002;
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
    ports = [22222 22224];
    openFirewall = true;
    startWhenNeeded = false;
  };

  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22222 22224];

  # ── SSH key from Windows (for krash user) ───────────────
  systemd.services.copy-wsl-ssh-key = {
    description = "Copy SSH key from Windows to WSL";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    before = ["sshd.service"];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      mkdir -p /home/krash/.ssh
      if [ -f /mnt/c/Users/krash/.ssh/id_ed25519 ] && [ ! -f /home/krash/.ssh/id_ed25519 ]; then
        cp /mnt/c/Users/krash/.ssh/id_ed25519 /home/krash/.ssh/id_ed25519
        chmod 600 /home/krash/.ssh/id_ed25519
        cp /mnt/c/Users/krash/.ssh/id_ed25519.pub /home/krash/.ssh/id_ed25519.pub 2>/dev/null || true
        chown -R krash:users /home/krash/.ssh
        echo "SSH key copied from Windows krash user"
      fi
    '';
  };

  # ── Nix ─────────────────────────────────────────────────
  nix = {
    registry.nixpkgs.to.path = lib.mkForce inputs.nixpkgs-2605.outPath;
    settings = {
      trusted-users = ["j_kro" "krash" "root"];
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
    git curl wget vim htop jq bash coreutils findutils gnused gawk
    nix-output-monitor nvd nix-tree nh
    bind.dnsutils mtr iperf3 traceroute
    gh ripgrep fd bat eza delta tmux
  ];

  # ── Home Manager (j_kro) ────────────────────────────────
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

    users.krash = {pkgs, ...}: {
      home = {
        stateVersion = lib.mkForce "26.05";
        username = "krash";
        homeDirectory = "/home/krash";
      };
      programs = {
        bash.enable = true;
        git = {
          enable = true;
          userName = lib.mkForce "krash";
          userEmail = lib.mkForce "krash@lan";
        };
        htop.enable = true;
        tmux.enable = true;
      };
    };
  };
}