# LM Studio - Local LLM runner with NVIDIA GPU support only
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
      (pkgs.writeShellScriptBin "lm-studio" ''
        #!/bin/bash
        # Stub CPU/Vulkan backends in user dir to prevent extension re-sync workers
        BACKENDS="$HOME/.lmstudio/extensions/backends"
        for d in "$BACKENDS"/llama.cpp-linux-x86_64-avx2-* \
                 "$BACKENDS"/llama.cpp-linux-x86_64-vulkan-*; do
          [ -d "$d" ] || continue
          chmod -R u+w "$d" 2>/dev/null
          find "$d" -name '*.node' -exec truncate -s 0 {} \;
          find "$d" -name '*.so' -delete 2>/dev/null
        done

        # Remove old CUDA versions - keep only latest
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

        cd /tmp

        # Symlink NVIDIA NVML for GPU monitoring
        NVIDIA_LIB_DIR=$(dirname $(find /nix/store -name "libnvidia-ml.so.1" 2>/dev/null | grep -v "lib32" | head -1))
        CUDA_DIR="$BACKENDS/vendor/linux-llama-cuda12-vendor-v1"
        if [ -n "$NVIDIA_LIB_DIR" ] && [ -d "$CUDA_DIR" ]; then
          for lib in "$NVIDIA_LIB_DIR"/libnvidia-ml.so* "$NVIDIA_LIB_DIR"/libnvidia-ptxjitcompiler.so*; do
            [ -e "$lib" ] && ln -sf "$lib" "$CUDA_DIR"/$(basename "$lib")
          done
        fi

        exec ${pkgs.lmstudio}/bin/lmstudio "$@"
      '')
    ];
  };
}
