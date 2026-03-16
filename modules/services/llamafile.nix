# Llamafile Service Module
# Provides a standalone LLM fallback using Mozilla llamafile
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

  # Llamafile binary from GitHub releases
  llamafilePackage = pkgs.stdenv.mkDerivation {
    pname = "llamafile";
    version = "0.8.17";
    src = pkgs.fetchurl {
      url = "https://github.com/Mozilla-Ocho/llamafile/releases/download/0.8.17/llamafile-0.8.17";
      hash = "sha256-1R3jFM7V9FQmW6qBzLQY9vqJ8K9nG3pHh3QYvP4wR6k=";
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/llamafile
      chmod +x $out/bin/llamafile
    '';
  };
in {
  options.services.llamafile = {
    enable = mkEnableOption "llamafile - standalone LLM service using Mozilla llamafile";

    # Model configuration
    modelPath = mkOption {
      type = types.path;
      default = /home/j_kro/.lmstudio/models/mradermacher/Qwen3.5-9B-Unredacted-MAX-i1-GGUF/Qwen3.5-9B-Unredacted-MAX.i1-Q4_K_S.gguf;
      description = "Path to the GGUF model file";
    };

    modelName = mkOption {
      type = types.str;
      default = "qwen3.5-9b-unredacted";
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
      type = types.nullOr (types.enum ["nvidia" "amd"]);
      default = null;
      description = "GPU type (null = auto-detect, nvidia, or amd)";
    };

    ctxSize = mkOption {
      type = types.int;
      default = 8192;
      description = "Context window size in tokens";
    };

    threads = mkOption {
      type = types.int;
      default = 8;
      description = "Number of CPU threads for inference";
    };

    # User configuration
    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User to run llamafile as";
    };

    # Integration with AI gateway
    gatewayFallback = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Register as fallback backend with AI gateway";
      };

      priority = mkOption {
        type = types.int;
        default = 100;  # Lower priority = tried last
        description = "Fallback priority (higher = tried earlier)";
      };
    };

    # Performance tuning
    batchSize = mkOption {
      type = types.int;
      default = 512;
      description = "Batch size for prompt processing";
    };

    ubatchSize = mkOption {
      type = types.int;
      default = 512;
      description = "User batch size (logical batch size)";
    };

    # Mirostat sampling (optional)
    mirostat = mkOption {
      type = types.nullOr (types.enum [1 2]);
      default = 2;
      description = "Mirostat sampling (1 or 2, null = disabled)";
    };
  };

  config = mkIf cfg.enable {
    # Systemd service
    systemd.services.llamafile = {
      description = "Mozilla Llamafile LLM Service";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      # Build GPU-specific flags
      serviceConfig = let
        gpuFlags = lib.optionalString (cfg.gpu != null) "--gpu ${cfg.gpu}";
        mirostatFlag = lib.optionalString (cfg.mirostat != null) "--mirostat ${toString cfg.mirostat}";
      in {
        Type = "simple";
        User = cfg.user;
        Group = "users";

        # Working directory for the model
        WorkingDirectory = "/home/${cfg.user}";

        # ExecStart with all the flags
        ExecStart = ''
          ${llamafilePackage}/bin/llamafile \
            --server \
            --v2 \
            -m ${cfg.modelPath} \
            --host ${cfg.host} \
            --port ${toString cfg.port} \
            -ngl ${toString cfg.gpuLayers} \
            -c ${toString cfg.ctxSize} \
            -t ${toString cfg.threads} \
            --batch-size ${toString cfg.batchSize} \
            --ubatch-size ${toString cfg.ubatchSize} \
            ${gpuFlags} \
            ${mirostatFlag}
        '';

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

        # Watchdog
        WatchdogSec = "60s";
      };
    };

    # Open firewall for the service
    networking.firewall.allowedTCPPorts = [cfg.port];

    # Environment variables for llamafile
    environment.sessionVariables = {
      LLAMAFILE_URL = "http://${cfg.host}:${toString cfg.port}/v1";
      LLAMAFILE_MODEL = cfg.modelName;
    };

    # Convenience script for testing
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
          systemctl status llamafile
          exit 1
        fi

        echo ""
        echo "Testing API..."
        curl -s "$LLAMAFILE_URL/chat/completions" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer no-key" \
          -d '{
            "model": "LLaMA_CPP",
            "messages": [{"role": "user", "content": "Say hi in 3 words"}],
            "max_tokens": 10
          }' | ${pkgs.jq}/bin/jq -r '.choices[0].message.content'
        echo ""
        echo "✓ Test complete"
      '')

      (pkgs.writeShellScriptBin "llamafile-chat" ''
        #!/bin/bash
        if [ -n "''${1:-}" ]; then
          curl -s "$LLAMAFILE_URL/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer no-key" \
            -d "''$(jq -n --arg prompt "$*" '{"model":"LLaMA_CPP","messages":[{"role":"user","content":$prompt}],"max_tokens":500}')" \
            | ${pkgs.jq}/bin/jq -r '.choices[0].message.content'
        else
          echo "Usage: llamafile-chat 'your prompt here'"
          echo "Example: llamafile-chat 'Explain quantum computing in simple terms'"
        fi
      '')
    ];

    # Integration with AI gateway (if enabled)
    services.ai-inference.gateway = lib.mkIf cfg.gatewayFallback.enable {
      # Add llamafile as a fallback backend
      routing.fallbackChain = lib.mkAfter ["llamafile"];
    };
  };
}
