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

    preloadModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "qwen/qwen3.5-35b-a3b-instruct";
      description = "Model to preload at startup (null = JIT loading)";
    };

    modelLoadArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [
        "--context-length"
        "262144"
        "--gpu-split"
        "auto"
      ];
      description = "Additional arguments for 'lms load' command";
    };

    contextLength = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 262144;
      description = "Default context length in tokens";
    };

    modelsPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.user}/.lmstudio/models";
      description = "Path to store downloaded models";
    };

    cudaLibPath = lib.mkOption {
      type = lib.types.str;
      default = "~/.lmstudio/app-*/resources/app/.webpack/bin/extensions/backends/vendor/linux-llama-cuda-vendor-v1";
      description = "Path to LM Studio's CUDA vendor libraries (supports * wildcard for version-agnostic path)";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault (lib.optional cfg.openFirewall cfg.port);

    systemd.tmpfiles.rules = [
      "d ${cfg.modelsPath} 0755 ${cfg.user} users - -"
    ];

    environment.etc."lm-studio/cuda-setup.sh".text = ''
      CUDA_LIB_PATH=$(echo /home/${cfg.user}/.lmstudio/app-*/resources/app/.webpack/bin/extensions/backends/vendor/linux-llama-cuda-vendor-v1 2>/dev/null | head -n1)
      if [ -z "$CUDA_LIB_PATH" ] || [ ! -d "$CUDA_LIB_PATH" ]; then
        CONFIG_PATH="${cfg.cudaLibPath}"
        CONFIG_PATH="''${CONFIG_PATH/#\~/$HOME}"
        CUDA_LIB_PATH=$(echo $CONFIG_PATH 2>/dev/null | head -n1)
      fi

      BACKEND_DIRS=$(echo /home/${cfg.user}/.lmstudio/extensions/backends/llama.cpp-*)
      for dir in $BACKEND_DIRS; do
        if [ -d "$dir" ]; then
          export LD_LIBRARY_PATH="$dir:''${LD_LIBRARY_PATH:-}"
        fi
      done

      if [ -n "$CUDA_LIB_PATH" ] && [ -d "$CUDA_LIB_PATH" ]; then
        export LD_LIBRARY_PATH="$CUDA_LIB_PATH:''${LD_LIBRARY_PATH:-}"
      fi
    '';

    systemd.services.lm-studio-headless = let
      gpuEnv = lib.optionalString (
        cfg.gpuDevice != null
      ) "CUDA_VISIBLE_DEVICES=${toString cfg.gpuDevice}";

      cudaSetup = "/etc/lm-studio/cuda-setup.sh";
    in {
      description = "LM Studio Headless Service (llmster daemon)";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        Environment = [
          "PATH=/run/current-system/sw/bin"
        ];

        ExecStartPre = lib.optionalString (cfg.preloadModel != null) ''
          /bin/sh -c '. ${cudaSetup} && ${gpuEnv} su - ${cfg.user} -c "LD_LIBRARY_PATH=$LD_LIBRARY_PATH ${lmsBin} daemon up" &&
                  . ${cudaSetup} && ${gpuEnv} su - ${cfg.user} -c "LD_LIBRARY_PATH=$LD_LIBRARY_PATH ${lmsBin} load ${cfg.preloadModel} --yes ${lib.escapeShellArgs cfg.modelLoadArgs}"'
        '';

        ExecStart = ''
          /bin/sh -c '. ${cudaSetup} && ${gpuEnv} su - ${cfg.user} -c "LD_LIBRARY_PATH=$LD_LIBRARY_PATH ${lmsBin} daemon up && ${lmsBin} server start --port ${toString cfg.port} --bind ${cfg.host}"'
        '';

        ExecStop = "/bin/sh -c 'su - ${cfg.user} -c \"${lmsBin} daemon down\"'";

        Restart = "on-failure";
        RestartSec = "10s";

        TimeoutStartSec = "300";
        TimeoutStopSec = "60";

        NoNewPrivileges = true;
        PrivateTmp = true;

        StandardOutput = "journal";
        StandardError = "journal";

      };
    };
  };

  meta.maintainers = with lib.maintainers; [];
}
