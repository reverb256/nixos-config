# LM Studio - Local LLM runner with NVIDIA GPU support only
# Overlays empty stubs on CPU/Vulkan .node bindings to save ~300MB RAM
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.lm-studio;

  # Create stub files that overlay the real CPU/Vulkan .node bindings
  # inside the LM Studio bwrap sandbox, preventing workers from loading.
  stubs = pkgs.runCommandLocal "lmstudio-backend-stubs" { } ''
    mkdir -p $out/liblmstudio/cpu $out/liblmstudio/vulkan
    truncate -s 0 $out/liblmstudio/cpu/liblmstudio_bindings.node
    truncate -s 0 $out/liblmstudio/vulkan/liblmstudio_bindings_vulkan.node
  '';
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

        # Find extracted AppImage path from the init script
        INIT=$(find /nix/store -maxdepth 1 -name "*lmstudio*-init" -newer /tmp 2>/dev/null | head -1)
        if [ -z "$INIT" ]; then
          INIT=$(find /nix/store -maxdepth 1 -name "*lmstudio*-init" 2>/dev/null | sort -r | head -1)
        fi
        EXTRACTED=$(grep -oP '/nix/store/[^ ]+-extracted' "$INIT" 2>/dev/null || true)

        if [ -z "$EXTRACTED" ]; then
          # Fallback: launch normally without overlay
          exec ${pkgs.lmstudio}/bin/lmstudio "$@"
        fi

        # Build bwrap overlay args to stub all CPU/Vulkan .node files
        # in the extracted AppImage. These are version-pinned paths that
        # match what LM Studio bundled (e.g., 2.12.0 for v0.4.10).
        STUB_ARGS=()
        for binding in "$EXTRACTED"/resources/app/.webpack/bin/liblmstudio/cpu/*.node \
                       "$EXTRACTED"/resources/app/.webpack/bin/liblmstudio/vulkan/*.node; do
          [ -f "$binding" ] || continue
          BASENAME=$(basename "$binding")
          case "$BASENAME" in
            *cuda*) continue ;;  # Keep CUDA bindings
          esac
          STUB_PATH="${stubs}/liblmstudio/cpu/$BASENAME"
          # vulkan bindings have different name
          case "$BASENAME" in
            *vulkan*) STUB_PATH="${stubs}/liblmstudio/vulkan/$BASENAME" ;;
          esac
          # Use the generic cpu stub for all non-cuda bindings
          STUB_ARGS+=(--ro-bind "${stubs}/liblmstudio/cpu/liblmstudio_bindings.node" "$binding")
        done

        # Also stub the extension backend dirs (avx2, vulkan)
        for d in "$EXTRACTED"/resources/app/.webpack/bin/extensions/backends/llama.cpp-linux-x86_64-avx2-* \
                 "$EXTRACTED"/resources/app/.webpack/bin/extensions/backends/llama.cpp-linux-x86_64-vulkan-*; do
          [ -d "$d" ] || continue
          for binding in "$d"/*.node; do
            [ -f "$binding" ] || continue
            STUB_ARGS+=(--ro-bind "${stubs}/liblmstudio/cpu/liblmstudio_bindings.node" "$binding")
          done
        done

        if [ ''${#STUB_ARGS[@]} -eq 0 ]; then
          exec ${pkgs.lmstudio}/bin/lmstudio "$@"
        fi

        # Launch inside bwrap overlay - stubs prevent CPU/Vulkan workers
        exec ${pkgs.bubblewrap}/bin/bwrap \
          --dev-bind /dev /dev \
          --proc /proc \
          --bind / / \
          "''${STUB_ARGS[@]}" \
          -- ${pkgs.lmstudio}/bin/lmstudio "$@"
      '')
    ];
  };
}
