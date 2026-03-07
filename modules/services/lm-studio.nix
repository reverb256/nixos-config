# LM Studio - Local LLM runner with GPU support
# Uses the custom lmstudio package (version 0.4.6-1)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.lm-studio;
in {
  options.programs.lm-studio = {
    enable = lib.mkEnableOption "LM Studio - Local LLM runner with GPU acceleration";
  };

  config = lib.mkIf cfg.enable {
    # Allow unfree package (LM Studio is proprietary)
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [
        "lmstudio"
      ];

    environment.systemPackages = with pkgs; [
      lmstudio

      # Wrapper for GUI launcher (handles /tmp directory change and NVML library)
      (pkgs.writeShellScriptBin "lm-studio" ''
        #!/bin/bash
        # LM Studio GUI launcher
        # Changes to /tmp to avoid bwrap issues with /etc/nixos
        cd /tmp

        # Find system NVIDIA library directory (for NVML access)
        NVIDIA_LIB_DIR=$(dirname $(find /nix/store -name "libnvidia-ml.so.1" 2>/dev/null | grep -v "lib32" | head -1))

        # LM Studio's bundled CUDA vendor directory (where it sets LD_LIBRARY_PATH)
        LMSTUDIO_CUDA_DIR="$HOME/.lmstudio/extensions/backends/vendor/linux-llama-cuda12-vendor-v1"

        # Create symlink to system NVML library in LM Studio's CUDA directory
        # This works because LM Studio sets LD_LIBRARY_PATH to this directory for its worker process
        if [ -n "$NVIDIA_LIB_DIR" ] && [ -d "$LMSTUDIO_CUDA_DIR" ]; then
          # Create symlinks for all NVIDIA libraries that might be needed
          for lib in "$NVIDIA_LIB_DIR"/libnvidia-ml.so* "$NVIDIA_LIB_DIR"/libnvidia-ptxjitcompiler.so*; do
            if [ -e "$lib" ]; then
              ln -sf "$lib" "$LMSTUDIO_CUDA_DIR"/$(basename "$lib")
            fi
          done
        fi

        exec ${pkgs.lmstudio}/bin/lmstudio "$@"
      '')
    ];
  };
}
