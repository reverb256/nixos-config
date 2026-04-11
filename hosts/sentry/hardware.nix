# Sentry Hardware Configuration
# RX 5600 XT (AMD GPU), AMD Zen, RGB control (Wraith Prism)
# ROCm setup for AMD GPU compute
{ pkgs, lib, ... }:
{
  # GPU COMPUTE - ROCm/Vulkan support for AI inference
  hardware.gpu-compute = {
    enable = true;
    rocm.enable = true; # ROCm for AMD 5600XT
    vulkan.enable = true; # Vulkan as universal backend
  };

  # HARDWARE PROFILES
  # Base profiles provided by node-profiles.sentry-monitoring:
  # - amd.zen, amdgpu.enable, amdgpu.wayland, monitoring.enable
  hardware = {
    # BTRFS compression and deduplication
    btrfs-compression.enable = true;
    # Hardware monitoring
    monitoring = {
      autoDetect = false; # Disabled: sensors-detect path issues
      fanControl = false; # BIOS fan control for now
    };
    # RGB control for AMD Wraith Prism cooler and MSI motherboard
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      wraithRgb.enable = true; # AMD Wraith Prism cooler
      temperatureReactive = {
        enable = true;
        sensor = "cpu";
        thresholds = {
          cool = 45;
          warm = 60;
          hot = 70;
        };
        interval = 5;
      };
    };
  };

  # ============================================================================
  # KERNEL - XMRig hugepages
  # ============================================================================
  boot.kernelParams = [
    "hugepagesz=1G"
    "hugepages=3"
  ];

  # ============================================================================
  # ROCm SETUP - Libraries and symlinks for AMD GPU
  # ============================================================================
  environment = {
    variables = {
      LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib";
      OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
    };

    systemPackages = with pkgs; [
      rocmPackages.rocm-smi
      rocmPackages.rocminfo
    ];
  };

  systemd.tmpfiles.rules =
    let
      rocmEnv = pkgs.symlinkJoin {
        name = "rocm-combined";
        paths = with pkgs.rocmPackages; [
          clr
          clr.icd
          rocblas
          hipblas
          rpp
        ];
      };
    in
    [
      "R /var/lib/etcd - - - - -"
      "L+ /opt/rocm - - - - ${rocmEnv}"
      "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
    ];
}
