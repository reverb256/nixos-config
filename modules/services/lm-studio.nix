# LM Studio - Local LLM runner with GPU support
# Uses the custom lmstudio package (version 0.4.6-1)
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
    enable = lib.mkEnableOption "LM Studio - Local LLM runner with GPU acceleration";
  };

  config = lib.mkIf cfg.enable {
    # Allow unfree package (LM Studio is proprietary)
    nixpkgs.config.allowUnfreePredicate =
      pkg:
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

        # Find NVIDIA library directory and add to LD_LIBRARY_PATH
        # This ensures LM Studio can find NVML (libnvidia-ml.so.1) for GPU VRAM queries
        NVIDIA_LIB_DIR=$(dirname $(find /nix/store -name "libnvidia-ml.so.1" 2>/dev/null | grep -v "lib32" | head -1))
        if [ -n "$NVIDIA_LIB_DIR" ]; then
          export LD_LIBRARY_PATH="$NVIDIA_LIB_DIR''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        fi

        exec ${pkgs.lmstudio}/bin/lmstudio "$@"
      '')
    ];
  };
}
