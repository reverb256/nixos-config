# SGLang Inference Server - High-performance serving for RTX 3090
{ config, lib, pkgs, ... }:
let
  cfg = config.services.sglang;
in
{
  options.services.sglang = {
    enable = lib.mkEnableOption "SGLang inference server";
    model = lib.mkOption {
      type = lib.types.str;
      default = "Qwen/Qwen3.5-35B-A3B-FP8";
      description = "Model to serve (HuggingFace identifier)";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8100;
      description = "Port to serve API on";
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to bind API to";
    };
    gpuDevice = lib.mkOption {
      type = lib.types.str;
      default = "0";
      description = "CUDA device ID (0 = RTX 3090, 1 = RTX 3060 Ti)";
    };
    tensorParallelSize = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Tensor parallelism size (number of GPUs)";
    };
    expertParallelSize = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Expert parallelism size for MoE models";
    };
    gpuMemoryUtilization = lib.mkOption {
      type = lib.types.float;
      default = 0.90;
      description = "GPU memory utilization (0.0-1.0)";
    };
    maxModelLen = lib.mkOption {
      type = lib.types.int;
      default = 262144;
      description = "Maximum context length in tokens (256K for Qwen3.5)";
    };
    reasoningParser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "qwen3";
      description = "Reasoning parser (qwen3 for Qwen3.5)";
    };
    kvCacheQuantization = lib.mkOption {
      type = lib.types.nullOr (lib.types.str);
      default = null;
      description = "KV cache quantization (fp8_e4m, fp8_e5m, int4). Reduces VRAM for 256K context";
    };
    args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--enable-prefix-caching"
        "--disable-log-requests"
        "--max-num-seqs=16"
      ];
      description = "Additional SGLang arguments";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.sglang = {
      description = "SGLang Inference Server for Qwen3.5 on Ampere GPUs";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3Packages.python312}/bin/python3 -m sglang.launch_server --model-path ${cfg.model} --host ${cfg.host} --port ${toString cfg.port} --tp ${toString cfg.tensorParallelSize} --ep ${toString cfg.expertParallelSize} --gpu-memory-utilization ${builtins.toString cfg.gpuMemoryUtilization} --max-model-len ${toString cfg.maxModelLen} ${lib.optionalString (cfg.reasoningParser != null) "--reasoning-parser ${cfg.reasoningParser}" ""} ${lib.optionalString (cfg.kvCacheQuantization != null) "--kv-cache-quantization ${cfg.kvCacheQuantization}" ""} ${lib.concatStringsSep " " " cfg.args}";
        Restart = "on-failure";
        RestartSec = "10s";
        Environment = "CUDA_VISIBLE_DEVICES=${cfg.gpuDevice}";
        User = "root";
      };
    };
    
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellScriptBin "sglang-health" ''
        #!/bin/bash
        curl -s http://${cfg.host}:${toString cfg.port}/v1/models | jq .
      '')
    ];
    
    system.activationScripts.sglang-model-info = ''
      echo "=== SGLang Model Configuration ==="
      echo "Model: ${cfg.model}"
      echo "Reasoning Parser: ${if cfg.reasoningParser != null then cfg.reasoningParser else "none"}"
      echo "GPU Device: CUDA_VISIBLE_DEVICES=${cfg.gpuDevice}"
      echo "Max Context: ${toString cfg.maxModelLen} tokens"
      echo "Tensor Parallelism: ${toString cfg.tensorParallelSize}"
      echo "Expert Parallelism: ${toString cfg.expertParallelSize}"
      echo "KV Cache Quantization: ${if cfg.kvCacheQuantization != null then cfg.kvCacheQuantization else "none"}"
      echo ""
      echo "Available Ampere-optimized models (SGLang recommended):"
      echo "  Qwen/Qwen3.5-35B-A3B-FP8 (18GB VRAM, RTX 3090) - FP8 recommended"
      echo "  Qwen/Qwen3.5-35B-A3B (22GB VRAM, RTX 3090) - BF16 full precision"
      echo "  Qwen/Qwen3.5-27B (16GB VRAM, RTX 3060 Ti)"
      echo "  Qwen/Qwen3.5-9B-Instruct (7GB VRAM, RTX 3060 Ti)"
      echo ""
      echo "=== KV Cache Quantization Options ==="
      echo "  fp8_e4m - 4-bit KV cache for extended context (best VRAM savings)"
      echo "  fp8_e5m - 5-bit KV cache for extended context (better quality)"
      echo "  int4 - 4-bit KV cache (best VRAM, some quality loss)"
      echo ""
      echo "=== SGLang vs vLLM Comparison Notes ==="
      echo "- SGLang has merged Qwen3.5 support (Feb 9, 2026)"
      echo "- vLLM requires nightly builds (0.17.0 not released)"
      echo "- SGLang FP8 mode is well-tested for Qwen3.5"
      echo "- SGLang AWQ has known bug with Qwen3.5-35B-A3B"
      echo "- Both backends support FP8 for Ampere GPUs"
      echo "- Both backends support OpenAI-compatible API"
    '';
  };
}
