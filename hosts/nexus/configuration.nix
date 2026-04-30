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
    ./impermanence.nix
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
      cmakeFlags = (old.cmakeFlags or []) ++ ["-DLLAMA_CUDA_ARCHITECTURES=86"];
    });
    llama-cpp = pkgs.llama-cpp.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3 -mtune=zen2";
      cmakeFlags = (old.cmakeFlags or []) ++ ["-DLLAMA_CUDA_ARCHITECTURES=86"];
    });
  };

  clusterNetworking = {
    enable = true;
    hostName = "nexus";
    ipAddress = "10.1.1.120";
    interfaceName = "enp7s0";
    wireless = {
      enable = true;
      ipAddress = "10.1.1.125";
    };
    unbound.enable = true;
    unbound.listenAddress = "10.1.1.120";
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

  services.flake-lock-sync.enable = lib.mkForce false;
  systemd.timers.flake-lock-sync.enable = false;

  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    image = ../../modules/desktop/wallpapers/catppuccin-mocha-bg.jpg;
  };

  networking.cluster-hosts = {
    enable = true;
    populateLocal = true;
  };

  profiles.node.nexus-gaming.enable = true;

  # Hermes + pi state via NFS from zephyr (canonical server)
  services.nfs-cluster-mounts = {
    enable = true;
    mountHermes = true;
    mountPi = true;
  };

  profiles.monitoring = {
    enable = true;
    prometheus.enable = false; # K8s monitoring namespace replaces this
    grafana.enable = false; # K8s monitoring namespace replaces this
    alertmanager.enable = false; # K8s monitoring namespace replaces this
  };

  services.cluster-ca.enable = true;

  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;

  # System hardening (Phase 0: Security Baseline)
  # Preset: compatibility (desktop + AI gateway)
  nix-mineral = {
    enable = true;
    preset = ["compatibility"];
  };

  # Resolve gitconfig conflict between NixOS default and nix-mineral
  environment.etc.gitconfig.source = lib.mkForce (pkgs.writeText "gitconfig" ''
    [user]
      name = Jeremy Kroeker
      email = jkroeker@proton.me
  '');

  system.stateVersion = "26.05";
  services.unbound-common.enable = true;
}
