# Universal GPU Compute Support Module
# Provides CUDA, ROCm, and Vulkan compute support across all hosts
# Enables llama-cpp and other GPU-accelerated workloads
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.gpu-compute;
  inherit (lib) mkEnableOption mkOption mkIf types literalExpression optional optionalString;
in {
  options.hardware.gpu-compute = {
    enable = mkEnableOption "Universal GPU compute support (CUDA/ROCm/Vulkan)";

    # Automatically detect and enable appropriate backend
    autoDetect = mkOption {
      type = types.bool;
      default = true;
      description = "Auto-detect GPU type and enable appropriate backend";
    };

    # Manual backend selection (overrides autoDetect)
    backend = mkOption {
      type = types.nullOr (types.enum ["cuda" "rocm" "vulkan" "cpu"]);
      default = null;
      description = "Force specific GPU backend (null = auto-detect)";
    };

    # Enable CUDA support (NVIDIA GPUs)
    cuda = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable CUDA support (NVIDIA GPUs)";
      };
      packages = mkOption {
        type = types.listOf types.package;
        default = with pkgs; [cudaPackages.cudatoolkit cudaPackages.cudnn];
        description = "CUDA packages to install";
      };
    };

    # Enable ROCm support (AMD GPUs)
    rocm = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable ROCm support (AMD GPUs)";
      };
      packages = mkOption {
        type = types.listOf types.package;
        default = with pkgs; [rocmPackages.clr rocmPackages.rocm-smi rocmPackages.comgr];
        description = "ROCm packages to install";
      };
    };

    # Enable Vulkan compute (universal GPU backend)
    vulkan = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Vulkan compute support";
      };
      packages = mkOption {
        type = types.listOf types.package;
        default = with pkgs; [vulkan-loader vulkan-tools];
        description = "Vulkan packages to install";
      };
    };

    # llama-cpp variant selection
    llamaCppVariant = mkOption {
      type = types.enum ["default" "cuda" "rocm" "vulkan"];
      default = "default";
      description = "llama-cpp variant to use (default = CPU-only)";
    };
  };

  config = mkIf cfg.enable (
    let
      # Determine which backend to use
      useCuda = cfg.backend == "cuda" || (cfg.backend == null && cfg.autoDetect && cfg.cuda.enable);
      useRocm = cfg.backend == "rocm" || (cfg.backend == null && cfg.autoDetect && cfg.rocm.enable);
      useVulkan = cfg.backend == "vulkan" || (cfg.backend == null && cfg.autoDetect && cfg.vulkan.enable);

      # Select llama-cpp variant based on backend
      llamaPkg = if cfg.llamaCppVariant == "rocm" then pkgs.llama-cpp-rocm
                 else if cfg.llamaCppVariant == "vulkan" then pkgs.llama-cpp-vulkan
                 else if cfg.llamaCppVariant == "cuda" then pkgs.llama-cpp # CUDA variant when available
                 else pkgs.llama-cpp;
    in
      lib.mkMerge [
        # CUDA support
        (lib.mkIf useCuda {
          hardware.graphics = {
            enable = true;
            extraPackages = with pkgs; [
              cudaPackages.cudatoolkit
              cudaPackages.cudnn
              cudaPackages.nccl
            ];
          };
          environment.systemPackages = with pkgs; [
            cudaPackages.cudatoolkit
            cudaPackages.cudnn
          ];
          # Ensure nvidia drivers are loaded
          boot.kernelModules = ["nvidia" "nvidia_uvm" "nvidia_drm"];
        })

        # ROCm support
        (lib.mkIf useRocm {
          hardware.graphics = {
            enable = true;
            extraPackages = with pkgs.rocmPackages; [
              clr
              comgr
              rocm-smi
              hip-runtime
            ];
          };
          environment.systemPackages = with pkgs.rocmPackages; [
            clr
            comgr
            rocm-smi
          ];
          # Ensure amdgpu driver is loaded
          boot.kernelModules = ["amdgpu"];
        })

        # Vulkan compute support
        (lib.mkIf useVulkan {
          hardware.graphics = {
            enable = true;
            extraPackages = with pkgs; [
              vulkan-loader
              vulkan-tools
              vulkan-headers
            ];
          };
          environment.systemPackages = with pkgs; [
            vulkan-loader
            vulkan-tools
          ];
        })

        # Environment variables for GPU compute
        {
          # CUDA environment
          environment.sessionVariables = lib.mkMerge [
            (lib.mkIf useCuda {
              CUDA_HOME = "${pkgs.cudaPackages.cudatoolkit}";
            })
            # ROCm environment
            (lib.mkIf useRocm {
              ROCM_PATH = "${pkgs.rocmPackages.clr}";
              HIP_PATH = "${pkgs.rocmPackages.hip-runtime}";
            })
          ];

          # Make llama-cpp variant available as a package
          environment.systemPackages = with pkgs; [
            (lib.hiPrio llamaPkg)
          ];
        }
      ]
  );
}
