# Zephyr Hardware Configuration
# GPU compute, RGB control, AIO cooling, hardware monitoring, Bluetooth
# RTX 3090 + RTX 3060 Ti (multi-GPU), Corsair H115i AIO, Razer Naga Pro
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # ============================================================================
  # GPU COMPUTE - CUDA + Vulkan support for AI inference
  # ============================================================================
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true; # CUDA for NVIDIA RTX 3090 + 3060 Ti
    vulkan.enable = true; # Vulkan as fallback/universal backend
  };

  # DDC/CI support for external monitor brightness control
  services.udev.extraRules = ''
    # Give i2c group access to DDC/CI monitors
    # Allows non-root users to control monitor brightness via ddcutil
    KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"

    # Allow users to control laptop display brightness
    SUBSYSTEM=="backlight", KERNEL=="intel_backlight", MODE="0666", RUN+="${pkgs.coreutils}/bin/chown j_kro:j_kro %k/brightness"
  '';

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  # Base profiles provided by node-profiles.zephyr-workstation:
  # - amd.zen, nvidia.enable, nvidia.multiGpu, monitoring.enable
  #
  # Zephyr-specific hardware overrides/additions:
  hardware = {
    profiles = {
      corsair.enable = true; # Corsair AIO + RGB (not in node profile)
    };

    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

    # Hardware monitoring extras (not covered by profile)
    monitoring = {
      autoDetect = false; # Skip auto-detect, we know the hardware
      fanControl = true; # Custom fan curve control
    };

    # Corsair extras (not covered by profile)
    corsair = {
      aio.enable = true; # Corsair H115i AIO control
      rgb.enable = true; # OpenRGB for RGB control
      autoStartRgb = false; # Don't auto-start (conflicts with liquidctl)
    };

    # Corsair keyboard/mouse driver daemon
    # Starts ckb-next-daemon (creates virtual uinput devices for media keys,
    # per-key RGB, profiles, DPI). GUI connects to daemon for configuration.
    # Without the daemon: no media keys, no RGB control, no profiles.
    ckb-next.enable = true;

    # RGB control for peripherals and components
    rgb-control = {
      enable = true;
      openrgb.enable = true; # Motherboard, GPU, Corsair devices
      openrazer.enable = true; # Razer Naga Pro mouse
      temperatureReactive = {
        enable = true;
        sensor = "both"; # Monitor both CPU and GPU temps
        thresholds = {
          cool = 50;
          warm = 65;
          hot = 75;
        };
        interval = 5;
      };
    };

    # Bluetooth support via BlueZ
    bluetooth.enable = true;
  };

  # ============================================================================
  # KERNEL MODULES - Multi-GPU + hardware support
  # ============================================================================
  boot = {
    # Multi-GPU kernel modules for RTX 3090 + 3060 Ti
    # (Note: hardware.profiles.nvidia.enable adds nvidia modules automatically)
    kernelModules = [
      "nvidia_uvm" # Unified Memory (CRITICAL for multi-GPU!)
    ];

    extraModprobeConfig = ''
      options nvidia NVreg_EnableBacklightHandler=1
    '';

    # Blacklist unused kernel modules to reduce memory footprint
    blacklistedKernelModules = [
      # Audio dummy modules (rarely used on desktop)
      "snd_seq_dummy"
      "snd_hrtimer"

      # Filesystems not used (Zephyr uses ext4/btrfs only)
      "ufs"
      "hfs"
      "hfsplus"
      "reiserfs"

      # Old networking protocols (not used)
      "appletalk"
      "ipx"
      "decnet"
    ];

    # Zephyr-specific kernel params for gaming
    # (Note: hardware.profiles.amd.zen adds split_lock_detect, threadirqs, preempt)
    kernelParams = [
      "amd_iommu=on" # Enable AMD IOMMU for device passthrough
      "iommu=pt" # IOMMU passthrough mode (better performance)
      "processor.max_cstate=1"
      "intel_idle.max_cstate=1"
      "hugepagesz=1G" # For XMRig RandomX performance (dual-xmrig module)
      "hugepages=3"
      "btrfs.commit_interval=300" # From btrfs-tuning module
      "nvidia.NVreg_RegistryDwords=EnableBrightnessControl=1" # Enable laptop brightness control
    ];
  };

  # ============================================================================
  # MULTI-GPU ENVIRONMENT VARIABLES - RTX 3090 + 3060 Ti
  # ============================================================================
  environment.sessionVariables = {
    # GPU visibility
    CUDA_VISIBLE_DEVICES = "0,1";

    # NCCL (NVIDIA Collective Communications Library) settings
    NCCL_P2P_LEVEL = "2"; # PCIe bridge level (P2P limited on heterogeneous GPUs)
    NCCL_P2P_DISABLE = "0"; # Try P2P first, disable if issues occur
    NCCL_IB_DISABLE = "1"; # Disable InfiniBand (not applicable)
    NCCL_ALGO = "Tree"; # Tree algorithm for multi-GPU communication

    # llama.cpp/llama-cpp CUDA settings
    GGML_CUDA_ENABLE_UNIFIED_MEMORY = "1"; # Critical for heterogeneous GPU support
    GGML_CUDA_GPU_MEMORY_FRACTION = "0.9"; # Use 90% of GPU VRAM (leave headroom)
    LLAMA_GRAPH_POOL_SIZE = "0.2"; # CUDA Graphs pool (20% of VRAM)
  };
}
