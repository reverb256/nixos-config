# LM Studio - Local LLM runner with GPU support
# Custom build from AppImage with CUDA, Vulkan, and NVIDIA GPU acceleration
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.lm-studio;
in {
  options.programs.lm-studio = {
    enable = lib.mkEnableOption "LM Studio - Local LLM runner with GPU acceleration";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (let
        version = "0.4.2-2";
        src = pkgs.fetchurl {
          url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
          hash = "sha256-JxGlqgsuLcW81mOIcntVFSHv19zSFouIChgz/egc+J0=";
        };
        appimageContents = pkgs.appimageTools.extractType2 {
          inherit version src;
          pname = "lm-studio";
        };
      in
        pkgs.buildFHSEnv {
          name = "lm-studio";
          targetPkgs = pkgs:
            with pkgs; [
              ocl-icd
              cudaPackages.cuda_cudart
              cudaPackages.libcublas
              cudaPackages.libcufft
              cudaPackages.libcusparse
              cudaPackages.libcusolver
              cudaPackages.cudnn
              vulkan-loader
              vulkan-headers
              libGL
              libglvnd
              stdenv.cc.cc.lib
              glib
              nss
              nspr
              dbus
              libdrm
              fontconfig
              freetype
              zlib
              alsa-lib
              cups
              expat
              libxkbcommon
              wayland
            ];
          extraBwrapArgs = [
            "--ro-bind /run/opengl-driver /run/opengl-driver"
            "--ro-bind /run/agenix.d /run/agenix.d"
          ];
          runScript = "${pkgs.bash}/bin/bash -c 'exec ${appimageContents}/AppRun --no-sandbox \"$@\"' --";
          profile = ''
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            export CUDA_VISIBLE_DEVICES=0
            export VK_ICD_FILENAMES="/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
            export XDG_DATA_DIRS="/run/opengl-driver/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
          '';
          extraInstallCommands = ''
                  mkdir -p $out/bin
                  cat > $out/bin/lms << 'EOF'
            #!/bin/bash
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            export CUDA_VISIBLE_DEVICES=0
            export LD_LIBRARY_PATH="/run/opengl-driver/lib:/run/opengl-driver/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export VK_ICD_FILENAMES="/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
            exec ${pkgs.steam-run}/bin/steam-run ${appimageContents}/resources/app/.webpack/lms "$@"
            EOF
                  chmod +x $out/bin/lms
                  mkdir -p $out/share/applications
                  cat > $out/share/applications/lm-studio.desktop << 'EOF'
            [Desktop Entry]
            Name=LM Studio
            Comment=Run local LLMs with GPU acceleration
            Exec=lm-studio %U
            Icon=lm-studio
            Categories=Development;IDE;
            Terminal=false
            Type=Application
            EOF
                  mkdir -p $out/share/icons/hicolor/0x0/apps
                  cp ${appimageContents}/usr/share/icons/hicolor/0x0/apps/lm-studio.png $out/share/icons/hicolor/0x0/apps/
          '';
        })
    ];
  };
}
