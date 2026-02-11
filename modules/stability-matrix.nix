# StabilityMatrix - Multi-Platform Package Manager for Stable Diffusion
# https://github.com/LykosAI/StabilityMatrix
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.programs.stability-matrix;
  
  # StabilityMatrix version and sources
  version = "2.15.5";
  
  # Download the Linux ZIP release
  src = pkgs.fetchzip {
    url = "https://github.com/LykosAI/StabilityMatrix/releases/download/v${version}/StabilityMatrix-linux-x64.zip";
    sha256 = "sha256-cU3sq4Brs7vR9U/KOooHZcBSJwKKN9Z/ItBvJ6w/ZHM=";
    stripRoot = false;
  };
  
  # The AppImage is inside the extracted directory
  appImagePath = "${src}/StabilityMatrix.Avalonia";
  
  # Desktop entry for StabilityMatrix
  desktopEntry = pkgs.makeDesktopItem {
    name = "StabilityMatrix";
    desktopName = "Stability Matrix";
    comment = "Multi-Platform Package Manager for Stable Diffusion";
    icon = "stability-matrix";
    exec = "stability-matrix %U";
    categories = ["Graphics" "2DGraphics" "RasterGraphics" "Art"];
    keywords = ["stable diffusion" "ai" "image generation" "art"];
    startupNotify = true;
    terminal = false;
  };
in {
  options.programs.stability-matrix = {
    enable = lib.mkEnableOption "StabilityMatrix - Package Manager for Stable Diffusion";
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "$HOME/.stabilitymatrix";
      description = "Directory where StabilityMatrix stores its data and models.";
    };
    
    enableCuda = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable NVIDIA CUDA GPU acceleration.";
    };
    
    enableRocm = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable AMD ROCm GPU acceleration.";
    };
  };
  
  config = lib.mkIf cfg.enable {
    # Add required packages to system
    environment.systemPackages = with pkgs; [
      # Required for running AppImages on NixOS
      appimage-run
      
      # StabilityMatrix wrapper script
      (pkgs.writeShellScriptBin "stability-matrix" ''
        #!/bin/bash
        
        # Set up data directory
        SM_DATA="${cfg.dataDir}"
        mkdir -p "$SM_DATA"
        
        ${lib.optionalString cfg.enableCuda ''
        # NVIDIA CUDA environment variables
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __VK_LAYER_NV_optimus=NVIDIA_only
        export CUDA_PATH=/run/opengl-driver
        export CUDA_HOME=/run/opengl-driver
        export LD_LIBRARY_PATH=/run/opengl-driver/lib:/run/opengl-driver/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        ''}
        
        ${lib.optionalString cfg.enableRocm ''
        # AMD ROCm environment variables
        export ROCM_PATH=/run/opengl-driver
        export HSA_OVERRIDE_GFX_VERSION=10.3.0
        export LD_LIBRARY_PATH=/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        ''}
        
        # Set the data directory for StabilityMatrix
        export STABILITY_MATRIX_DATA="$SM_DATA"
        
        # Run the AppImage
        cd "$SM_DATA"
        exec ${pkgs.appimage-run}/bin/appimage-run ${appImagePath} "$@"
      '')
      
      # Desktop entry
      desktopEntry
    ];
    
    # Add to environment variables
    environment.variables = lib.mkIf cfg.enableCuda {
      # Ensure CUDA is available to StabilityMatrix packages
      CUDA_PATH = "/run/opengl-driver";
      CUDA_HOME = "/run/opengl-driver";
    };
    
    # Note: StabilityMatrix manages its own Python environments and packages
    # The system doesn't need to provide Python or additional ML libraries
  };
}
