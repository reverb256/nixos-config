# LM Studio Headless Service (llmster daemon)
# Runs LM Studio in headless mode using the lms CLI with proper daemon lifecycle
# Based on: https://lmstudio.ai/docs/developer/core/headless_llmster
{
  config,
  lib,
  ...
}: let
  cfg = config.services.lm-studio-headless;
  lmsBin = "/home/${cfg.user}/.lmstudio/bin/lms";
in {
  options.services.lm-studio-headless = {
    enable = lib.mkEnableOption "LM Studio headless service (llmster daemon)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 1234;
      description = "Port for LM Studio API server";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address to bind to";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to run LM Studio as (must have lms CLI installed)";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall for the configured port";
    };

    # GPU configuration
    gpuDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 1;
      description = "GPU device ID to use (null = all GPUs, 0 = first GPU, 1 = second)";
    };

    gpuSplit = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "auto";
      description = "GPU split strategy for multi-GPU (auto, gpu_0, gpu_1, etc.)";
    };

    # Model preloading (optional - JIT loading available if not set)
    preloadModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "qwen/qwen3.5-35b-a3b-instruct";
      description = "Model to preload at startup (null = JIT loading)";
    };

    modelLoadArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["--context-length" "262144" "--gpu-split" "auto"];
      description = "Additional arguments for 'lms load' command";
    };

    # Server options
    contextLength = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 262144;
      description = "Default context length in tokens";
    };

    # Model storage
    modelsPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.user}/.lmstudio/models";
      description = "Path to store downloaded models";
    };

    # CUDA library path (for LM Studio's CUDA backend)
    # LM Studio extracts its AppImage to ~/.lmstudio/app-*/
    cudaLibPath = lib.mkOption {
      type = lib.types.str;
      # Default uses wildcard for auto-detection at runtime
      # The shell script will expand ~/.lmstudio/app-* to find the actual directory
      default = "~/.lmstudio/app-*/resources/app/.webpack/bin/extensions/backends/vendor/linux-llama-cuda-vendor-v1";
      description = "Path to LM Studio's CUDA vendor libraries (supports * wildcard for version-agnostic path)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Open firewall if requested
    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;

    # Create models directory with correct permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.modelsPath} 0755 ${cfg.user} users - -"
    ];

    # Helper script to resolve wildcard and set LD_LIBRARY_PATH
    # LM Studio stores CUDA libraries in versioned app-* directories
    # We expand the wildcard at runtime to avoid hardcoded store paths
    environment.etc."lm-studio/cuda-setup.sh".text = ''
      # Resolve wildcard in CUDA library path
      # First try: expand wildcard in user's .lmstudio directory
      CUDA_LIB_PATH=$(echo /home/${cfg.user}/.lmstudio/app-*/resources/app/.webpack/bin/extensions/backends/vendor/linux-llama-cuda-vendor-v1 2>/dev/null | head -n1)
      # Second try: use the configured path (may contain ~ or wildcards)
      if [ -z "$CUDA_LIB_PATH" ] || [ ! -d "$CUDA_LIB_PATH" ]; then
        # Expand ~ in configured path and try again
        CONFIG_PATH="${cfg.cudaLibPath}"
        CONFIG_PATH="''${CONFIG_PATH/#\~/$HOME}"
        CUDA_LIB_PATH=$(echo $CONFIG_PATH 2>/dev/null | head -n1)
      fi

      # Find all llama.cpp backend directories and add them to LD_LIBRARY_PATH
      # This ensures bundled libraries are loaded before system libraries
      BACKEND_DIRS=$(echo /home/${cfg.user}/.lmstudio/extensions/backends/llama.cpp-*)
      for dir in $BACKEND_DIRS; do
        if [ -d "$dir" ]; then
          export LD_LIBRARY_PATH="$dir:''${LD_LIBRARY_PATH:-}"
        fi
      done

      # Set LD_LIBRARY_PATH if we found a valid CUDA path
      if [ -n "$CUDA_LIB_PATH" ] && [ -d "$CUDA_LIB_PATH" ]; then
        export LD_LIBRARY_PATH="$CUDA_LIB_PATH:''${LD_LIBRARY_PATH:-}"
      fi
    '';

    # Systemd service for LM Studio headless mode with proper daemon lifecycle
    systemd.services.lm-studio-headless = let
      # Build CUDA device environment variable (empty string if no GPU specified)
      gpuEnv = lib.optionalString (cfg.gpuDevice != null) "CUDA_VISIBLE_DEVICES=${toString cfg.gpuDevice}";

      # Path to the CUDA setup script
      cudaSetup = "/etc/lm-studio/cuda-setup.sh";
    in {
      description = "LM Studio Headless Service (llmster daemon)";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      # Build environment
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Note: We don't set User= here because we use 'su -' to run commands
        # This ensures the lms CLI runs in the correct user context with HOME set properly

        # PATH for root (su will set PATH for the target user)
        Environment = [
          "PATH=/run/current-system/sw/bin"
        ];

        # Daemon lifecycle following official docs:
        # https://lmstudio.ai/docs/developer/core/headless_llmster
        #
        # IMPORTANT: Commands must run as the target user via 'su -'
        # The lms CLI stores state in the user's home directory (~/.lmstudio/)
        #
        # ExecStartPre steps:
        # 1. lms daemon up - Start the llmster daemon
        # 2. lms load <model> --yes - Preload model (if configured)
        #
        # ExecStart:
        # lms daemon up && lms server start - Start daemon and HTTP server
        #
        # ExecStop:
        # lms daemon down - Clean shutdown

        ExecStartPre = lib.optionalString (cfg.preloadModel != null) ''
          /bin/sh -c '. ${cudaSetup} && ${gpuEnv} su - ${cfg.user} -c "LD_LIBRARY_PATH=$LD_LIBRARY_PATH ${lmsBin} daemon up" &&
                  . ${cudaSetup} && ${gpuEnv} su - ${cfg.user} -c "LD_LIBRARY_PATH=$LD_LIBRARY_PATH ${lmsBin} load ${cfg.preloadModel} --yes ${lib.escapeShellArgs cfg.modelLoadArgs}"'
        '';

        ExecStart = ''
          /bin/sh -c '. ${cudaSetup} && ${gpuEnv} su - ${cfg.user} -c "LD_LIBRARY_PATH=$LD_LIBRARY_PATH ${lmsBin} daemon up && ${lmsBin} server start --port ${toString cfg.port} --bind ${cfg.host}"'
        '';

        ExecStop = "/bin/sh -c 'su - ${cfg.user} -c \"${lmsBin} daemon down\"'";

        # Restart on failure
        Restart = "on-failure";
        RestartSec = "10s";

        # Timeouts
        TimeoutStartSec = "300"; # 5 minutes for model loading
        TimeoutStopSec = "60";

        # Security settings
        NoNewPrivileges = true;
        PrivateTmp = true;

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";

        # Watchdog for health monitoring
        WatchdogSec = "30s";
      };
    };
  };

  # Meta information
  meta.maintainers = with lib.maintainers; [];
}
