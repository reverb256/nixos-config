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
    # LM Studio accepts any non-empty API key for local inference
    export OPENAI_API_KEY="${cfg.localApiKey}"
    
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
    # LM Studio accepts any non-empty API key for local inference
    export OPENAI_API_KEY="${cfg.localApiKey}"
    
    exec ${pkgs.nodejs_22}/bin/npx -y moltbot@latest gateway --port ${toString cfg.port} --verbose
  '';
in {
  options.services.moltbot = {
    enable = lib.mkEnableOption "Molt.bot AI agent framework (LOCAL ONLY mode)";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/moltbot";
      description = "Directory for mutable state (conversations, config, skills). Using absolute path for systemd compatibility.";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 18789;
      description = "Port for the Moltbot gateway WebSocket server";
    };

    localApiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:1234/v1";
      description = ''
        Local inference API endpoint URL.
        - LM Studio default: http://127.0.0.1:1234/v1
        - Custom servers: http://127.0.0.1:8000/v1
        Note: Using 127.0.0.1 instead of localhost for IPv4 consistency
      '';
    };

    localApiKey = lib.mkOption {
      type = lib.types.str;
      default = "lm-studio-local";
      description = ''
        API key for local inference. LM Studio accepts any non-empty string.
        This is not a real secret since inference is local-only.
      '';
    };

    backend = lib.mkOption {
      type = lib.types.enum ["lmstudio" "custom"];
      default = "lmstudio";
      description = ''
        Local inference backend to use:
        - lmstudio: LM Studio (default, easiest setup with CUDA support)
        - custom: Custom OpenAI-compatible endpoint
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "local-model";
      description = ''
        Model identifier for reference. LM Studio uses whatever model is currently loaded.
        This is primarily for documentation purposes.

        Recommended models for RTX 3090 (24GB VRAM):
        - Qwen2.5-32B-Instruct (Q4_K_M, ~16GB VRAM, excellent quality)
        - Llama-3.3-70B-Instruct (Q4_K_M, ~18GB VRAM, best overall)
        - Mixtral-8x22B-Instruct (Q4_K_M, ~20GB VRAM, MoE)
        - Qwen2.5-14B-Instruct (Q4_K_M, ~8GB VRAM, fast)

        Load model in LM Studio first, then start Molt.bot.
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
        
        # Resource limits for RTX 3090 with 24GB VRAM
        # Gateway itself uses minimal resources; LM Studio handles model inference
        MemoryMax = "8G";
        CPUQuota = "100%";
        
        # Environment
        Environment = [
          "CLAWDBOT_NIX_MODE=1"
          "CLAWDBOT_STATE_DIR=${cfg.stateDir}"
          "NODE_ENV=production"
          "CLAWDBOT_DEFAULT_PROVIDER=local"
          "OPENAI_BASE_URL=${cfg.localApiUrl}"
          "OPENAI_API_KEY=${cfg.localApiKey}"
        ];
      };

      environment = {
        PATH = lib.mkForce (lib.makeBinPath [pkgs.nodejs_22 pkgs.coreutils]);
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
      │  (Node.js)      │     │  (LM Studio)     │     │  24GB VRAM   │
      └─────────────────┘     └──────────────────┘     └──────────────┘
      ```

      ## Setup Instructions

      ### Option 1: LM Studio (Recommended)

      **Installation:**
      1. Download LM Studio: https://lmstudio.ai/
      2. Download a model (see recommended models below)
      3. Start the local server: Developer tab → Start Server
      4. Molt.bot will automatically connect to http://127.0.0.1:1234/v1

      **RTX 3090 Optimal Settings:**
      - GPU Layers: 40 (maximize GPU utilization)
      - Context Length: 4096 tokens
      - Batch Size: 512
      - Quantization: Q4_K_M for 32B models, Q5_K_M for 20B models
      - Enable "Use GPU" and disable "Low VRAM" mode

      ### Option 2: Custom OpenAI-Compatible Server

      For other CUDA-enabled inference servers (llama.cpp, TGI, etc.):
      
      1. Start your inference server on desired port
      2. Configure Molt.bot:
         ```nix
         services.moltbot = {
           enable = true;
           backend = "custom";
           localApiUrl = "http://localhost:8000/v1";
         };
         ```

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

      ## Recommended Models for RTX 3090 (24GB VRAM)

      **Optimal for Molt.bot (Q4_K_M quantization):**
      - **Qwen2.5-32B-Instruct** (~16GB VRAM, excellent quality)
      - **Llama-3.3-70B-Instruct** (~18GB VRAM, best overall)
      - **Mixtral-8x22B-Instruct** (~20GB VRAM, MoE architecture)
      - **DeepSeek-V2.5** (~16GB VRAM, great for coding)

      **Smaller/Faster Options:**
      - **Qwen2.5-14B-Instruct** (~8GB VRAM, fast responses)
      - **Llama-3.2-8B-Instruct** (~5GB VRAM, very fast)

      **LM Studio Settings:**
      - GPU Layers: 40 (maximize utilization)
      - Context: 4096 tokens
      - Quantization: Q4_K_M (best quality/performance balance)

      ## Configuration

      Current settings:
      - Backend: ${cfg.backend}
      - API URL: ${cfg.localApiUrl}
      - Model: ${cfg.model}
      - Port: ${toString cfg.port}
      - State: ${cfg.stateDir}

      ## Troubleshooting

      ### LM Studio Connection Issues
      - Verify server is running: `curl http://127.0.0.1:1234/v1/models`
      - Check LM Studio Developer tab → Server is started
      - Ensure port 1234 is not blocked by firewall
      - Try restarting LM Studio if VRAM is stuck

      ### Out of Memory (OOM)
      - Reduce GPU layers in LM Studio (try 35 instead of 40)
      - Use Q4_K_M quantization instead of Q5_K_M
      - Reduce context length to 2048 tokens
      - Close other GPU applications
      - Monitor VRAM: `nvidia-smi` (should stay under 23GB)

      ### Slow Responses
      - Increase batch size in LM Studio (512-1024)
      - Ensure model is fully loaded on GPU (check GPU layers)
      - Disable "Low VRAM" mode in LM Studio
      - Check GPU utilization: `nvidia-smi dmon`
      - Consider using a smaller model (14B instead of 32B)

      ### CUDA/GPU Issues
      - Verify NVIDIA drivers: `nvidia-smi`
      - Check CUDA version: `nvcc --version`
      - Ensure LM Studio detects GPU in settings
      - Update to latest NVIDIA drivers (570+ recommended)

      ## Documentation

      - Molt.bot: https://molt.bot
      - LM Studio: https://lmstudio.ai/docs
      - LM Studio Discord: https://discord.gg/aPQY5s6un4
      - CUDA on NixOS: https://nixos.wiki/wiki/CUDA
    '';
  };
}
