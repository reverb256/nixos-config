# modules/profiles/hardware/implementations.nix --- Hardware profile implementations
{
  config,
  lib,
  ...
}: let
  cfg = config.hardware.profiles;
in {
  config = lib.mkMerge [
    (lib.mkIf cfg.amd.enable {
      boot = {
        kernelParams = ["amd_iommu=on" "iommu=pt"]
          ++ lib.optionals cfg.amd.zen [
            "split_lock_detect=off"
            "threadirqs"
            "preempt=full"
          ];
      };
      hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
    })

    (lib.mkIf cfg.intel.enable {
      boot.kernelParams = ["intel_iommu=on" "iommu=pt"];
      hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
    })

    (lib.mkIf cfg.nvidia.enable {
      hardware.nvidia-common.enable = true;
      boot.kernelModules = ["nvidia" "nvidia_uvm" "nvidia_drm" "nvidia_modeset"];
    })

    (lib.mkIf cfg.amdgpu.enable {
      boot = {
        kernelModules = ["amdgpu"];
        initrd.kernelModules = ["amdgpu"];
      };
    })

    (lib.mkIf (cfg.nvidia.multiGpu || cfg.amdgpu.wayland) {
      environment.sessionVariables = lib.mkMerge [
        (lib.mkIf cfg.nvidia.multiGpu {
          CUDA_VISIBLE_DEVICES = "0,1";
          NCCL_P2P_LEVEL = "2";
          NCCL_P2P_DISABLE = "0";
          NCCL_IB_DISABLE = "1";
          NCCL_ALGO = "Tree";
        })
        (lib.mkIf cfg.amdgpu.wayland {
          ROC_ENABLE_PRE_VEGA = "1";
        })
      ];
    })

    (lib.mkIf cfg.corsair.enable {
      hardware.corsair = {
        enable = true;
        aio.enable = true;
        rgb.enable = true;
      };
    })

    (lib.mkIf cfg.monitoring.enable {
      hardware.monitoring.enable = true;
    })
  ];
}
