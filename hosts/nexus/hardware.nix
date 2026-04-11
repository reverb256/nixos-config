# Nexus Hardware Configuration
# RTX 3060 Ti (single GPU), AMD Zen, RGB control
# Storage: bcache0 (3.6TB + 465GB cache), nvme1n1 (223.6GB worn-storage)
{ pkgs, lib, ... }:
{
  # GPU COMPUTE - CUDA + Vulkan support for AI inference
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true; # CUDA for NVIDIA RTX 3060 Ti
    vulkan.enable = true; # Vulkan as fallback
  };

  # HARDWARE PROFILES
  # Base profiles provided by node-profiles.nexus-gaming:
  # - amd.zen, nvidia.enable (single GPU), monitoring.enable
  hardware = {
    # NVIDIA GPU support (base driver)
    nvidia-common.enable = true;
    # BTRFS compression and deduplication
    btrfs-compression.enable = true;
    # Hardware monitoring
    monitoring = {
      autoDetect = false; # Disabled: sensors-detect has bug with --auto flag
      fanControl = false; # BIOS fan control for now
    };
    # RGB control for Razer Naga Pro and Gigabyte motherboard
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      openrazer.enable = true; # Razer Naga Pro
      temperatureReactive = {
        enable = true;
        sensor = "cpu"; # Monitor CPU temps
        thresholds = {
          cool = 50;
          warm = 65;
          hot = 75;
        };
        interval = 5;
      };
    };
  };

  # ============================================================================
  # FILESYSTEM COMPRESSION - Enable zstd:3 on all BTRFS filesystems
  # ============================================================================
  fileSystems = {
    "/".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
    ];
    "/home".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
    ];
  };

  # ============================================================================
  # STORAGE - Additional storage mounts (bcache0 subvolumes)
  # ============================================================================
  fileSystems = {
    "/data/home" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = [
        "subvol=home"
        "compress=zstd"
        "ssd"
        "discard=async"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    "/data/shared" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
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
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
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
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
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

    "/var/lib/containers" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
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
  };

  # ============================================================================
  # KERNEL - IOMMU and XMRig hugepages
  # ============================================================================
  boot.kernelParams = [
    "amd_iommu=on" # Enable AMD IOMMU for device passthrough
    "iommu=pt" # IOMMU passthrough mode (better performance)
    "hugepagesz=1G" # For XMRig RandomX performance
    "hugepages=3"
  ];
}
