{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./monitoring.nix
    ./firewall.nix
    ./hardware.nix
    ./desktop.nix
    ./services.nix
    ./hardware-configuration.nix

    ../../modules/default.nix

    ../../modules/hardware/rgb-control.nix

    ../../modules/services/podman-support.nix

    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
  ];

  clusterNetworking = {
    enable = true;
    hostName = "forge";
    ipAddress = config.networking.cluster.hosts.forge.ip;
    interfaceName = "eth0";
    wireless.enable = false;
    unbound.enable = true;
    unbound.listenAddress = config.networking.cluster.hosts.forge.ip;
  };

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
      addresses=${config.networking.cluster.hosts.forge.ip}/24
      gateway=10.1.1.1
      dns=127.0.0.1

      [ipv6]
      method=auto
    '';
  };

  system.stateVersion = "26.05";
  services.unbound-common.enable = true;
  services.flake-lock-sync.enable = true;
  systemd.timers.flake-lock-sync.enable = true;

  services.k3s-cluster = {
    enable = true;
    role = "server";
    nodeName = "forge";
    clusterInit = false;
    serverAddr = "https://${config.networking.cluster.kubernetes.vip}:${toString config.networking.cluster.kubernetes.apiPort}";
    tokenFile = "/run/agenix/k3s-cluster-token";
    nodeIP = config.networking.cluster.hosts.forge.ip;
  };

  services.keepalived-vip = {
    enable = true;
    vip = config.networking.cluster.kubernetes.vip;
    interface = "eth0";
    priority = 80;
  };

  services.cluster-ca = {
    enable = true;
    generateLeaf = false;
  };

  services.tailscale.enable = true;

  services.gpu-profile-manager = { enable = true; };

  # ═══════════════════════════════════════════════════════════════════
  # STORAGE REDIRECT — Use secondary HDD for heavy data
  # System SSD: TEAM T253X2256G 256GB (sdb, ata-TEAM_T253X2256G_TM701907310240040386)
  # Storage HDD: ADATA SU635 240GB (sda, ata-ADATA_SU635_2L40291DQ5CE)
  #   sda2 (215.6G) at /home — 206G free
  # Pre-reboot setup (run once):
  #   mount /dev/disk/by-id/ata-ADATA_SU635_2L40291DQ5CE-part2 /mnt
  #   btrfs subvolume create /mnt/@nix
  #   mkdir -p /mnt/@nix/store /mnt/@nix/var
  #   cp -a /nix/store/* /mnt/@nix/store/
  #   cp -a /nix/var/* /mnt/@nix/var/
  #   umount /mnt
  #   nixos-rebuild boot && reboot
  # ═══════════════════════════════════════════════════════════════════
  fileSystems."/nix" = {
    device = "/dev/disk/by-id/ata-ADATA_SU635_2L40291DQ5CE-part2";
    fsType = "btrfs";
    options = ["subvol=@nix" "compress=zstd" "noatime" "nofail"];
  };

  services.nfs-client = {
    enable = false;
    mountShared = true;
    mountHome = true;
  };

  services.gaming-detection = { enable = true; };
  services.mining-coordinator = { enable = true; };

  services.agenix-secrets-registry = {
    enable = true;
    kubernetes = true;
    initrdRecovery = true;
    aiServices = true;
  };

  services.cluster-mesh.enable = true;

  services.agent-firewall = {
    enable = true;
    auditLog = true;
  };

  networking.cluster.dns.enable = true;
  services.initrd-ssh-recovery = {
    enable = true;
    interface = "eth0";
    networkDriver = "r8169";
    port = 2222;
  };
  services.recovery-specialisation.enable = true;
  services.btrfs-boot-snapshot = {
    enable = true;
    device = "/dev/disk/by-uuid/9e2086e8-ad39-4084-9904-e85f7f73d1af";
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedGzipSettings = true;
    virtualHosts."_" = {
      default = true;
      locations."= /".return = "200 'OK'";
      locations."= /".extraConfig = ''
        add_header Content-Type text/plain;
      '';
    };
  };

  services.xserver.videoDrivers = ["nvidia"];

  boot.kernelParams = [
    "mitigations=auto"
  ];

  security.clusterAudit = {
    enable = true;
    enableFirewall = true;
    enableTailscaleSSH = true;
    bindServicesToLocalhost = true;
  };
}
