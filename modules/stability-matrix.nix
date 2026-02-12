# StabilityMatrix - Multi-Platform Package Manager for Stable Diffusion
# https://github.com/LykosAI/StabilityMatrix
#
# Packaged using appimageTools.wrapType2 for proper NixOS integration
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.programs.stability-matrix;
  inherit (pkgs) appimageTools fetchzip;

  # StabilityMatrix version
  version = "2.15.5";
  pname = "stability-matrix";

  # Fetch and extract the zip containing the AppImage
  extracted-zip = fetchzip {
    url = "https://github.com/LykosAI/StabilityMatrix/releases/download/v${version}/StabilityMatrix-linux-x64.zip";
    sha256 = "sha256-BD7NOeR4+EIHzBr6mF/eru8rmuS+Akk9+d+pXJGmzjY=";
  };

  src = "${extracted-zip}/StabilityMatrix.AppImage";

  # Extract AppImage contents for desktop integration
  appimageContents = appimageTools.extract {
    inherit pname version src;
  };

  # Wrap the AppImage with required libraries
  wrappedApp = appimageTools.wrapType2 {
    inherit pname version src;

    # Required libraries for .NET/Avalonia and Python
    extraPkgs = pkgs: [
      pkgs.icu             # .NET globalization support
      pkgs.libxcrypt       # Python crypt module
      pkgs.libxcrypt-legacy # Legacy crypt support for bundled Python
    ];
  };
in {
  options.programs.stability-matrix = {
    enable = lib.mkEnableOption "StabilityMatrix - Package Manager for Stable Diffusion";

    dataDir = lib.mkOption {
      type = lib.types.str;
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
    environment.systemPackages = [
      # Wrapper script that sets environment and runs the AppImage
      (pkgs.writeShellScriptBin "stability-matrix" ''
        #!/bin/bash

        # Expand the data directory path
        SM_DATA="$(eval echo "${cfg.dataDir}")"

        # Create data directory
        mkdir -p "$SM_DATA"

        # Add build tools to PATH for UV package builds (e.g., insightface with C++ extensions)
        # UV_NO_BUILD_ISOLATION=1 disables isolated builds so UV uses current environment's compilers
        # This is required on NixOS where compilers aren't in FHS paths like /usr/bin
        export PATH="${pkgs.gcc}/bin:${pkgs.cmake}/bin:${pkgs.pkg-config}/bin:$PATH"
        export CC="${pkgs.gcc}/bin/gcc"
        export CXX="${pkgs.gcc}/bin/g++"
        export UV_NO_BUILD_ISOLATION=1

        ${lib.optionalString cfg.enableCuda ''
        # NVIDIA CUDA environment variables
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __VK_LAYER_NV_optimus=NVIDIA_only
        export CUDA_PATH=/run/opengl-driver
        export CUDA_HOME=/run/opengl-driver
        export LD_LIBRARY_PATH=/run/opengl-driver/lib:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        ''}

        ${lib.optionalString cfg.enableRocm ''
        # AMD ROCm environment variables
        export ROCM_PATH=/run/opengl-driver
        export HSA_OVERRIDE_GFX_VERSION=10.3.0
        export LD_LIBRARY_PATH=/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        ''}

        # Set the data directory for StabilityMatrix
        export STABILITY_MATRIX_DATA="$SM_DATA"

        # Run from data directory using steam-run for FHS compatibility
        # This ensures UV can find compilers for building packages with C/C++ extensions
        cd "$SM_DATA"
        exec ${pkgs.steam-run}/bin/steam-run \
          --setenv=PATH="$PATH" \
          --setenv=CC="$CC" \
          --setenv=CXX="$CXX" \
          --setenv=UV_NO_BUILD_ISOLATION=1 \
          ${wrappedApp}/bin/${pname} "$@"
      '')

      # Desktop entry
      (pkgs.makeDesktopItem {
        name = "StabilityMatrix";
        desktopName = "Stability Matrix";
        comment = "Multi-Platform Package Manager for Stable Diffusion";
        icon = "${appimageContents}/usr/share/icons/hicolor/512x512/apps/zone.lykos.stabilitymatrix.png";
        exec = "stability-matrix %U";
        categories = ["Graphics" "2DGraphics" "RasterGraphics" "Art"];
        keywords = ["stable diffusion" "ai" "image generation" "art"];
        startupNotify = true;
        terminal = false;
      })
    ];

    # Environment variables for CUDA
    environment.variables = lib.mkIf cfg.enableCuda {
      CUDA_PATH = "/run/opengl-driver";
      CUDA_HOME = "/run/opengl-driver";
    };
  };
}
