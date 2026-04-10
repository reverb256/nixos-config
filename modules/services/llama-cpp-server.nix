# llama.cpp server - OpenAI-compatible API for local GGUF models
# Uses CUDA build with GPU-only inference via --override-tensor.
# Targets a specific GPU via CUDA_VISIBLE_DEVICES.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.llama-cpp-server;

  # Custom CUDA build with proper library resolution
  llama-cpp-cuda = pkgs.callPackage ../../packages/llama-cpp-cuda.nix { };

  # Library path for the CUDA build's bundled ggml libs
  llamaLibPath = "${llama-cpp-cuda}/lib";
in
{
  options.services.llama-cpp-server = {
    enable = lib.mkEnableOption "llama.cpp server for local GGUF inference";

    model = lib.mkOption {
      type = lib.types.str;
      description = "Path to the GGUF model file";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1234;
      description = "Port for the OpenAI-compatible API";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to bind to";
    };

    contextLength = lib.mkOption {
      type = lib.types.int;
      default = 8192;
      description = "Maximum context length in tokens";
    };

    gpuDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "CUDA device index to use (sets CUDA_VISIBLE_DEVICES). null = all GPUs";
    };

    cacheType = lib.mkOption {
      type = lib.types.str;
      default = "f16";
      description = "KV cache quantization type (f16, q8_0, q4_0)";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to run the server as";
    };

    alias = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Alias for the model (used as model ID in API)";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments for llama-server";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];

    systemd.services.llama-cpp-server = {
      description = "llama.cpp OpenAI-compatible server (CUDA)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart =
          let
            llamaServer = lib.getExe llama-cpp-cuda;
          in
          ''
            ${llamaServer} \
              --model ${cfg.model} \
              --host ${cfg.host} \
              --port ${toString cfg.port} \
              --n-gpu-layers -1 \
              --override-tensor ".*=CUDA0" \
              --ctx-size ${toString cfg.contextLength} \
              --cache-type-k ${cfg.cacheType} \
              --cache-type-v ${cfg.cacheType} \
              --parallel 4 \
              --cont-batching \
              --metrics \
              ${lib.optionalString (cfg.alias != null) "--alias ${cfg.alias}"} \
              ${lib.escapeShellArgs cfg.extraArgs}
          '';
        Restart = "on-failure";
        RestartSec = "5s";
        Environment = [
          # Use the CUDA build's bundled ggml libs (not system's mismatched ones)
          "LD_LIBRARY_PATH=${llamaLibPath}"
          # Pin to specific GPU if configured
        ]
        ++ lib.optional (cfg.gpuDevice != null) "CUDA_VISIBLE_DEVICES=${toString cfg.gpuDevice}";
      };
    };
  };
}
