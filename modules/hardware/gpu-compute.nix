# Universal GPU Compute Support Module
# Provides CUDA, ROCm, and Vulkan compute support across all hosts
# Enables llama.cpp and other GPU-accelerated workloads
#
# Follows official NixOS CUDA wiki: https://wiki.nixos.org/wiki/CUDA
# Key principle: Use binary cache from cache.nixos-cuda.org
#
# IMPORTANT: Avoid cudatoolkit and cuda_compat - they are problematic:
# - cuda_compat is Jetson-only (aarch64), not x86_64
# - cudatoolkit may pull in broken dependencies
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

    # CUDA support (NVIDIA GPUs)
    cuda = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable CUDA support (NVIDIA GPUs)";
      };
    };

    # ROCm support (AMD GPUs)
    rocm = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable ROCm support (AMD GPUs)";
      };
    };

    # Vulkan compute (universal GPU backend)
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
      # CUDA packages for x86_64 systems
      # Using cudaPackages (defaults to latest CUDA 12.x)
      # FIXED: allowUnsupportedSystem=false prevents cuda_compat (Jetson/ARM64) on x86_64
      # See: https://github.com/NixOS/nixpkgs/issues/458799
      cudaPackages = with pkgs.cudaPackages; [
        cuda_cudart # Core CUDA runtime library (sufficient for llama.cpp)
      ];

      # ROCm packages for AMD GPUs
      rocmPackages = with pkgs.rocmPackages; [
        clr # ROCm Core Runtime
        clr.icd # OpenCL ICD loader
        rocm-smi # ROCm System Management Interface
      ];

      # Vulkan packages for universal GPU compute
      vulkanPackages = with pkgs; [
        vulkan-loader
        vulkan-tools
        vulkan-headers
      ];
    in
      lib.mkMerge [
        # CUDA support (NVIDIA GPUs)
        # NOTE: NVIDIA drivers are already configured by nvidia-common.nix
        # This module only adds CUDA runtime libraries for compute workloads
        (lib.mkIf cfg.cuda.enable {
          environment.systemPackages = cudaPackages;

          # Use common environment variables module for CUDA
          # environment.common.cuda.enable = true;  # DISABLED: Module not loaded
        })

        # ROCm support (AMD GPUs)
        (lib.mkIf cfg.rocm.enable {
          environment.systemPackages = rocmPackages;

          # Use common environment variables module for ROCm
          # environment.common.rocm.enable = true;  # DISABLED: Module not loaded

          # Ensure amdgpu driver is loaded
          boot.kernelModules = ["amdgpu"];
        })

        # Vulkan compute support (universal)
        (lib.mkIf cfg.vulkan.enable {
          environment.systemPackages = vulkanPackages;
        })
      ]
  );
}
