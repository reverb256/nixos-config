{
  config,
  pkgs,
  lib,
  ...
}:
{
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true;
    vulkan.enable = true;
  };

  services.udev.extraRules = ''
    KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"

    SUBSYSTEM=="backlight", KERNEL=="intel_backlight", MODE="0666", RUN+="${pkgs.coreutils}/bin/chown j_kro:j_kro %k/brightness"
  '';

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
      openrazer.enable = true;
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
    ];

    kernelParams = [
      "amd_iommu=on"
      "iommu=pt"
      "processor.max_cstate=1"
      "intel_idle.max_cstate=1"
      "hugepagesz=1G"
      "hugepages=3"
      "btrfs.commit_interval=300"
      "nvidia.NVreg_RegistryDwords=EnableBrightnessControl=1"
    ];
  };

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
