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
      # Symlink c++/gcc/g++ so UV's isolated builds can find them
      # UV creates isolated build environments that only see standard PATHs
      # These symlinks ensure compilers are discoverable in /run/current-system/sw/bin
      (pkgs.runCommand "compiler-symlinks" {} ''
        mkdir -p $out/bin
        ln -s ${pkgs.gcc}/bin/g++ $out/bin/c++
        ln -s ${pkgs.gcc}/bin/gcc $out/bin/gcc
        ln -s ${pkgs.gcc}/bin/g++ $out/bin/g++
        ln -s ${pkgs.gcc}/bin/ar $out/bin/ar
        ln -s ${pkgs.gcc}/bin/ranlib $out/bin/ranlib
      '')

      # Wrapper script that sets environment and runs the AppImage
      (pkgs.writeShellScriptBin "stability-matrix" ''
        #!/bin/bash

        # Expand the data directory path
        SM_DATA="$(eval echo "${cfg.dataDir}")"

        # Create data directory
        mkdir -p "$SM_DATA"

        # Build environment for UV/pip on NixOS
        # Compiler symlinks are installed system-wide above
        # This means UV's isolated builds will find c++ in standard PATH
        export PATH="${pkgs.gcc}/bin:${pkgs.cmake}/bin:${pkgs.pkg-config}/bin:${pkgs.gnumake}/bin:$PATH"
        export CC="gcc"
        export CXX="g++"
        export AR="ar"
        export RANLIB="ranlib"
        # Keep build isolation ON - setuptools is provided by UV's isolated env
        #unset UV_NO_BUILD_ISOLATION
        #unset PIP_NO_BUILD_ISOLATION

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
        # steam-run inherits exported environment variables
        cd "$SM_DATA"
        exec ${pkgs.steam-run}/bin/steam-run ${wrappedApp}/bin/${pname} "$@"
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
