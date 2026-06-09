{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
    imports = [
      ./monitoring.nix
      ./firewall.nix
      ./hardware.nix
      ./desktop.nix
      ./services.nix
      ./hardware-configuration.nix
      ./disko.nix
      ./preservation.nix
      ./nfs-allow.nix

      ./ai-inference.nix

      ../../modules/default.nix

      ../../modules/hardware/rgb-control.nix

      ../../modules/security/aistor-secrets.nix
      ../../modules/services/podman-support.nix

      ../../modules/services/k3s-cluster.nix
      ../../modules/services/keepalived-vip.nix
      inputs.disko.nixosModules.disko
      inputs.nix-mineral.nixosModules.nix-mineral
    ];

  # Host-specific CPU/GPU optimization for llama.cpp (Zen2 + Ampere: RTX 3060 Ti)
  nixpkgs.config.packageOverrides = pkgs: {
    llama-cpp-turboquant = pkgs.llama-cpp-turboquant.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3 -mtune=zen2";
    });
    llama-cpp = pkgs.llama-cpp.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3 -mtune=zen2";
    });
  };

  clusterNetworking = {
    enable = true;
    hostName = "nexus";
    ipAddress = config.networking.cluster.hosts.nexus.ip;
    interfaceName = "enp7s0";
    wireless = {
      enable = true;
      ipAddress = "10.1.1.125";
    };
    unbound.enable = true;
    unbound.listenAddress = config.networking.cluster.hosts.nexus.ip;
  };

  # Prevent hardware-configuration from overriding interface naming
  # while preserving the cluster-networking keep-names policy
  systemd.network.links = lib.mkForce {
    "10-keep-names" = {
      matchConfig = {
        OriginalName = "*";
      };
      linkConfig = {
        NamePolicy = "keep";
      };
    };
  };

  # Flake lock sync enabled — nexus runs etcd and needs fresh inputs for reliable rebuilds
  services.flake-lock-sync.enable = true;
  systemd.timers.flake-lock-sync.enable = true;

  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    image = ../../modules/desktop/wallpapers/catppuccin-mocha-bg.png;
  };

  networking.cluster-hosts = {
    enable = true;
    populateLocal = true;
  };

  profiles.node.nexus-gaming.enable = true;

  # Nexus is headless — no printer, disable CUPS to save resources
  services.boot-error-fixes.includePrinting = false;

  # Hermes + pi state via NFS from zephyr (canonical server)
  services.nfs-cluster-mounts = {
    enable = true;
    mountHermes = false;
    mountPi = false;
  };

  profiles.monitoring = {
    enable = true;
    prometheus.enable = false; # K8s monitoring namespace replaces this
    grafana.enable = false; # K8s monitoring namespace replaces this
    alertmanager.enable = false; # K8s monitoring namespace replaces this
  };

  services.cluster-ca.enable = true;

  boot.kernelPackages = inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;

  # System hardening (Phase 0: Security Baseline)
  # Preset: compatibility (desktop + AI gateway)
  nix-mineral = {
    enable = true;
    preset = ["compatibility"];
    # Fix: nix-mineral adds bind+nodev+nosuid+noexec over-itself mounts for
    # /etc, /var, /var/lib, /var/log, /home, /root, /srv, /tmp, /var/tmp.
    # These paths sit on an ephemeral subvolume;
# Symlink to /persistent in the activation script above.
    # Disable per-path to prevent bind mount generation.
    # https://github.com/cynicsketch/nix-mineral/issues/11
    filesystems.normal = {
      "/etc".enable = lib.mkForce false;
      "/home".enable = lib.mkForce false;
      "/root".enable = lib.mkForce false;
      "/srv".enable = lib.mkForce false;
      "/tmp".enable = lib.mkForce false;
      "/var".enable = lib.mkForce false;
      "/var/lib".enable = lib.mkForce false;
      "/var/log".enable = lib.mkForce false;
      "/var/tmp".enable = lib.mkForce false;
    };
  };

  # Resolve gitconfig conflict between NixOS default and nix-mineral
  environment.etc.gitconfig.source = lib.mkForce (pkgs.writeText "gitconfig" ''
    [user]
      name = Jeremy Kroeker
      email = jkroeker@proton.me
  '');

  # System hardening (Phase 1: Cluster Security)
  security.clusterAudit = {
    enable = true;
    enableFirewall = true;
    enableTailscaleSSH = true;
    bindServicesToLocalhost = true;
  };

  system.stateVersion = "26.05";
  services.unbound-common.enable = true;


  # sops-nix secrets registry (dual-run with agenix during migration)
  services.sops-secrets-registry = {
    enable = true;
    aiServices = true;
    kubernetes = true;
    monitoring = true;
    storage = true;
    mining = true;
    cloud = true;
    automation = true;
    selfHosting = true;
    ci = true;
  };
}