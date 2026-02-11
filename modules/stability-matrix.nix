# StabilityMatrix - Multi-Platform Package Manager for Stable Diffusion
# https://github.com/LykosAI/StabilityMatrix
#
# This module provides a wrapper script that downloads and runs StabilityMatrix.
# The AppImage is downloaded on first run and cached in the user's data directory.
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.programs.stability-matrix;
  
  # StabilityMatrix version
  version = "2.15.5";
  
  # Download URL for the Linux release
  downloadUrl = "https://github.com/LykosAI/StabilityMatrix/releases/download/v${version}/StabilityMatrix-linux-x64.zip";
  
  # Fetch the icon from the StabilityMatrix repo
  icon = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/LykosAI/StabilityMatrix/main/StabilityMatrix.Avalonia/Assets/Icon.png";
    hash = "sha256-DDLc1WDfra5sjMFIb7oSJ+nPk6VeO6JiVx6DBS4b8i4=";
  };
  
  # Desktop entry for StabilityMatrix
  desktopEntry = pkgs.makeDesktopItem {
    name = "StabilityMatrix";
    desktopName = "Stability Matrix";
    comment = "Multi-Platform Package Manager for Stable Diffusion";
    icon = "${icon}";
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
      type = lib.types.str;
      default = "$HOME/.stabilitymatrix";
      description = "Directory where StabilityMatrix stores its data, models, and cached AppImage.";
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
      
      # Required for downloading and extracting the release
      curl
      unzip
      
      # StabilityMatrix wrapper script
      (pkgs.writeShellScriptBin "stability-matrix" ''
        #!/bin/bash
        set -e
        
        # Expand the data directory path
        SM_DATA="$(eval echo "${cfg.dataDir}")"
        SM_CACHE="$SM_DATA/.cache"
        SM_APPIMAGE="$SM_CACHE/StabilityMatrix.Avalonia"
        SM_VERSION_FILE="$SM_CACHE/version"
        
        # Current expected version
        EXPECTED_VERSION="${version}"
        
        # Create directories
        mkdir -p "$SM_DATA"
        mkdir -p "$SM_CACHE"
        
        # Download/update AppImage if needed
        if [[ ! -f "$SM_APPIMAGE" ]] || [[ ! -f "$SM_VERSION_FILE" ]] || [[ "$(cat "$SM_VERSION_FILE")" != "$EXPECTED_VERSION" ]]; then
          echo "StabilityMatrix: Downloading version $EXPECTED_VERSION..."
          TMP_DIR=$(mktemp -d)
          trap "rm -rf $TMP_DIR" EXIT
          
          # Download the zip file
          curl -fsSL "${downloadUrl}" -o "$TMP_DIR/StabilityMatrix-linux-x64.zip"
          
          # Extract the AppImage
          unzip -q "$TMP_DIR/StabilityMatrix-linux-x64.zip" -d "$TMP_DIR"
          
          # Find and move the AppImage (the name may vary slightly)
          APPIMAGE_SRC=$(find "$TMP_DIR" -name "StabilityMatrix.Avalonia" -type f | head -1)
          if [[ -z "$APPIMAGE_SRC" ]]; then
            echo "Error: Could not find StabilityMatrix.Avalonia in the extracted archive"
            exit 1
          fi
          
          # Make executable and move to cache
          chmod +x "$APPIMAGE_SRC"
          mv "$APPIMAGE_SRC" "$SM_APPIMAGE"
          
          # Write version file
          echo "$EXPECTED_VERSION" > "$SM_VERSION_FILE"
          
          echo "StabilityMatrix: Download complete!"
        fi
        
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
        
        # Run the AppImage from the data directory
        cd "$SM_DATA"
        exec ${pkgs.appimage-run}/bin/appimage-run "$SM_APPIMAGE" "$@"
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
  };
}
