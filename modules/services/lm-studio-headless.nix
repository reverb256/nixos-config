# LM Studio Headless Service (llmster daemon)
# Runs LM Studio in headless mode using the lms CLI with proper daemon lifecycle
# Based on: https://lmstudio.ai/docs/developer/core/headless_llmster
{
  config,
  lib,
  pkgs,
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
  };

  config = lib.mkIf cfg.enable {
    # Open firewall if requested
    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;

    # Create models directory with correct permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.modelsPath} 0755 ${cfg.user} users - -"
    ];

    # Systemd service for LM Studio headless mode with proper daemon lifecycle
    systemd.services.lm-studio-headless = let
      # Build CUDA device environment variable (empty string if no GPU specified)
      gpuEnv = lib.optionalString (cfg.gpuDevice != null) "CUDA_VISIBLE_DEVICES=${toString cfg.gpuDevice}";
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
          # Add CUDA vendor library path for LM Studio's CUDA backend
          "LD_LIBRARY_PATH=/nix/store/jvfs2y324lhbcjqyplhc3c9ji16z85ak-lmstudio-0.4.6-1-extracted/resources/app/.webpack/bin/extensions/backends/vendor/linux-llama-cuda-vendor-v1:$${LD_LIBRARY_PATH:-}"
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
          /bin/sh -c 'export LD_LIBRARY_PATH=/nix/store/jvfs2y324lhbcjqyplhc3c9ji16z85ak-lmstudio-0.4.6-1-extracted/resources/app/.webpack/bin/extensions/backends/vendor/linux-llama-cuda-vendor-v1:$${LD_LIBRARY_PATH:-} && ${gpuEnv} su - ${cfg.user} -c "${lmsBin} daemon up" &&
                  export LD_LIBRARY_PATH=/nix/store/jvfs2y324lhbcjqyplhc3c9ji16z85ak-lmstudio-0.4.6-1-extracted/resources/app/.webpack/bin/extensions/backends/vendor/linux-llama-cuda-vendor-v1:$${LD_LIBRARY_PATH:-} && ${gpuEnv} su - ${cfg.user} -c "${lmsBin} load ${cfg.preloadModel} --yes ${lib.escapeShellArgs cfg.modelLoadArgs}"'
        '';

        ExecStart = ''
          /bin/sh -c 'export LD_LIBRARY_PATH=/nix/store/jvfs2y324lhbcjqyplhc3c9ji16z85ak-lmstudio-0.4.6-1-extracted/resources/app/.webpack/bin/extensions/backends/vendor/linux-llama-cuda-vendor-v1:$${LD_LIBRARY_PATH:-} && ${gpuEnv} su - ${cfg.user} -c "${lmsBin} daemon up && ${lmsBin} server start --port ${toString cfg.port} --bind ${cfg.host}"'
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
