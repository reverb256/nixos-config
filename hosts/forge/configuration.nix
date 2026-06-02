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
    ../../modules/default.nix
    ../../modules/hardware/rgb-control.nix
    ../../modules/services/podman-support.nix
    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
    ../../modules/services/sshfs-projects-mount.nix
  ];

  # Host-specific CPU/GPU optimization for llama.cpp (Zen1 + Ada: RTX 4060)
  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    image = ../../modules/desktop/wallpapers/gruvbox-dark-bg.png;
  };

  clusterNetworking = {
    enable = true;
    hostName = "forge";
    ipAddress = config.networking.cluster.hosts.forge.ip;
    interfaceName = lib.mkForce "eno1";
    wireless.enable = false;
    unbound.enable = true;
    unbound.listenAddress = config.networking.cluster.hosts.forge.ip;
  };

  networking.interfaces.eno1.ipv6.addresses = [
    {
      address = "fd00::130";
      prefixLength = 64;
    }
  ];

  boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 0;
  boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 0;
  boot.kernel.sysctl."net.ipv6.conf.eno1.disable_ipv6" = 0;

  systemd.timers.flake-lock-sync.enable = true;
  services.flake-lock-sync.enable = true;

  kernel-hardening.zswap.maxPoolPercent = 20;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 999;
  };

  services.earlyoom = {
    enable = true;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };

  boot.kernel.sysctl."vm.min_free_kbytes" = lib.mkForce 524288;

  profiles.node.forge-mining.enable = true;
  services.ai-inference.backend.type = "llama-cpp";

  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;

  # Shared hermes + pi state via NFS (resilient: nofail, automount, soft)
  services.sshfs-projects-mount.enable = true;

  services.nfs-cluster-mounts = {
    enable = true;
    mountHermes = false;
    mountPi = false;
  };

  # Override noexec on /var (nix-mineral remnant) for k3s re-exec
  fileSystems."/var/lib/rancher/k3s" = {
    device = "/var/lib/rancher/k3s";
    fsType = "none";
    options = ["bind" "rw" "nosuid"];
  };

  system.stateVersion = "26.05";
  services.unbound-common.enable = true;
  # ═══════════════════════════════════════════════════════════════════
  # STORAGE REDIRECT — Use secondary HDD for heavy data
  # System SSD: TEAM T253X2256G 256GB (sdb, ata-TEAM_T253X2256G_TM701907310240040386)
  # Storage HDD: ADATA SU635 240GB (sda, ata-ADATA_SU635_2L40291DQ5CE)
  #   sda2 (215.6G) at /home — 206G free. Nix store: 86G.
  # Pre-reboot setup:
  #   sudo mount /dev/disk/by-id/ata-ADATA_SU635_2L40291DQ5CE-part2 /mnt
  #   sudo btrfs subvolume create /mnt/@nix
  #   sudo mkdir -p /mnt/@nix/store /mnt/@nix/var
  #   sudo cp -a /nix/store/* /mnt/@nix/store/
  #   sudo cp -a /nix/var/* /mnt/@nix/var/
  #   sudo umount /mnt
  #   sudo nixos-rebuild boot && reboot
  # ═══════════════════════════════════════════════════════════════════
  fileSystems."/nix" = {
    device = "/dev/disk/by-id/ata-ADATA_SU635_2L40291DQ5CE-part2";
    fsType = "btrfs";
    options = ["subvol=@nix" "compress=zstd" "noatime" "x-initrd.mount" "nofail"];
  };

  # Mount /var on the secondary HDD — frees ~29G on the system SSD
  # Covers: /var/lib/rancher (k3s), /var/lib/vllm-models, /var/lib/nix-csi, /var/lib/flatpak
  fileSystems."/var" = {
    device = "/dev/disk/by-id/ata-ADATA_SU635_2L40291DQ5CE-part2";
    fsType = "btrfs";
    options = ["subvol=@var" "compress=zstd" "noatime" "x-initrd.mount" "nofail"];
  };
}
