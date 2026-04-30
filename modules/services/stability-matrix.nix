{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.programs.stability-matrix;
  inherit (pkgs) appimageTools fetchzip;
  version = "2.15.7";
  pname = "stability-matrix";
  extracted-zip = fetchzip {
    url = "https://github.com/LykosAI/StabilityMatrix/releases/download/v${version}/StabilityMatrix-linux-x64.zip";
    sha256 = "sha256-5zYe08p6mq53Bn0JqlF+LBfGUIurwgPqS8XUvKWKx84=";
  };
  src = "${extracted-zip}/StabilityMatrix.AppImage";
  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
  wrappedApp = appimageTools.wrapType2 {
    inherit pname version src;
    extraPkgs = pkgs: [
      pkgs.icu
      pkgs.libxcrypt
      pkgs.libxcrypt-legacy
    ];
  };
  cudaEnv = ''
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    export CUDA_PATH=/run/opengl-driver
    export CUDA_HOME=/run/opengl-driver
    export LD_LIBRARY_PATH=/run/opengl-driver/lib:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export SETUPTOOLS_USE_DISTUTILS=stdlib
  '';
  rocmEnv = ''
    export ROCM_PATH=/run/opengl-driver
    export HSA_OVERRIDE_GFX_VERSION=10.3.0
    export LD_LIBRARY_PATH=/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  '';
  wrapperScript = pkgs.writeShellScriptBin "stability-matrix" ''
    #!/bin/bash
    SM_DATA="$(eval echo "${cfg.dataDir}")"
    mkdir -p "$SM_DATA"
    export PATH="${
      lib.makeBinPath [
        pkgs.gcc
        pkgs.cmake
        pkgs.pkg-config
        pkgs.gnumake
      ]
    }:$PATH"
    export CC="gcc"
    export CXX="g++"
    export AR="ar"
    export RANLIB="ranlib"
    ${lib.optionalString cfg.enableCuda cudaEnv}
    ${lib.optionalString cfg.enableRocm rocmEnv}
    export STABILITY_MATRIX_DATA="$SM_DATA"
    cd "$SM_DATA"
    exec ${pkgs.steam-run}/bin/steam-run ${wrappedApp}/bin/${pname} "$@"
  '';
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
      (pkgs.runCommand "compiler-symlinks" {} ''
        mkdir -p $out/bin
        ln -s ${pkgs.gcc}/bin/g++ $out/bin/c++
        ln -s ${pkgs.gcc}/bin/gcc $out/bin/gcc
        ln -s ${pkgs.gcc}/bin/g++ $out/bin/g++
        ln -s ${pkgs.gcc}/bin/ar $out/bin/ar
        ln -s ${pkgs.gcc}/bin/ranlib $out/bin/ranlib
      '')
      wrapperScript
      (pkgs.makeDesktopItem {
        name = "StabilityMatrix";
        desktopName = "Stability Matrix";
        comment = "Multi-Platform Package Manager for Stable Diffusion";
        icon = "${appimageContents}/usr/share/icons/hicolor/512x512/apps/zone.lykos.stabilitymatrix.png";
        exec = "stability-matrix %U";
        categories = [
          "Graphics"
          "2DGraphics"
          "RasterGraphics"
          "Art"
        ];
        keywords = [
          "stable diffusion"
          "ai"
          "image generation"
          "art"
        ];
        startupNotify = true;
        terminal = false;
      })
    ];
    environment.variables = lib.mkIf cfg.enableCuda {
      CUDA_PATH = lib.mkDefault "/run/opengl-driver";
      CUDA_HOME = lib.mkDefault "/run/opengl-driver";
    };
  };
}
