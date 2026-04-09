# LM Studio - Local LLM runner with NVIDIA GPU support only
# Overlays empty stubs on CPU/Vulkan .node bindings to save ~300MB RAM
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.lm-studio;

  # Create stub files that overlay the real CPU/Vulkan .node bindings
  # inside the LM Studio bwrap sandbox, preventing workers from loading.
  stubs = pkgs.runCommandLocal "lmstudio-backend-stubs" {} ''
    mkdir -p $out/liblmstudio/cpu $out/liblmstudio/vulkan
    # Empty .node files - workers load then immediately exit
    truncate -s 0 $out/liblmstudio/cpu/liblmstudio_bindings.node
    truncate -s 0 $out/liblmstudio/vulkan/liblmstudio_bindings_vulkan.node
    # Also stub the vulkan backend .node files
    mkdir -p $out/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.5.0
    truncate -s 0 $out/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.5.0/liblmstudio_bindings_vulkan.node
    truncate -s 0 $out/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.5.0/llm_engine_vulkan.node
    # Stub the CPU-only backend
    mkdir -p $out/extensions/backends/llama.cpp-linux-x86_64-avx2-2.5.0
    truncate -s 0 $out/extensions/backends/llama.cpp-linux-x86_64-avx2-2.5.0/liblmstudio_bindings.node
    truncate -s 0 $out/extensions/backends/llama.cpp-linux-x86_64-avx2-2.5.0/llm_engine.node
  '';
in {
  options.programs.lm-studio = {
    enable = lib.mkEnableOption "LM Studio - GPU-only local LLM runner";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) ["lmstudio"];

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

        # Find which extracted AppImage dir this build uses
        INIT_LINK=$(readlink -f ${pkgs.lmstudio}/bin/lmstudio)
        EXTRACTED=$(grep -oP '/nix/store/[^ ]+-extracted' "$INIT_LINK" 2>/dev/null || true)

        if [ -z "$EXTRACTED" ]; then
          # Fallback: just launch normally
          exec ${pkgs.lmstudio}/bin/lmstudio "$@"
        fi

        # Launch inside a bwrap overlay that stubs CPU/Vulkan .node files.
        # This prevents the bundled AppImage workers from loading (~300MB saved).
        exec ${pkgs.bubblewrap}/bin/bwrap \
          --dev-bind /dev /dev \
          --proc /proc /proc \
          --bind / / \
          --ro-bind ${stubs}/liblmstudio/cpu/liblmstudio_bindings.node \
            "$EXTRACTED/resources/app/.webpack/bin/liblmstudio/cpu/liblmstudio_bindings.node" \
          --ro-bind ${stubs}/liblmstudio/vulkan/liblmstudio_bindings_vulkan.node \
            "$EXTRACTED/resources/app/.webpack/bin/liblmstudio/vulkan/liblmstudio_bindings_vulkan.node" \
          --ro-bind ${stubs}/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.5.0/liblmstudio_bindings_vulkan.node \
            "$EXTRACTED/resources/app/.webpack/bin/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.5.0/liblmstudio_bindings_vulkan.node" \
          --ro-bind ${stubs}/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.5.0/llm_engine_vulkan.node \
            "$EXTRACTED/resources/app/.webpack/bin/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.5.0/llm_engine_vulkan.node" \
          --ro-bind ${stubs}/extensions/backends/llama.cpp-linux-x86_64-avx2-2.5.0/liblmstudio_bindings.node \
            "$EXTRACTED/resources/app/.webpack/bin/extensions/backends/llama.cpp-linux-x86_64-avx2-2.5.0/liblmstudio_bindings.node" \
          --ro-bind ${stubs}/extensions/backends/llama.cpp-linux-x86_64-avx2-2.5.0/llm_engine.node \
            "$EXTRACTED/resources/app/.webpack/bin/extensions/backends/llama.cpp-linux-x86_64-avx2-2.5.0/llm_engine.node" \
          -- ${pkgs.lmstudio}/bin/lmstudio "$@"
      '')
    ];
  };
}
