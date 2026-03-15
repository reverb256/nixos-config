# AI Inference Gateway v2 - Advanced Router with Failover, Security, and Reranking
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ai-inference;
  inherit (lib) mkIf;

  # Python environment with gateway dependencies (including RAG)
  gatewayPython = pkgs.python3.withPackages (ps: [
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
  ]);

  # Gateway main.py v2

  # Gateway __init__.py

  # Gateway package directory (OLD - monolithic)
  # Kept for rollback if needed

  # Modular gateway package (NEW - with middleware pipeline architecture)
  # Production-ready with rate limiting, circuit breaker, security, observability
  # Now using OpenAI SDK for better backend communication
  modularGatewayPkg = let
    gatewaySrc = ./ai_inference_gateway;
  in
    pkgs.runCommand "ai-inference-gateway-modular-pkg-v5"
    {
      preferLocalBuild = true;
      passAsFile = ["buildScript"];
      buildScript = ''
        mkdir -p $out/ai_inference_gateway
        # Copy the entire modular gateway package
        cp -r ${gatewaySrc}/. $out/ai_inference_gateway/
        # Fix permissions
        chmod -R u+w $out/ai_inference_gateway
        # Remove compiled Python files
        find $out -name "*.pyc" -delete
        find $out -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
      '';
    }
    ''
      . $buildScriptPath
    '';

  # Use modular gateway by default (set to false to use old monolithic version)
  gatewayPkg = modularGatewayPkg;
in {
  config = mkIf (cfg.enable && cfg.gateway.enable) {
    systemd.services.ai-inference-gateway = {
      description = "AI Inference API Gateway v2";
      after = [
        "network.target"
        "network-online.target"
      ];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      environment = {
        PATH = lib.mkForce "/run/current-system/sw/bin:/run/current-system/sw/sbin:${config.system.path}";
        npm_config_cache = "/var/cache/ai-inference/npm";
        BACKEND_URL = cfg.backend.url;
        BACKEND_TYPE = cfg.backend.type;
        BACKEND_FALLBACK_URLS = lib.strings.concatMapStringsSep "," (url: url) (
          lib.optional cfg.backend.zai.enable cfg.backend.zai.baseUrl
        );
        GATEWAY_HOST = cfg.gateway.host;
        PORT = toString cfg.gateway.port;
        AUTH_MODE = cfg.auth.mode;
        LM_STUDIO_API_KEY =
          if cfg.backend.lmStudio.apiKeyFile != null
          then "" # Will be loaded from file by gateway
          else cfg.backend.lmStudio.apiKey;
        LM_STUDIO_API_KEY_FILE =
          lib.optionalString (
            cfg.backend.lmStudio.apiKeyFile != null
          )
          cfg.backend.lmStudio.apiKeyFile;
        # ZAI backend configuration
        ZAI_API_KEY =
          if cfg.backend.zai.apiKeyFile != null
          then "" # Will be loaded from file by gateway
          else cfg.backend.zai.apiKey;
        ZAI_API_KEY_FILE =
          lib.optionalString (
            cfg.backend.zai.apiKeyFile != null
          )
          cfg.backend.zai.apiKeyFile;
        ZAI_BASE_URL = cfg.backend.zai.baseUrl;
        ZAI_MODELS = lib.generators.toJSON {} cfg.backend.zai.models;
        PYTHONUNBUFFERED = "1";
        ROUTING_ENABLED = lib.boolToString cfg.routing.enable;
        DEFAULT_MODEL = cfg.routing.defaultModel;
        RATE_LIMIT_ENABLED = lib.boolToString cfg.rateLimit.enable;
        RATE_LIMIT_RPM = toString cfg.rateLimit.requestsPerMinute;
        MAX_REQUEST_SIZE = toString cfg.security.maxRequestSize;
        SECURITY_PROXY_ENABLED = lib.boolToString cfg.security.enableProxy;
        MCP_ENABLED = lib.boolToString cfg.mcp.enable;
        MCP_SERVERS = builtins.toJSON cfg.mcp.servers;
        # RAG configuration
        RAG_ENABLED = lib.boolToString cfg.rag.enable;
        QDRANT_URL = cfg.rag.qdrantUrl;
        EMBEDDING_MODEL = cfg.rag.embeddingModel;
        CHUNK_SIZE = toString cfg.rag.chunkSize;
        CHUNK_OVERLAP = toString cfg.rag.chunkOverlap;
        RAG_TOP_K = toString cfg.rag.topK;
        HYBRID_SEARCH_ENABLED = lib.boolToString cfg.rag.hybridSearch.enable;
        VECTOR_WEIGHT = builtins.toString cfg.rag.hybridSearch.vectorWeight;
        BM25_WEIGHT = builtins.toString cfg.rag.hybridSearch.bm25Weight;
        AUTO_RAG_ENABLED = lib.boolToString cfg.rag.autoRag.enable;
        TOKEN_SCOPED_COLLECTIONS = lib.boolToString cfg.rag.tokenScopedCollections;
        # Reranker configuration
        RERANKER_ENABLED = lib.boolToString cfg.rag.reranker.enable;
        RERANKER_MODEL = cfg.rag.reranker.model;
        # Cache directories for sentence-transformers
        TRANSFORMERS_CACHE = "/var/cache/ai-inference";
        HF_HOME = "/var/cache/ai-inference";
        # Sentry error tracking
        SENTRY_ENABLED = lib.boolToString cfg.sentry.enable;
        SENTRY_DSN =
          if cfg.sentry.dsnFile != null
          then "" # Will be loaded from file by gateway
          else cfg.sentry.dsn or "";
        SENTRY_DSN_FILE =
          lib.optionalString (cfg.sentry.dsnFile != null) cfg.sentry.dsnFile;
        SENTRY_ENVIRONMENT = cfg.sentry.environment;
        SENTRY_TRACES_SAMPLE_RATE = builtins.toString cfg.sentry.tracesSampleRate;
      };

      serviceConfig = {
        ExecStart = "${gatewayPython}/bin/uvicorn ai_inference_gateway.main:app --host ${cfg.gateway.host} --port ${toString cfg.gateway.port} --workers ${toString cfg.gateway.workers} --log-level debug --app-dir ${gatewayPkg}";
        ExecReload = "/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = "10s";
        User = "ai-inference";
        Group = "ai-inference";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths =
          [
            "/tmp"
            "/var/cache/ai-inference"
            "/run/gpu-scheduler"
          ]
          ++ lib.optional (cfg.backend.lmStudio.apiKeyFile != null) (dirOf cfg.backend.lmStudio.apiKeyFile)
          ++ lib.optional (cfg.backend.zai.apiKeyFile != null) (dirOf cfg.backend.zai.apiKeyFile)
          ++ lib.optional cfg.mcp.enable (dirOf "/run/agenix/zai-api-key")
          ++ lib.optional cfg.mcp.enable (dirOf "/run/agenix/context7-api-key")
          ++ lib.optional (lib.hasAttr "sentry" cfg && lib.hasAttr "dsnFile" cfg.sentry && cfg.sentry.dsnFile != null) (dirOf cfg.sentry.dsnFile);
        # Memory limits with OOM protection
        MemoryMax = "2G";
        MemoryHigh = "1.5G"; # Start soft limiting at 1.5GB
        OOMScoreAdjust = -400; # Protect from OOM killer (negative = protected)
        CPUWeight = 100;
        IOWeight = 100;
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "ai-gateway";
      };
    };

    users.users.ai-inference = {
      isSystemUser = true;
      group = "ai-inference";
      description = "AI Inference Gateway";
    };
    users.groups.ai-inference = {};

    # Create cache directory and GPU scheduler communication directory
    systemd.tmpfiles.rules = [
      "d /var/cache/ai-inference 0755 ai-inference ai-inference - -"
      "d /run/gpu-scheduler 0755 ai-inference ai-inference - -"
    ];
  };
}
