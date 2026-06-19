{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.gpu-compute;
  inherit (lib) mkEnableOption mkOption mkIf types;
in {
  options.hardware.gpu-compute = {
    enable = mkEnableOption "Universal GPU compute support (CUDA/ROCm/Vulkan)";

    cuda = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable CUDA support (NVIDIA GPUs)";
      };
    };

    rocm = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable ROCm support (AMD GPUs)";
      };
    };

    vulkan = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Vulkan compute support";
      };
    };
  };

  config = mkIf cfg.enable (
    let
      cudaPackages = with pkgs.cudaPackages; [
        cuda_cudart
      ];

      rocmPackages = with pkgs.rocmPackages; [
        clr
        clr.icd
        rocm-smi
      ];

      vulkanPackages = with pkgs; [
        vulkan-loader
        vulkan-tools
        vulkan-headers
      ];
    in
      lib.mkMerge [
        (lib.mkIf cfg.cuda.enable {
          environment.systemPackages = cudaPackages;
        })

        (lib.mkIf cfg.rocm.enable {
          environment.systemPackages = rocmPackages;

          boot.kernelModules = ["amdgpu"];
        })

        (lib.mkIf cfg.vulkan.enable {
          hardware.graphics = {
            enable = true;
            extraPackages = with pkgs; [ mesa ];
          };

          environment.systemPackages = vulkanPackages;
        })
      ]
  );
}
