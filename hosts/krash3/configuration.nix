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
  wsl.enable = true;
  wsl.defaultUser = "j_kro";
  wsl.ssh-agent.enable = true;
  wsl.startMenuLaunchers = true;
  wsl.wslConf = {
    automount = {
      root = "/mnt";
      options = "metadata,uid=1000,gid=100";
    };
    network.generateHosts = false;
    interop.appendWindowsPath = false;
  };
  environment.pathsToLink = [ "/share/applications" "/share/xdg-desktop-portal" ];
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = false;
  system.stateVersion = "26.05";
  networking.hostName = "krash3";
  networking.hostId = "deadbeef";
  time.timeZone = "America/Winnipeg";
  users.users.j_kro = {
    uid = 1001;
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
    openssh.authorizedKeys.keys = meshKeys;
    initialPassword = "nixos";
    shell = pkgs.zsh;
  };
  security.sudo.wheelNeedsPassword = false;
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
  nix = {
    settings = {
      trusted-users = ["j_kro" "root"];
      experimental-features = ["nix-command" "flakes"];
      accept-flake-config = true;
      auto-optimise-store = true;
    };
    gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 30d"; };
    optimise.automatic = true;
    nixPath = lib.mkForce [];
    extraOptions = "keep-outputs = true\nkeep-derivations = true\n";
  };
  environment.systemPackages = with pkgs; [
    git curl wget vim htop jq bash coreutils findutils gnused gawk
    unzip xz file which
    nix-output-monitor nvd nix-tree nh
    bind.dnsutils mtr iperf3 traceroute tcpdump nmap
    gh ripgrep fd bat eza delta tmux rsync fastfetch
  ];
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = ["git" "docker" "systemd" "history" "command-not-found"];
    };
  };
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
        zsh.enable = true;
        git = { enable = true; userName = lib.mkForce "j_kro"; userEmail = lib.mkForce "j_kro@lan"; };
        htop.enable = true;
        tmux.enable = true;
        starship = {
          enable = true;
          settings = { add_newline = false; character = { success_symbol = "[➜](bold.green)"; error_symbol = "[➜](bold.red)"; }; };
        };
      };
      home.packages = with pkgs; [ wl-clipboard _7zz ];
      home.sessionVariables = { EDITOR = "vim"; VISUAL = "vim"; };
    };
  };
  systemd.services.copy-wsl-ssh-key = {
    description = "Copy SSH key from Windows to WSL";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    before = ["sshd.service"];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      mkdir -p /home/j_kro/.ssh
      if [ -f /mnt/c/Users/j_kro.Krash3/.ssh/id_ed25519 ] && [ ! -f /home/j_kro/.ssh/id_ed25519 ]; then
        cp /mnt/c/Users/j_kro.Krash3/.ssh/id_ed25519 /home/j_kro/.ssh/id_ed25519
        chmod 600 /home/j_kro/.ssh/id_ed25519
        cp /mnt/c/Users/j_kro.Krash3/.ssh/id_ed25519.pub /home/j_kro/.ssh/id_ed25519.pub 2>/dev/null || true
        chown -R j_kro:users /home/j_kro/.ssh
        echo "SSH key copied from Windows"
      fi
    '';
  };
}
