# vLLM Inference Server - systemd service
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.vllm;
in
{
  options.services.vllm = {
    enable = lib.mkEnableOption "vLLM inference server";

    model = lib.mkOption {
      type = lib.types.str;
      default = "Qwen/Qwen3.5-7B-Instruct";
      description = "Model to serve (HuggingFace identifier)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Port to serve the API on";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to bind the API to";
    };

    tensorParallelSize = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Tensor parallelism size (number of GPUs)";
    };

    gpuMemoryUtilization = lib.mkOption {
      type = lib.types.float;
      default = 0.90;
      description = "GPU memory utilization (0.0-1.0)";
    };

    maxModelLen = lib.mkOption {
      type = lib.types.int;
      default = 32768;
      description = "Maximum context length in tokens";
    };

    args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional vLLM arguments";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.vllm = {
      description = "vLLM Inference Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python312Packages.vllm}/bin/vllm serve ${cfg.model} \
          --host ${cfg.host} \
          --port ${toString cfg.port} \
          --tensor-parallel-size ${toString cfg.tensorParallelSize} \
          --gpu-memory-utilization ${builtins.toString cfg.gpuMemoryUtilization} \
          --max-model-len ${toString cfg.maxModelLen} \
          ${lib.concatStringsSep " " cfg.args}";
        Restart = "on-failure";
        RestartSec = "10s";
        Environment = "CUDA_VISIBLE_DEVICES=0"; # Use RTX 3090 only
      };
    };
  };
}
