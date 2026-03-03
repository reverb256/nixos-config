# LM Studio - Local LLM runner with GPU support
# Uses the nixpkgs lmstudio package (version 0.4.5-2)
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
    # Allow unfree package (LM Studio is proprietary)
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "lmstudio"
    ];

    environment.systemPackages = with pkgs; [
      lmstudio

      # Wrapper for GUI launcher
      (pkgs.writeShellScriptBin "lm-studio" ''
        #!/bin/bash
        # LM Studio GUI launcher
        # Changes to /tmp to avoid bwrap issues with /etc/nixos
        cd /tmp
        exec ${pkgs.lmstudio}/bin/lm-studio "$@"
      '')
    ];

    # NVIDIA GPU environment variables
    # NOTE: CUDA_VISIBLE_DEVICES is NOT set to allow all GPUs to be used
    environment.variables = {
      __NV_PRIME_RENDER_OFFLOAD = "1";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
    };
  };
}
