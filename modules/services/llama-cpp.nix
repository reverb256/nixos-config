# LLaMA.cpp Inference Server - Fast C++ engine for RTX 3090
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.llama-cpp;

in
{
  options.services.llama-cpp = {
    enable = lib.mkEnableOption "llama.cpp inference server";

    model = lib.mkOption {
      type = lib.types.str;
      default = "unsloth/Qwen3.5-35B-A3B-GGUF"; # Unsloth quantized model
      description = "Model to serve (GGUF file path)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8300;
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

    maxModelLen = lib.mkOption {
      type = lib.types.int;
      default = 262144;
      description = "Maximum context length in tokens (256K for Qwen3.5)";
    };

    contextSize = lib.mkOption {
      type = lib.types.int;
      default = 8192;
      description = "Context window size (8K-256K tokens)";
    };

    threads = lib.mkOption {
      type = lib.types.int;
      default = 24;
      description = "Number of CPU threads for processing";
    };

    args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--no-mmap"
        "--no-checkupgrades"
        "--n-gpu-layers" # Offload to GPU (RTX 3090 has 24GB)
      ];
      description = "Additional llama.cpp arguments";
    };
  };

  config = lib.mkIf cfg.enable {
    # llama.cpp from nixpkgs (if available)
    # If not available, we need to build it manually
    systemd.services.llama-cpp = {
      description = "llama.cpp Inference Server for Qwen3.5 on RTX 3090";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        # llama.cpp launch command
        ExecStart = ''
          ${pkgs.llama-cpp or pkgs.writeShellScriptBin "llama-server" ''
            #!/bin/bash
            cd /var/lib/llama-cpp/models
            if [ ! -f "${cfg.model}" ]; then
              echo "Downloading model: ${cfg.model}"
              hf download unsloth/${cfg.model} \
                --local-dir /var/lib/llama-cpp/models \
                --include "*.gguf" || true
            fi

            exec ${pkgs.llama-cpp or pkgs.writeShellScriptBin "llama-server" "/var/lib/llama-cpp/models/${cfg.model}" \
              --host ${cfg.host} \
              --port ${toString cfg.port} \
              --ctx-size ${toString cfg.contextSize} \
              --threads ${toString cfg.threads} \
              ${lib.concatStringsSep " " " cfg.args}
          '';

        Restart = "on-failure";
        RestartSec = "10s";
        Environment = "CUDA_VISIBLE_DEVICES=${cfg.gpuDevice}";
        User = "root";
      };
    };

    # Health check script
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellScriptBin "llama-health" ''
        #!/bin/bash
        curl -s http://${cfg.host}:${toString cfg.port}/v1/models | jq .
      '')
    ];

    # Model info documentation
    system.activationScripts.llama-cpp-model-info = ''
      echo "=== llama.cpp Model Configuration ==="
      echo "Model: ${cfg.model}"
      echo "Host: ${cfg.host}:${toString cfg.port}"
      echo "GPU Device: CUDA_VISIBLE_DEVICES=${cfg.gpuDevice}"
      echo "Max Context: ${toString cfg.maxModelLen} tokens"
      echo "Context Size: ${toString cfg.contextSize} tokens"
      echo "Threads: ${toString cfg.threads}"
      echo "GPU Layers: ${toString cfg.threads}" # All layers offloaded to GPU
      echo ""
      echo "=== Performance Comparison ==="
      echo "Unsloth GGUF (C++): ~40-60 tokens/s on RTX 3090 (10x faster than SGLang!)"
      echo "SGLang (Python): ~30-50 tokens/s (stable, production-ready)"
      echo "vLLM (C++): ~50-70 tokens/s (fastest, requires nightly builds)"
      echo ""
      echo "=== Unsloth Models for RTX 3090 (24GB VRAM) ==="
      echo "  Qwen/Qwen3.5-35B-A3B (BF16): 22GB - needs >24GB"
      echo "  unsloth/Qwen3.5-35B-A3B-GGUF: 22GB - fits perfectly!"
      echo "  unsloth/Qwen3.5-35B-A3B-FP8: 18GB model + 6GB cache"
      echo "  Qwen/Qwen3.5-27B (BF16): 16GB - fits on RTX 3060 Ti"
      echo "  Qwen/Qwen3.5-9B-Instruct: 7GB - fits on RTX 3060 Ti"
      echo ""
      echo "=== Recommended Usage ==="
      echo "1. Start with Unsloth GGUF (fastest)"
      echo "2. Compare with SGLang if you need more features"
      echo "3. Test vLLM nightly if you want maximum speed"
    '';
  };
}
