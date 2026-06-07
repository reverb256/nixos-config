{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.disko.nixosModules.disko
    ./monitoring.nix
    ./firewall.nix
    ./hardware.nix
    ./desktop.nix
    ./services.nix
    ./disko.nix
    ./preservation.nix

    ../../modules/default.nix

    ../../modules/hardware/rgb-control.nix

    ../../modules/services/podman-support.nix

    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
    ../../modules/services/sshfs-projects-mount.nix
    inputs.nix-mineral.nixosModules.nix-mineral
  ];

  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/dracula.yaml";
    image = ../../modules/desktop/wallpapers/dracula-bg.png;
  };

  clusterNetworking = {
    enable = true;
    hostName = "sentry";
    ipAddress = config.networking.cluster.hosts.sentry.ip;
    interfaceName = "eth0";
    wireless.enable = false;
    unbound.enable = true;
    unbound.listenAddress = config.networking.cluster.hosts.sentry.ip;
  };

  # Block Hoyoverse telemetry domains (Genshin Impact, Honkai Star Rail, Zenless Zone Zero)
  networking.hoyoverse-telemetry-block.enable = true;

  # Declarative static IP for eth0 — NM connection persisted across rebuilds
  environment.etc."NetworkManager/system-connections/static-eth0.nmconnection" = {
    mode = "0600";
    text = ''
      [connection]
      id=static-eth0
      type=ethernet
      interface-name=eth0

      [ethernet]

      [ipv4]
      method=manual
      addresses=${config.networking.cluster.hosts.sentry.ip}/24
      gateway=10.1.1.1
      dns=127.0.0.1

      [ipv6]
      method=auto
    '';
  };

  services.flake-lock-sync.enable = true;
  systemd.timers.flake-lock-sync.enable = true;

  profiles.node.sentry-monitoring.enable = true;

  services.ai-inference.enable = lib.mkForce false;

  # ═══════════════════════════════════════════════════════════════════
  # STORAGE — Managed by disko.nix
  # System SSD: Micron 1100 SATA 256GB (sdb, /dev/disk/by-id/ata-Micron_1100_SATA_256GB_18361E518AB4)
  # Storage HDD: ST1000DM010 1TB (sda, /dev/disk/by-id/ata-ST1000DM010-2EP102_ZN1AMQLC)
  # ═══════════════════════════════════════════════════════════════════
  # Subvolumes on SSD: @root (/), @persistent (/persistent), @nix (/nix)
  # Subvolumes on HDD: @home (/home)
  # /storage is manually mounted in hardware-configuration.nix
  # /var is on SSD (default)

  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;
  boot.loader.timeout = lib.mkDefault 5;

  services.sshfs-projects-mount.enable = true;

  services.nfs-cluster-mounts = {
    enable = true;
    mountHermes = false;
    mountPi = false;
  };

  # System hardening
  nix-mineral = {
    enable = true;
    preset = ["compatibility"];
    settings.etc.kicksecure-module-blacklist = false;
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

  systemd.services.nfs-idmapd.serviceConfig.SupplementaryGroups = ["proc"];
  systemd.tmpfiles.rules = ["d /var/lib/nfs/rpc_pipefs/nfs 0755 root root -"];

  environment.etc.gitconfig.source = lib.mkForce (pkgs.writeText "gitconfig" ''
    [user]
      name = Jeremy Kroeker
      email = jkroeker@proton.me
  '');

  system.stateVersion = "26.05";
  services.unbound-common.enable = true;

  services.unbound.settings.forward-zone = lib.mkForce [
    {
      name = "ts.net.";
      forward-addr = ["100.100.100.100" "fd7a:115c:a1e0::53"];
    }
    {
      name = ".";
      forward-addr = ["1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4"];
    }
  ];

  security.clusterAudit = {
    enable = true;
    enableFirewall = true;
    enableTailscaleSSH = true;
    bindServicesToLocalhost = true;
  };

  environment.systemPackages = with pkgs; [
    nvtopPackages.full
  ];
}
