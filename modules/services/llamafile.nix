{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.llamafile;
  inherit
    (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;

  useCuda = config.hardware.gpu-compute.cuda.enable or false;
  useRocm = config.hardware.gpu-compute.rocm.enable or false;

  llamaPkg =
    if cfg.vulkanDevice != null
    then pkgs.llama-cpp-vulkan
    else if cfg.gpu == "amd" || cfg.gpu == "rocm"
    then pkgs.llama-cpp-rocm
    else if cfg.gpu == "nvidia"
    then pkgs.llama-cpp
    else if cfg.gpu == null && useRocm
    then pkgs.llama-cpp-rocm
    else if cfg.gpu == null && useCuda
    then pkgs.llama-cpp
    else pkgs.llama-cpp;
in {
  options.services.llamafile = {
    enable = mkEnableOption "llamafile - standalone LLM service using llama.cpp";

    modelPath = mkOption {
      type = types.str;
      default = "/home/j_kro/.lmstudio/models/mradermacher/Qwen3.5-4B-Unredacted-MAX-i1-GGUF/Qwen3.5-4B-Unredacted-MAX.i1-Q4_K_S.gguf";
      description = "Path to the GGUF model file";
    };

    modelName = mkOption {
      type = types.str;
      default = "qwen3.5-4b-unredacted";
      description = "Model name for API responses";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Listen address (use 0.0.0.0 for cluster access)";
    };

    port = mkOption {
      type = types.port;
      default = 8081;
      description = "Listen port for llamafile API server";
    };

    gpuLayers = mkOption {
      type = types.int;
      default = 999;
      description = "Number of layers to offload to GPU (999 = all)";
    };

    gpu = mkOption {
      type = types.nullOr (types.enum ["nvidia" "amd" "rocm"]);
      default = null;
      description = "GPU type (null = auto-detect, nvidia, or amdgpu/rocm)";
    };

    ctxSize = mkOption {
      type = types.int;
      default = 32768;
      description = "Context window size in tokens (32768 for Qwen3.5)";
    };

    threads = mkOption {
      type = types.int;
      default = 12;
      description = "Number of CPU threads for inference";
    };

    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User to run llamafile as";
    };

    batchSize = mkOption {
      type = types.int;
      default = 64;
      description = "Batch size for prompt processing (64 for low TTFT on Qwen3.5)";
    };

    ubatchSize = mkOption {
      type = types.int;
      default = 16;
      description = "User batch size (16 for optimal Qwen3.5 performance)";
    };

    flashAttention = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Flash Attention (Qwen3.5 benefits significantly)";
    };

    parallelDecoding = mkOption {
      type = types.int;
      default = 1;
      description = "Parallel decoding slots crash GGML_SCHED_MAX_SPLIT_INPUTS on multi-GPU";
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

    chatTemplate = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Jinja2 chat template (e.g. '<start_of_turn>user\\n{{prompt}}<end_of_turn>\\n<start_of_turn>model\\n'). Auto-detected from GGUF metadata when null.";
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

    mmprojPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to multimodal projector GGUF file (mmproj) for vision/audio support";
    };

    gpuDevice = mkOption {
      type = types.int;
      default = 0;
      description = "CUDA/ROCm device index (use nvidia-smi ordering, not CUDA enumeration)";
    };

    vulkanDevice = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Vulkan device name (e.g. 'Vulkan1', 'Vulkan2'). Overrides --gpu-device for Vulkan backends.";
    };

    cacheRam = mkOption {
      type = types.int;
      default = 0;
      description = "Prompt cache size in MB (0 = disable, use GPU only to save system RAM)";
    };

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
    systemd.services.llamafile = let
      gpuLayersFlag = "-ngl ${toString cfg.gpuLayers}";
      # Write chat template to store to avoid ExecStart multi-line quoting issues
      chatTemplateFile = pkgs.writeText "llamafile-chat-template.txt" cfg.chatTemplate;
    in {
      description = "Llama.cpp LLM Service";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";

        WorkingDirectory = "/home/${cfg.user}";

        ExecStart = ''
          ${llamaPkg}/bin/llama-server \
            --model ${cfg.modelPath} \
            ${lib.optionalString (cfg.mmprojPath != null) "--mmproj ${cfg.mmprojPath}"} \
            --host ${cfg.host} \
            --port ${toString cfg.port} \
            ${gpuLayersFlag} \
            -c ${toString cfg.ctxSize} \
            -t ${toString cfg.threads} \
            --batch-size ${toString cfg.batchSize} \
            --ubatch-size ${toString cfg.ubatchSize} \
            ${lib.optionalString cfg.flashAttention "--flash-attn on"} \
            ${lib.optionalString (cfg.parallelDecoding > 0) "--parallel ${toString cfg.parallelDecoding}"} \
            ${lib.optionalString (cfg.chatTemplate != null) "--chat-template '${builtins.replaceStrings ["\n"] ["\\n"] cfg.chatTemplate}'"} \
            ${lib.optionalString (cfg.vulkanDevice != null) "--device ${cfg.vulkanDevice}"} \
            --chat-template-kwargs '${builtins.toJSON { enable_thinking = cfg.enableThinking; }}' \
            --reasoning-budget ${toString cfg.reasoningBudget} \
            --cache-type-k ${cfg.cacheTypeK} \
            --cache-type-v ${cfg.cacheTypeV} \
            --cache-ram ${toString cfg.cacheRam} \
            --temp ${lib.strings.floatToString cfg.temperature} \
            --top-k ${toString cfg.topK} \
            --top-p ${lib.strings.floatToString cfg.topP} \
            --min-p ${lib.strings.floatToString cfg.minP} \
            --metrics
        '';

        Environment = [
          "LD_LIBRARY_PATH=${llamaPkg}/lib"
        ] ++ lib.optional (cfg.vulkanDevice == null) "CUDA_VISIBLE_DEVICES=${toString cfg.gpuDevice}";

        NoNewPrivileges = true;
        PrivateTmp = true;

        LimitNOFILE = 65536;

        Restart = "on-failure";
        RestartSec = "10s";

        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];

    environment.sessionVariables = {
      LLAMAFILE_URL = "http://${cfg.host}:${toString cfg.port}";
      LLAMAFILE_MODEL = cfg.modelName;
    };

    environment.systemPackages = with pkgs; [
      (pkgs.writeShellScriptBin "llamafile-test" ''
        #!/bin/bash
        set -euo pipefail
        echo "=== Llamafile Test ==="
        echo "URL: $LLAMAFILE_URL"
        echo "Model: $LLAMAFILE_MODEL"
        echo ""

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
  };
}
