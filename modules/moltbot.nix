# Molt.bot AI Agent Module
# Personal AI assistant with LOCAL ONLY inference
# Uses vLLM or LM Studio for completely local operation on RTX 3090
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.moltbot;

  # NPM wrapper for moltbot CLI - LOCAL ONLY
  moltbotWrapper = pkgs.writeShellScriptBin "moltbot" ''
    export PATH="${pkgs.nodejs_22}/bin:$PATH"
    export CLAWDBOT_NIX_MODE="1"
    export CLAWDBOT_STATE_DIR="${cfg.stateDir}"
    
    # Local inference configuration
    export CLAWDBOT_DEFAULT_PROVIDER="local"
    export OPENAI_BASE_URL="${cfg.localApiUrl}"
    export OPENAI_API_KEY="local-inference"  # Dummy key for local inference
    
    exec ${pkgs.nodejs_22}/bin/npx -y moltbot@latest "$@"
  '';

  # Moltbot gateway service script - LOCAL ONLY
  gatewayScript = pkgs.writeShellScriptBin "moltbot-gateway" ''
    export PATH="${pkgs.nodejs_22}/bin:$PATH"
    export CLAWDBOT_NIX_MODE="1"
    export CLAWDBOT_STATE_DIR="${cfg.stateDir}"
    
    # Local inference configuration
    export CLAWDBOT_DEFAULT_PROVIDER="local"
    export OPENAI_BASE_URL="${cfg.localApiUrl}"
    export OPENAI_API_KEY="local-inference"  # Dummy key for local inference
    
    exec ${pkgs.nodejs_22}/bin/npx -y moltbot@latest gateway --port ${toString cfg.port} --verbose
  '';
in {
  options.services.moltbot = {
    enable = lib.mkEnableOption "Molt.bot AI agent framework (LOCAL ONLY mode)";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.moltbot";
      description = "Directory for mutable state (conversations, config, skills)";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 18789;
      description = "Port for the Moltbot gateway WebSocket server";
    };

    localApiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:1234/v1";
      description = ''
        Local inference API endpoint URL.
        - LM Studio: http://localhost:1234/v1
        - vLLM: http://localhost:8000/v1
        - Ollama: http://localhost:11434/v1
      '';
    };

    backend = lib.mkOption {
      type = lib.types.enum ["lmstudio" "vllm" "ollama" "custom"];
      default = "lmstudio";
      description = ''
        Local inference backend to use:
        - lmstudio: LM Studio (default, easiest setup)
        - vllm: vLLM for high-performance inference
        - ollama: Ollama for easy model management
        - custom: Custom OpenAI-compatible endpoint
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "gpt-oss-20b";
      description = ''
        Model name to use. For local inference, this is often ignored
        by the backend (it uses whatever model is loaded).
        
        Recommended models for RTX 3090:
        - gpt-oss-20b (~5GB, fast, good for coding)
        - GLM-4.7-flash (~12GB, balanced performance)
        - qwen2.5-72b (~18GB, best quality)
        - llama-3.1-70b (~18GB, best quality)
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to run Moltbot services as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group to run Moltbot services as";
    };

    enableGateway = lib.mkEnableOption "Moltbot gateway systemd service" // {
      default = true;
    };

    enableLocalLLM = lib.mkEnableOption "Local LLM inference service (vLLM)" // {
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    # Install moltbot CLI wrapper
    environment.systemPackages = [moltbotWrapper gatewayScript];

    # Enable nix-ld for dynamically linked executables
    programs.nix-ld.enable = lib.mkDefault true;

    # Create state directory
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/config 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/skills 0750 ${cfg.user} ${cfg.group} -"
    ];

    # Moltbot gateway systemd service
    systemd.services.moltbot-gateway = lib.mkIf cfg.enableGateway {
      description = "Molt.bot AI Agent Gateway (Local Inference)";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${gatewayScript}/bin/moltbot-gateway";
        ExecStop = "${pkgs.coreutils}/bin/pkill -f 'moltbot gateway'";
        Restart = "always";
        RestartSec = "10s";
        
        # Security hardening
        NoNewPrivileges = false;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = false;
        ReadWritePaths = [cfg.stateDir];
        
        # Resource limits
        MemoryMax = "4G";
        CPUQuota = "200%";
        
        # Environment
        Environment = [
          "CLAWDBOT_NIX_MODE=1"
          "CLAWDBOT_STATE_DIR=${cfg.stateDir}"
          "NODE_ENV=production"
          "CLAWDBOT_DEFAULT_PROVIDER=local"
          "OPENAI_BASE_URL=${cfg.localApiUrl}"
          "OPENAI_API_KEY=local-inference"
        ];
      };

      environment = {
        PATH = lib.makeBinPath [pkgs.nodejs_22 pkgs.coreutils];
      };
    };

    # Optional: vLLM local inference service
    systemd.services.vllm-server = lib.mkIf cfg.enableLocalLLM {
      description = "vLLM Local Inference Server";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${pkgs.python3}/bin/python3 -m vllm.entrypoints.openai.api_server --model ${cfg.model} --tensor-parallel-size 1 --gpu-memory-utilization 0.9 --port 8000";
        Restart = "always";
        RestartSec = "30s";
        
        # GPU access
        PrivateDevices = false;
        
        # Resource limits for RTX 3090
        MemoryMax = "20G";
        
        Environment = [
          "CUDA_VISIBLE_DEVICES=0"
          "PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512"
        ];
      };

      environment = {
        PATH = lib.makeBinPath [pkgs.python3 pkgs.cudaPackages.cudatoolkit];
      };
    };

    # Firewall configuration
    networking.firewall = {
      allowedTCPPorts = [cfg.port];
    };

    # Documentation
    environment.etc."moltbot/README.md".text = ''
      # Molt.bot Configuration (LOCAL ONLY)

      Molt.bot running with COMPLETELY LOCAL inference on your RTX 3090.
      No API keys needed. No external dependencies. 100% private.

      ## Architecture

      ```
      ┌─────────────────┐     ┌──────────────────┐     ┌──────────────┐
      │  Molt.bot CLI   │────▶│  Local Inference │────▶│  RTX 3090    │
      │  (Node.js)      │     │  (LM Studio/     │     │  24GB VRAM   │
      └─────────────────┘     │   vLLM/Ollama)   │     └──────────────┘
                              └──────────────────┘
      ```

      ## Setup Instructions

      ### Option 1: LM Studio (Easiest)

      1. Download LM Studio: https://lmstudio.ai/
      2. Download a model (e.g., Qwen2.5-72B, Llama-3.1-70B, Mixtral-8x22B)
      3. Start the local server: Developer tab → Start Server
      4. Molt.bot will automatically connect to http://localhost:1234/v1

      ### Option 2: vLLM (Best Performance)

      1. Enable vLLM service in configuration:
         ```nix
         services.moltbot = {
           enable = true;
           backend = "vllm";
           localApiUrl = "http://localhost:8000/v1";
           enableLocalLLM = true;
           model = "Qwen/Qwen2.5-72B-Instruct";
         };
         ```

      2. Rebuild: `just switch`

      3. vLLM will start automatically and load the model

      ### Option 3: Ollama

      1. Install Ollama: `nix shell nixpkgs#ollama`
      2. Pull a model: `ollama pull qwen2.5:72b`
      3. Start server: `ollama serve`
      4. Set URL: `services.moltbot.localApiUrl = "http://localhost:11434/v1"`

      ## Quick Start

      ```bash
      # Start gateway
      moltbot gateway --port 18789

      # Or use systemd
      systemctl --user start moltbot-gateway

      # Send a message
      moltbot agent --message "Hello, what can you do?"

      # Interactive mode
      moltbot onboard
      ```

      ## Recommended Models for RTX 3090 (24GB)

      **Primary Models:**
      - **gpt-oss-20b** (~5GB, very fast, good for coding and general tasks)
      - **GLM-4.7-flash** (~12GB, balanced performance and quality)

      **Alternative High-Performance Models:**
      - **Qwen2.5-72B-Instruct** (4-bit quantized, ~18GB, best overall quality)
      - **Llama-3.1-70B-Instruct** (4-bit quantized, ~18GB, best overall quality)
      - **Mixtral-8x22B-Instruct-v0.1** (4-bit quantized, ~20GB)
      - **DeepSeek-Coder-V2-Lite-Instruct** (4-bit, ~12GB)

      ## Configuration

      Current settings:
      - Backend: ${cfg.backend}
      - API URL: ${cfg.localApiUrl}
      - Model: ${cfg.model}
      - Port: ${toString cfg.port}
      - State: ${cfg.stateDir}

      ## Troubleshooting

      ### Out of Memory
      - Use 4-bit quantization (Q4_K_M)
      - Reduce context length: `--max-model-len 4096`
      - Lower GPU memory: `--gpu-memory-utilization 0.8`

      ### Slow Responses
      - Enable FlashAttention: `--attention-backend flash_attn`
      - Use tensor parallelism (if multiple GPUs)
      - Check GPU utilization: `nvidia-smi`

      ### Connection Refused
      - Verify local inference server is running
      - Check firewall: `sudo iptables -L | grep ${toString cfg.port}`
      - Test API: `curl ${cfg.localApiUrl}/models`

      ## Documentation

      - Molt.bot: https://molt.bot
      - vLLM: https://docs.vllm.ai/
      - LM Studio: https://lmstudio.ai/docs
      - Ollama: https://github.com/ollama/ollama
    '';
  };
}
