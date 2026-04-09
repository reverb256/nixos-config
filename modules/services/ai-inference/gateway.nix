# AI Inference Gateway v2 - Advanced Router with Failover, Security, and Reranking
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ai-inference;
  inherit (lib) mkIf;

  # Gateway source directory
  gatewaySrc = ./ai_inference_gateway;

  # Qwen3-TTS: Self-hosted TTS via qwen-tts Python package (overlay)
  # Source: https://github.com/QwenLM/Qwen3-TTS
  # PyPI: https://pypi.org/project/qwen-tts/
  # Models from HuggingFace: Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice, Qwen/Qwen3-TTS-Tokenizer-12Hz
  # Pre-download: huggingface-cli download Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice --local-dir /var/cache/ai-inference/

  # Gateway package (plain files, not a Python package yet)
  # Used for --app-dir in uvicorn
  # NOTE: We use symlinkJoin with source tracking to ensure changes are detected
  modularGatewayPkgBase =
    pkgs.runCommand "ai-inference-gateway-modular-pkg-base"
      {
        preferLocalBuild = true;
        # Track source changes by including it in the name/hash
        src = gatewaySrc;
      }
      ''
        mkdir -p $out/ai_inference_gateway
        # Copy the entire modular gateway package
        cp -r ${gatewaySrc}/. $out/ai_inference_gateway/
        # Fix permissions
        chmod -R u+w $out/ai_inference_gateway
        # Remove compiled Python files
        find $out -name "*.pyc" -delete
        find $out -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
      '';

  # Gateway as a proper Python package (installable in site-packages)
  # This allows `import ai_inference_gateway` without --app-dir
  modularGatewayPkgPython =
    pkgs.runCommand "ai-inference-gateway-modular-pkg-python"
      {
        preferLocalBuild = true;
        # Track source changes by including it in the name/hash
        src = gatewaySrc;
      }
      ''
        # Create site-packages structure
        mkdir -p $out/lib/python3.13/site-packages
        # Copy gateway package to site-packages
        cp -r ${gatewaySrc}/. $out/lib/python3.13/site-packages/ai_inference_gateway
        # Fix permissions
        chmod -R u+w $out/lib/python3.13/site-packages/ai_inference_gateway
        # Remove compiled Python files
        find $out -name "*.pyc" -delete
        find $out -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
      '';

  # Python environment with gateway dependencies AND the gateway package
  # The gateway package is added as an extra package
  gatewayPython = pkgs.python3.withPackages (
    ps:
    [
      ps.fastapi
      ps.uvicorn
      ps.httpx
      ps.openai # OpenAI SDK for proper API communication
      ps.anthropic # Anthropic SDK for Claude API compatibility
      ps.prometheus-client
      ps.pyjwt
      ps.cryptography
      ps.python-multipart
      ps.uvloop
      ps.httptools
      ps.aiohttp
      ps.psutil
      ps.qdrant-client
      ps.sentence-transformers
      ps.rank-bm25
      ps.numpy
      ps.beautifulsoup4 # For RAG URL ingestion (HTML parsing)
      ps.redis
      ps.pydantic
      ps.pydantic-settings
      ps.sentry-sdk
      # MCP SDK for SearXNG MCP server integration
      ps.mcp
      # HuggingFace CLI for model downloads
      ps.huggingface-hub
      # TTS support: Qwen3-TTS (models loaded from HuggingFace)
      ps.qwen-tts
      ps.transformers
      ps.torch
      ps.torchaudio
      ps.accelerate
      ps.datasets
      # Audio processing for TTS/STT format conversion
      ps.pydub # For MP3 conversion (requires ffmpeg in systemPackages)
      ps.soundfile # For FLAC/WAV handling
      ps.librosa # Audio analysis for qwen-tts
      ps.einops # Tensor manipulation for qwen-tts
      # Vision support (Qwen3-VL via transformers)
      ps.pillow # For image processing
      ps.onnxruntime # For ONNX model support
      # SearXNG deep integration dependencies
      ps.scikit-learn # For result clustering (DBSCAN, TF-IDF)
      ps.lxml # Fast HTML parsing for ingestion
      ps.feedgen # For RSS/ATOM export generation
    ]
    ++ [ modularGatewayPkgPython ]
  );

  # Combined package: gateway source + Python environment in one
  # This allows both --app-dir usage and direct imports
  modularGatewayPkg = pkgs.symlinkJoin {
    name = "ai-inference-gateway-modular-pkg-v15"; # Bump for self-improvement system integration
    paths = [
      modularGatewayPkgBase
      gatewayPython
    ];
  };

  # Use modular gateway by default (set to false to use old monolithic version)
  gatewayPkg = modularGatewayPkg;

  # Container image for Kubernetes deployment
  # Runs as non-root user (UID 1000) for security
  gatewayContainerImage = pkgs.dockerTools.buildLayeredImage {
    name = "ai-inference-gateway";
    tag = "latest";
    # Create home dir and cache dir with correct ownership for UID 1000
    extraCommands = ''
      mkdir -p home/ai-gateway
      chown 1000:1000 home/ai-gateway
      mkdir -p var/cache/ai-inference
      chown 1000:1000 var/cache/ai-inference
      mkdir -p tmp
      chown 1000:1000 tmp
      mkdir -p run/ai-inference
      chown 1000:1000 run/ai-inference
    '';
    contents = [
      gatewayPython
      modularGatewayPkgBase
      pkgs.bash
      pkgs.coreutils
      pkgs.cacert
    ];
    config = {
      User = "1000:1000";
      Cmd = [
        "${gatewayPython}/bin/python"
        "-m"
        "uvicorn"
        "ai_inference_gateway.main:app"
        "--host"
        "0.0.0.0"
        "--port"
        "8080"
        "--workers"
        "4"
      ];
      ExposedPorts = {
        "8080/tcp" = { };
      };
      Env = [
        "PYTHONPATH=/app:${gatewayPython}/lib/python3.13/site-packages"
        "PATH=${gatewayPython}/bin:/usr/bin:/bin"
        "HOME=/home/ai-gateway"
        "USER=ai-gateway"
        "TRANSFORMERS_CACHE=/var/cache/ai-inference"
        "HF_HOME=/var/cache/ai-inference"
        "TORCHINDUCTOR_CACHE_DIR=/var/cache/ai-inference/torch-cache"
      ];
      WorkingDir = "/app";
    };
  };

  # Wrapper script for OpenCode SearXNG MCP server
  # Dynamically finds the gateway package to avoid hardcoded Nix store paths
  opencodeSearxngMcpWrapper = pkgs.writeShellApplication {
    name = "opencode-searxng-mcp";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      gnused
    ];
    text = builtins.readFile ./bin/opencode-searxng-mcp;
  };
in
{
  config = mkIf (cfg.enable && cfg.gateway.enable) {
    # Expose the gateway Python environment for use by MCP servers
    services.ai-inference.gateway.python = gatewayPython;

    # Install the OpenCode MCP wrapper script to system path
    environment.systemPackages = [ opencodeSearxngMcpWrapper ];

    # Gateway runs in Kubernetes, not as systemd service
    # See: kubernetes-manifests/ai-inference/gateway-deployment.yaml
  };
}
# force rebuild 4 1773547685
