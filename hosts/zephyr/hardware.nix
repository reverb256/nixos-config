{
  config,
  pkgs,
  lib,
  ...
}: {
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true;
    vulkan.enable = true;
  };

  hardware.nvidia.powerLimits = {
    enable = true;
    gpus = {
      "3060ti" = {
        index = 0;
        limit = 100;
      };
      "3090" = {
        index = 1;
        limit = 250; # Performance
      };
    };
    profiles = {
      gaming = {
        "3060" = 200;
        "3090" = 150; # Balanced
        "4060" = 110;
      };
      ai = {
        "3060" = 110;
        "3090" = 150; # Balanced
        "4060" = 110; # Balanced
      };
      kubernetes-gpu = {
        "3060" = 150;
        "3090" = 150; # Balanced
        "4060" = 110; # Balanced
      };
      builds = {
        "3060" = 150;
        "3090" = 150; # Balanced
        "4060" = 95;
      };
      mining = {
        "3060" = 100; # Tuned
        "3090" = 150; # Balanced
        "4060" = 110; # Balanced
      };
      idle = {
        "3060" = 200;
        "3090" = 150; # Balanced
        "4060" = 115;
      };
    };
  };

  services.udev.extraRules = ''
    KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"

    SUBSYSTEM=="backlight", KERNEL=="intel_backlight", MODE="0666", RUN+="${pkgs.coreutils}/bin/chown j_kro:j_kro %k/brightness"
  '';

  hardware.nvidia.open = false;

  hardware = {

    profiles = {
      corsair.enable = true;
    };

    btrfs-compression.enable = true;

    monitoring = {
      autoDetect = false;
      fanControl = true;
    };

    corsair = {
      aio.enable = true;
      rgb.enable = true;
      autoStartRgb = false;
    };

    ckb-next.enable = true;

    rgb-control = {
      enable = true;
      openrgb.enable = true;
      openrazer.enable = false;
      temperatureReactive = {
        enable = true;
        sensor = "both";
        thresholds = {
          cool = 50;
          warm = 65;
          hot = 75;
        };
        interval = 5;
      };
    };

    bluetooth.enable = true;
  };

  # Intel AX200 BT adapter needs firmware blobs (ibt-*.sfi, ibt-*.ddc)
  hardware.enableAllFirmware = true;

  boot = {
    kernelModules = [
      "nvidia_uvm"
    ];

    extraModprobeConfig = ''
      options nvidia NVreg_EnableBacklightHandler=1
    '';

    blacklistedKernelModules = [
      "snd_seq_dummy"
      "snd_hrtimer"

      "ufs"
      "hfs"
      "hfsplus"
      "reiserfs"

      "appletalk"
      "ipx"
      "decnet"
      "razermouse"
    ];

    kernelParams = [
      "amd_iommu=on"
      "iommu=pt"
      "processor.max_cstate=1"
      "intel_idle.max_cstate=1"
      "nvidia.NVreg_RegistryDwords=EnableBrightnessControl=1"
      # Override kernel-hardening.nix: user-space oops (Discord, llama-server)
      # should NOT crash the whole workstation. Keep softlockup_panic for real kernel issues.
      "panic_on_oops=0"
      # Fix Intel AX200 Bluetooth FW download failure (-19 ENODEV) — USB autosuspend
      # causes the device to be unresponsive during firmware loading.
      "btusb.enable_autosuspend=0"
    ];
  };

  # BTRFS commit interval - merge with hardware-configuration.nix options
  fileSystems."/".options = ["commit=300"];
  fileSystems."/home".options = ["commit=300"];
  environment.sessionVariables = {
    NCCL_P2P_LEVEL = "2";
    NCCL_P2P_DISABLE = "0";
    NCCL_IB_DISABLE = "1";
    NCCL_ALGO = "Tree";

    GGML_CUDA_ENABLE_UNIFIED_MEMORY = "1";
    GGML_CUDA_GPU_MEMORY_FRACTION = "0.9";
    LLAMA_GRAPH_POOL_SIZE = "0.2";
  };
}
