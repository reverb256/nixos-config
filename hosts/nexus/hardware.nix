{
  pkgs,
  lib,
  config,
  ...
}: {
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true;
    vulkan.enable = true;
  };

  hardware = {
    nvidia-common.enable = true;
    btrfs-compression.enable = true;
    monitoring = {
      autoDetect = false;
      fanControl = false;
    };
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      openrazer.enable = false;
      temperatureReactive = {
        enable = true;
        sensor = "cpu";
        thresholds = {
          cool = 50;
          warm = 65;
          hot = 75;
        };
        interval = 5;
      };
    };
  };

  # bcache0 needs the bcache kernel module in initrd so it assembles at boot
  boot.initrd.kernelModules = [ "bcache" ];

  # /, /home, /boot, /nix, /persistent, /games, swap managed by disko.nix
  # Only bcache0 and extra data mounts here

  fileSystems = {
    # --- bcache0 (nexus-storage) subvol mounts ---
    "/home" = {
      device = lib.mkForce "/dev/disk/by-label/nexus-storage";
      fsType = "btrfs";
      options = [
        "subvol=home"
        "compress=zstd"
        "ssd"
        "discard=async"
        "x-initrd.mount"
        "x-systemd.device-timeout=10s"
      ];
      neededForBoot = true;
    };

    "/data/shared" = {
      device = "/dev/disk/by-label/nexus-storage";
      fsType = "btrfs";
      options = [
        "subvol=shared"
        "compress=zstd"
        "ssd"
        "discard=async"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    "/data/backups" = {
      device = "/dev/disk/by-label/nexus-storage";
      fsType = "btrfs";
      options = [
        "subvol=backups"
        "compress=zstd"
        "ssd"
        "discard=async"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

      "/data/media" = {
        device = "/dev/disk/by-label/nexus-storage";
        fsType = "btrfs";
        options = [
          "subvol=media"
          "compress=zstd"
          "ssd"
          "discard=async"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
      };

      "/data/hermes" = {
        device = "/dev/disk/by-label/nexus-storage";
        fsType = "btrfs";
        options = [
          "subvol=hermes"
          "compress=zstd"
          "ssd"
          "discard=async"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
      };

      "/data/models" = {
        device = "/dev/disk/by-label/nexus-storage";
        fsType = "btrfs";
        options = [
          "subvol=models"
          "compress=zstd"
          "ssd"
          "discard=async"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
      };

      "/data/pi" = {
        device = "/dev/disk/by-label/nexus-storage";
        fsType = "btrfs";
        options = [
          "subvol=pi"
          "compress=zstd"
          "ssd"
          "discard=async"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
      };

      "/var/lib/containers" = {
        device = "/dev/disk/by-label/nexus-storage";
        fsType = "btrfs";
        options = [
          "subvol=containers"
          "compress=zstd"
          "ssd"
          "discard=async"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
      };

      # --- NVMe data mounts (legacy, for backward compatibility) ---
      # Note: These services have been moved to bcache0 for better performance
      # and to reduce pressure on the NVMe root filesystem
      "/data/hermes-legacy" = {
        device = "/dev/disk/by-partlabel/disk-nvme1n1-root";
        fsType = "btrfs";
        options = [
          "subvol=@home"
          "compress=zstd"
          "ssd"
          "discard=async"
          "noatime"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
      };

      "/data/models-legacy" = {
        device = "/dev/disk/by-partlabel/disk-nvme1n1-root";
        fsType = "btrfs";
        options = [
          "subvol=@home"
          "compress=zstd"
          "ssd"
          "discard=async"
          "noatime"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
      };

      "/data/pi-legacy" = {
        device = "/dev/disk/by-partlabel/disk-nvme1n1-root";
        fsType = "btrfs";
        options = [
          "subvol=@home"
          "compress=zstd"
          "ssd"
          "discard=async"
          "noatime"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
      };
  };

  boot.kernelParams = [
    "amd_iommu=on"
    "iommu=pt"
    "nvme_core.timeout=30"
    "rootdelay=5"
  ];

  hardware.nvidia.open = lib.mkForce false;
  hardware.nvidia.package = lib.mkForce config.boot.kernelPackages.nvidiaPackages.new_feature;
  hardware.nvidia.powerLimits = {
    enable = true;
    gpus = {
      "3060ti" = {
        index = 0;
        limit = 100; # Tuned for efficiency (min floor)
      };
    };
  };
}