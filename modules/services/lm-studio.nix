{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.lm-studio;
in
{
  options.programs.lm-studio = {
    enable = lib.mkEnableOption "LM Studio - GPU-only local LLM runner";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "lmstudio" ];

    environment.systemPackages = [
      pkgs.lmstudio
      (pkgs.writeShellScriptBin "lm-studio" ''
        #!/bin/bash
        BACKENDS="$HOME/.lmstudio/extensions/backends"
        for d in "$BACKENDS"/llama.cpp-linux-x86_64-avx2-* \
                 "$BACKENDS"/llama.cpp-linux-x86_64-vulkan-*; do
          [ -d "$d" ] || continue
          chmod -R u+w "$d" 2>/dev/null
          find "$d" -name '*.node' -exec truncate -s 0 {} \;
          find "$d" -name '*.so' -delete 2>/dev/null
        done

        LATEST=""
        for d in "$BACKENDS"/llama.cpp-linux-x86_64-nvidia-cuda-*; do
          [ -d "$d" ] || continue
          VER=''${d##*-}
          if [ -z "$LATEST" ]; then
            LATEST="$d"
          elif [ "$VER" \> "''${LATEST##*-}" ]; then
            rm -rf "$LATEST"
            LATEST="$d"
          else
            rm -rf "$d"
          fi
        done

        cd "$HOME"

        NVIDIA_LIB_DIR="/run/opengl-driver/lib"
        CUDA_DIR="$BACKENDS/vendor/linux-llama-cuda12-vendor-v1"
        if [ -d "$CUDA_DIR" ]; then
          for lib in "$NVIDIA_LIB_DIR"/libnvidia-ml.so* "$NVIDIA_LIB_DIR"/libnvidia-ptxjitcompiler.so*; do
            [ -e "$lib" ] && ln -sf "$lib" "$CUDA_DIR"/$(basename "$lib")
          done
        fi

        unset LD_LIBRARY_PATH
        exec ${pkgs.lmstudio}/bin/lmstudio "$@"
      '')
    ];
  };
}
