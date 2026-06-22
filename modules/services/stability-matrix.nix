{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.programs.stability-matrix;
  inherit (pkgs) appimageTools fetchzip;
  version = "2.16.1";
  pname = "stability-matrix";
  extracted-zip = fetchzip {
    url = "https://github.com/LykosAI/StabilityMatrix/releases/download/v${version}/StabilityMatrix-linux-x64.zip";
    sha256 = "sha256-B69QCmndiP+ug20NFZPosympOcHJw69MWhZi56ekD7s=";
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
      pkgs.libayatana-appindicator
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
    #!/usr/bin/env bash
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
    # Fix uv 0.9.30 exclude-newer cutoff blocking recently-published packages
    # (e.g. comfyui-frontend-package==1.42.15 published after uv's build date)
    export UV_EXCLUDE_NEWER="2099-01-01T00:00:00Z"
    # Pass DBus session address for system tray icon (steam-run strips it)
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    cd "$SM_DATA"
    exec ${pkgs.steam-run}/bin/steam-run ${wrappedApp}/bin/${pname} "$@"
  '';
  # Patches ComfyUI Manager prestartup_script.py to handle broken stderr pipe.
  # Stability Matrix pipes stderr to its launcher; when SM exits or the pipe breaks,
  # flush() on tqdm progress writes raises BrokenPipeError crashing the KSampler.
  # See: https://github.com/Comfy-Org/ComfyUI-Manager/issues/28
  comfyui-manager-patch = pkgs.writeShellScript "patch-comfyui-manager-pipe" ''
    TARGET="$HOME/.stabilitymatrix/Packages/ComfyUI/venv/lib/python3.12/site-packages/comfyui_manager/prestartup_script.py"
    [ ! -f "$TARGET" ] && exit 0
    NEEDS_PATCH=0
    # Check if bare write_stderr/flush exists without try/except
    if grep -qn 'write_stderr(message)''$' "$TARGET" 2>/dev/null; then
      if ! grep -B1 -A2 'write_stderr(message)''$' "$TARGET" | grep -q 'except.*BrokenPipeError'; then
        NEEDS_PATCH=1
      fi
    fi
    if [ "$NEEDS_PATCH" -eq 1 ]; then
      ''${pkgs.gnused}/bin/sed -i \
        -e '/^\(\s*\)write_stderr(message)''$/{ N; s/^\(\s*\)write_stderr(message)\n\(\s*\)original_stderr\.flush()''$/\1try:\n\1    write_stderr(message)\n\1    original_stderr.flush()\n\1except (OSError, ValueError, BrokenPipeError):\n\1    pass/; }' \
        -e '/^\(\s*\)write_stdout(message)''$/{ N; s/^\(\s*\)write_stdout(message)\n\(\s*\)original_stdout\.flush()''$/\1try:\n\1    write_stdout(message)\n\1    original_stderr.flush()\n\1except (OSError, ValueError, BrokenPipeError):\n\1    pass/; }' \
        "$TARGET"
      echo "patch-comfyui-manager: applied BrokenPipeError patches"
    fi
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

    # Auto-patch ComfyUI Manager whenever it's updated (pip install overwrites prestartup_script.py)
    systemd.user.services.patch-comfyui-manager = {
      description = "Patch ComfyUI Manager BrokenPipeError fix";
      serviceConfig.Type = "oneshot";
      script = "${comfyui-manager-patch}";
      # Run on login and after SM package updates
      wantedBy = ["default.target"];
      after = ["graphical-session.target"];
    };
    systemd.user.paths.patch-comfyui-manager = {
      description = "Watch ComfyUI Manager prestartup_script.py for updates";
      wantedBy = ["default.target"];
      pathConfig.PathChanged = "%h/.stabilitymatrix/Packages/ComfyUI/venv/lib/python3.12/site-packages/comfyui_manager/prestartup_script.py";
      pathConfig.Unit = "patch-comfyui-manager.service";
    };
  };
}
