{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./monitoring.nix
    ./firewall.nix
    ./hardware.nix
    ./desktop.nix
    ./services.nix
    ./hardware-configuration.nix

    ./ai-inference.nix

    ../../modules/default.nix

    ../../modules/hardware/rgb-control.nix

    ../../modules/security/aistor-secrets.nix
    ../../modules/services/podman-support.nix

    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
  ];

  clusterNetworking = {
    enable = true;
    hostName = "nexus";
    ipAddress = "10.1.1.120";
    interfaceName = "enp7s0";
    wireless = {
      enable = true;
      ipAddress = "10.1.1.125";
    };
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

  profiles.monitoring = {
    enable = true;
    prometheus.enable = false;  # K8s monitoring namespace replaces this
    grafana.enable = false;     # K8s monitoring namespace replaces this
    alertmanager.enable = false; # K8s monitoring namespace replaces this
  };

  services.cluster-ca.enable = true;


  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;


  # Hermes state lives on local disk (nexus IS the NFS server)
  fileSystems."/home/j_kro/.hermes" = {
    device = "/data/hermes";
    fsType = "none";
    options = [ "bind" "noatime" ];
  };

  # Pi agent state lives on local disk (nexus IS the NFS server)
  fileSystems."/home/j_kro/.pi/agent" = {
    device = "/data/pi";
    fsType = "none";
    options = [ "bind" "noatime" ];
  };
  system.stateVersion = "26.05";
}
