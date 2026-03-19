# Llamafile Service Module
# Provides a standalone LLM fallback using llama.cpp (llama-server)
# Runs a single GGUF model as an OpenAI-compatible API service
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.llamafile;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    literalExpression
    optional
    optionalString
    ;

  # Auto-detect GPU backend from gpu-compute module or use explicit setting
  hasGpuCompute = config.hardware.gpu-compute.enable or false;
  useCuda = config.hardware.gpu-compute.cuda.enable or false;
  useRocm = config.hardware.gpu-compute.rocm.enable or false;
  useVulkan = config.hardware.gpu-compute.vulkan.enable or false;

  # Select llama-cpp variant (prefer explicit GPU setting, then auto-detect)
  llamaPkg = if cfg.gpu == "amd" || cfg.gpu == "rocm" then pkgs.llama-cpp-rocm
             else if cfg.gpu == "nvidia" then pkgs.llama-cpp # CUDA for NVIDIA (Flash Attention support)
             else if cfg.gpu == null && useRocm then pkgs.llama-cpp-rocm
             else if cfg.gpu == null && useCuda then pkgs.llama-cpp
             else pkgs.llama-cpp;
in {
  options.services.llamafile = {
    enable = mkEnableOption "llamafile - standalone LLM service using llama.cpp";

    # Model configuration
    modelPath = mkOption {
      type = types.path;
      default = /home/j_kro/.lmstudio/models/mradermacher/Qwen3.5-4B-Unredacted-MAX-i1-GGUF/Qwen3.5-4B-Unredacted-MAX.i1-Q4_K_S.gguf;
      description = "Path to the GGUF model file";
    };

    modelName = mkOption {
      type = types.str;
      default = "qwen3.5-4b-unredacted";
      description = "Model name for API responses";
    };

    # Server configuration
    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Listen address (use 0.0.0.0 for cluster access)";
    };

    port = mkOption {
      type = types.port;
      default = 8081;  # Different from gateway's 8080
      description = "Listen port for llamafile API server";
    };

    # GPU configuration
    gpuLayers = mkOption {
      type = types.int;
      default = 999;  # Offload all possible layers to GPU
      description = "Number of layers to offload to GPU (999 = all)";
    };

    gpu = mkOption {
      type = types.nullOr (types.enum ["nvidia" "amd" "rocm"]);
      default = null;
      description = "GPU type (null = auto-detect, nvidia, or amdgpu/rocm)";
    };

    ctxSize = mkOption {
      type = types.int;
      default = 32768;  # Qwen3.5 supports up to 262K native
      description = "Context window size in tokens (32768 for Qwen3.5)";
    };

    threads = mkOption {
      type = types.int;
      default = 12;  # Better thread utilization for Qwen3.5
      description = "Number of CPU threads for inference";
    };

    # User configuration
    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User to run llamafile as";
    };

    # Performance tuning (Qwen3.5-optimized defaults)
    batchSize = mkOption {
      type = types.int;
      default = 64;  # Lower latency for Qwen3.5
      description = "Batch size for prompt processing (64 for low TTFT on Qwen3.5)";
    };

    ubatchSize = mkOption {
      type = types.int;
      default = 16;  # Better micro-batch for Qwen3.5
      description = "User batch size (16 for optimal Qwen3.5 performance)";
    };

    # Qwen3.5-specific optimizations
    flashAttention = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Flash Attention (Qwen3.5 benefits significantly)";
    };

    parallelDecoding = mkOption {
      type = types.int;
      default = 3;
      description = "Parallel decoding slots for Qwen3.5";
    };

    enableThinking = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Qwen3.5 thinking mode (chain-of-thought with <think> tags)";
    };

    reasoningBudget = mkOption {
      type = types.int;
      default = 0;
      description = "Reasoning budget in tokens (0 = disable reasoning mode entirely)";
    };

    cacheTypeK = mkOption {
      type = types.str;
      default = "bf16";
      description = "KV cache type for keys (bf16 recommended for Qwen3.5 to fix garbled output)";
    };

    cacheTypeV = mkOption {
      type = types.str;
      default = "bf16";
      description = "KV cache type for values (bf16 recommended for Qwen3.5 to fix garbled output)";
    };

    # Sampling parameters
    temperature = mkOption {
      type = types.float;
      default = 0.7;
      description = "Sampling temperature";
    };

    topK = mkOption {
      type = types.int;
      default = 40;
      description = "Top-k sampling";
    };

    topP = mkOption {
      type = types.float;
      default = 0.9;
      description = "Top-p sampling";
    };

    minP = mkOption {
      type = types.float;
      default = 0.05;
      description = "Min-p sampling";
    };
  };

  config = mkIf cfg.enable {
    # Systemd service
    systemd.services.llamafile = {
      description = "Llama.cpp LLM Service";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      # Build GPU-specific flags for llama-server
      serviceConfig = let
        # llama-server uses different flag names than llamafile
        gpuLayersFlag = "-ngl ${toString cfg.gpuLayers}";
        gpuFlag = optionalString (cfg.gpu != null) (
          if cfg.gpu == "nvidia" then "-ngl ${toString cfg.gpuLayers}" # CUDA is default
          else if cfg.gpu == "amd" || cfg.gpu == "rocm" then "--gpu-layers ${toString cfg.gpuLayers} --rocm"
          else ""
        );
      in {
        Type = "simple";
        User = cfg.user;
        Group = "users";

        # Working directory for the model
        WorkingDirectory = "/home/${cfg.user}";

        # ExecStart with Qwen3.5-optimized llama-server flags
        ExecStart = ''
          ${llamaPkg}/bin/llama-server \
            --model ${cfg.modelPath} \
            --host ${cfg.host} \
            --port ${toString cfg.port} \
            ${gpuLayersFlag} \
            -c ${toString cfg.ctxSize} \
            -t ${toString cfg.threads} \
            --batch-size ${toString cfg.batchSize} \
            --ubatch-size ${toString cfg.ubatchSize} \
            ${lib.optionalString cfg.flashAttention "--flash-attn on"} \
            ${lib.optionalString (cfg.parallelDecoding > 0) "--parallel ${toString cfg.parallelDecoding}"} \
            --chat-template-kwargs '{\"enable_thinking\":${if cfg.enableThinking then "true" else "false"}}' \
            --reasoning-budget ${toString cfg.reasoningBudget} \
            --cache-type-k ${cfg.cacheTypeK} \
            --cache-type-v ${cfg.cacheTypeV} \
            --temp ${lib.strings.floatToString cfg.temperature} \
            --top-k ${toString cfg.topK} \
            --top-p ${lib.strings.floatToString cfg.topP} \
            --min-p ${lib.strings.floatToString cfg.minP} \
            --metrics
        '';

        # Environment to prioritize bundled libraries
        # Force use of GPU 0 (RTX 3060 Ti) to avoid conflict with mining on GPU 1 (RTX 3090)
        Environment = "LD_LIBRARY_PATH=${llamaPkg}/lib:CUDA_VISIBLE_DEVICES=0";

        # Security settings
        NoNewPrivileges = false;  # Needed for GPU access
        PrivateTmp = true;

        # Resource limits
        LimitNOFILE = 65536;

        # Restart policy
        Restart = "on-failure";
        RestartSec = "10s";

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";

        # Watchdog disabled - llama-server doesn't implement sd_notify() heartbeat
        # When idle, all threads wait in pthread_cond_wait, triggering false timeouts
        # WatchdogSec = "60s";  # BUG: Causes SIGABRT on idle after 60 seconds
      };
    };

    # Open firewall for the service
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];

    # Environment variables for llamafile
    environment.sessionVariables = {
      LLAMAFILE_URL = "http://${cfg.host}:${toString cfg.port}";
      LLAMAFILE_MODEL = cfg.modelName;
    };

    # Convenience scripts
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellScriptBin "llamafile-test" ''
        #!/bin/bash
        set -euo pipefail
        echo "=== Llamafile Test ==="
        echo "URL: $LLAMAFILE_URL"
        echo "Model: $LLAMAFILE_MODEL"
        echo ""

        # Check service status
        if systemctl is-active --quiet llamafile; then
          echo "✓ Service is running"
        else
          echo "✗ Service is not running"
          systemctl status llamafile --no-pager
          exit 1
        fi

        echo ""
        echo "Testing API..."
        curl -s "$LLAMAFILE_URL/v1/chat/completions" \
          -H "Content-Type: application/json" \
          -d '{
            "model": "gguf",
            "messages": [{"role": "user", "content": "Say hi in 3 words"}],
            "max_tokens": 10
          }' | ${jq}/bin/jq -r '.choices[0].message.content // .error // "No response"'
        echo ""
        echo "✓ Test complete"
      '')

      (pkgs.writeShellScriptBin "llamafile-chat" ''
        #!/bin/bash
        if [ -n "''${1:-}" ]; then
          curl -s "$LLAMAFILE_URL/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "''$(jq -n --arg prompt "$*" '{"model":"gguf","messages":[{"role":"user","content":$prompt}],"max_tokens":500}')" \
            | ${jq}/bin/jq -r '.choices[0].message.content // .error'
        else
          echo "Usage: llamafile-chat 'your prompt here'"
          echo "Example: llamafile-chat 'Explain quantum computing in simple terms'"
        fi
      '')
    ];

    # Note: To integrate with AI gateway as fallback, add to gateway config:
    # services.ai-inference.routing.fallbackChain = [ "lm-studio" "llamafile" "zai" ];
  };
}
