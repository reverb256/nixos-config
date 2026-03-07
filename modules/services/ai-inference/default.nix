# AI Inference Service - Main Module
# Integrates with existing LM Studio installation
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ai-inference;
  inherit
    (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    literalExpression
    ;

  # Python package for the gateway (with RAG dependencies)
  gatewayEnv = pkgs.python3.withPackages (ps: [
    ps.fastapi
    ps.uvicorn
    ps.httpx
    ps.prometheus-client
    ps.pyjwt
    ps.cryptography
    ps.python-multipart
    ps.uvloop
    ps.httptools
    ps.qdrant-client
    ps.sentence-transformers
    ps.rank-bm25
    ps.numpy
  ]);
in {
  options.services.ai-inference = {
    enable = mkEnableOption "AI Inference Service (integrates with LM Studio)";

    # Python package for the gateway
    package = mkOption {
      type = types.package;
      default = gatewayEnv;
      description = "Python environment with gateway dependencies";
      readOnly = true;
    };

    # Backend configuration
    backend = {
      url = mkOption {
        type = types.str;
        default = "http://127.0.0.1:1234";
        description = "Backend API URL (LM Studio, vLLM, Ollama, or ZAI)";
      };

      type = mkOption {
        type = types.enum [
          "lm-studio"
          "vllm"
          "llama-cpp"
          "sglang"
          "zai"
        ];
        default = "lm-studio";
        description = "Backend inference engine type";
      };

      # LM Studio specific configuration
      lmStudio = {
        apiKey = mkOption {
          type = types.str;
          default = "";
          description = "LM Studio API token (obtained from LM Studio settings)";
        };

        apiKeyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = literalExpression "/run/agenix/lm-studio-api-key";
          description = "Path to file containing LM Studio API token (takes precedence over apiKey)";
        };
      };

      # ZAI-specific configuration
      zai = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable ZAI coding plan endpoint";
        };

        apiKey = mkOption {
          type = types.str;
          default = "";
          description = "ZAI API key for coding plan";
        };

        apiKeyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = literalExpression "/run/agenix/zai-api-key";
          description = "Path to file containing ZAI API key (takes precedence over apiKey)";
        };

        baseUrl = mkOption {
          type = types.str;
          default = "https://api.z.ai/api/coding/paas/v4";
          description = "ZAI API base URL (matches OpenCode configuration)";
        };

        # Advanced retry configuration
        maxRetries = mkOption {
          type = types.int;
          default = 3;
          description = "Maximum retry attempts for ZAI requests";
        };

        retryDelay = mkOption {
          type = types.float;
          default = 1.0;
          description = "Initial retry delay in seconds (exponential backoff)";
        };

        timeout = mkOption {
          type = types.float;
          default = 300.0;
          description = "Request timeout in seconds";
        };

        enableRetry = mkOption {
          type = types.bool;
          default = true;
          description = "Enable automatic retry with exponential backoff for ZAI requests";
        };

        models = mkOption {
          type = types.attrs;
          default = {
            "glm-5" = {
              name = "GLM-5 (200K)";
            };
            "glm-4.7" = {
              name = "GLM-4.7 (200K)";
            };
            "glm-4.6" = {
              name = "GLM-4.6 (256K)";
            };
            "glm-4.5-air" = {
              name = "GLM-4.5 Air (128K)";
            };
          };
          description = "Available ZAI models";
        };
      };
    };

    # API Gateway configuration
    gateway = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable API gateway (routing, auth, metrics)";
      };

      host = mkOption {
        type = types.str;
        default = "0.0.0.0"; # Listen on all interfaces for Spacebot integration
        description = "Gateway listen address (use 0.0.0.0 for all interfaces or Tailscale IP for network access)";
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Gateway listen port";
      };

      workers = mkOption {
        type = types.int;
        default = 4;
        description = "Number of uvicorn workers";
      };

      # Middleware configuration
      middleware = {
        redis = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable Redis for middleware features";
          };
          host = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = "Redis host";
          };
          port = mkOption {
            type = types.int;
            default = 6379;
            description = "Redis port";
          };
        };
      };
    };

    # Model routing configuration
    routing = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable intelligent model routing by context size";
      };

      # Graceful degradation fallback chain
      fallbackChain = mkOption {
        type = types.listOf types.str;
        default = [
          "vllm"
          "lm-studio"
          "zai"
        ];
        description = "Order of backend fallback on failure";
      };

      rules = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              minTokens = mkOption {
                type = types.int;
                description = "Minimum token count for this rule";
              };
              maxTokens = mkOption {
                type = types.int;
                default = 999999;
                description = "Maximum token count for this rule";
              };
              model = mkOption {
                type = types.str;
                description = "Model to use for this range";
              };
              priority = mkOption {
                type = types.int;
                default = 0;
                description = "Priority (higher = preferred)";
              };
              contextLength = mkOption {
                type = types.int;
                default = 262144; # 256K for Qwen3.5
                description = "Context window size in tokens";
              };
            };
          }
        );
        default = [
          {
            minTokens = 0;
            maxTokens = 131072; # Up to 128K tokens
            model = "qwen3.5-35b-a3b";
            priority = 10;
            contextLength = 262144; # 256K context
          }
          {
            minTokens = 131073; # 128K+ tokens
            maxTokens = 999999;
            model = "qwen3.5-27b";
            priority = 20;
            contextLength = 262144; # 256K context
          }
        ];
        description = "Model routing rules by token count (Qwen3.5 supports 256K)";
      };

      defaultModel = mkOption {
        type = types.str;
        default = "qwen3.5-35b-a3b";
        description = "Default model when routing is disabled or no rule matches";
      };
    };

    # Authentication configuration
    auth = {
      mode = mkOption {
        type = types.enum [
          "none"
          "tailscale"
          "api-key"
          "web3"
        ];
        default = "none";
        description = "Authentication mode";
      };

      tailscale = {
        aclTags = mkOption {
          type = types.listOf types.str;
          default = [];
          example = [
            "tag:ai-inference"
            "tag:trusted"
          ];
          description = "Allowed Tailscale ACL tags (empty = allow all Tailscale IPs)";
        };
      };

      apiKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = literalExpression "/etc/ai-inference/api-keys.txt";
        description = "Path to API keys file (key:tier:tokens_remaining, one per line)";
      };
    };

    # Monitoring configuration
    monitoring = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Prometheus metrics export";
      };

      port = mkOption {
        type = types.port;
        default = 9190;
        description = "Metrics endpoint port (separate from gateway)";
      };
    };

    # Rate limiting
    rateLimit = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable rate limiting";
      };

      requestsPerMinute = mkOption {
        type = types.int;
        default = 60;
        description = "Requests per minute per client";
      };
    };

    # MCP Broker configuration
    mcp = {
      enable = mkEnableOption "MCP broker for aggregating tools from multiple MCP servers";

      servers = mkOption {
        type = types.attrsOf (
          types.submodule ({config, ...}: {
            options = {
              type = mkOption {
                type = types.enum ["local" "remote"];
                default = "remote";
                description = "MCP server type: local (stdio subprocess) or remote (HTTP)";
              };

              url = mkOption {
                type = types.nullOr types.str;
                default =
                  if config.type == "remote"
                  then null
                  else null;
                description = "MCP server URL (required for remote type)";
              };

              command = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = literalExpression ''[ "${pkgs.python3}/bin/python3" "/etc/nixos/skills/my-skill/server.py" ]'';
                description = "Command to run for local MCP servers (required for local type)";
              };

              environment = mkOption {
                type = types.attrsOf types.str;
                default = {};
                example = {NIX_HOST = "zephyr";};
                description = "Environment variables for local MCP servers";
              };

              headers = mkOption {
                type = types.attrsOf types.str;
                default = {};
                example = {Authorization = "Bearer token";};
                description = "HTTP headers for authentication (remote type only)";
              };

              enabled = mkOption {
                type = types.bool;
                default = true;
                description = "Whether this server is enabled";
              };
            };
          })
        );
        default = {};
        example = literalExpression ''
          {
            # Remote HTTP MCP server
            web-search = {
              type = "remote";
              url = "https://api.example.com/mcp/search";
              headers = { Authorization = "Bearer token"; };
            };
            # Local stdio MCP server
            nix-rebuild = {
              type = "local";
              command = [ "${pkgs.python3}/bin/python3" "/etc/nixos/skills/nix-rebuild/server.py" ];
              environment = { NIX_HOST = "zephyr"; };
            };
          }
        '';
        description = "MCP servers to connect to (both local and remote)";
      };
    };

    # Security options
    security = {
      maxRequestSize = mkOption {
        type = types.int;
        default = 10485760; # 10MB
        description = "Maximum request size in bytes";
      };

      enableProxy = mkOption {
        type = types.bool;
        default = false; # Disabled by default for code assistants
        description = "Enable security proxy (blocks code snippets with certain patterns)";
      };
    };

    # RAG configuration
    rag = {
      enable = mkEnableOption "RAG (Retrieval Augmented Generation) with hybrid search";

      # Qdrant service configuration (submodule)
      qdrant = {
        enable = mkEnableOption "Qdrant vector database service for RAG";

        package = mkOption {
          type = types.package;
          default = pkgs.qdrant;
          description = "Qdrant package to use";
        };

        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Qdrant listen address";
        };

        port = mkOption {
          type = types.port;
          default = 6333;
          description = "Qdrant HTTP port";
        };

        grpcPort = mkOption {
          type = types.port;
          default = 6334;
          description = "Qdrant gRPC port";
        };

        storagePath = mkOption {
          type = types.str;
          default = "/var/lib/qdrant";
          description = "Qdrant storage path";
        };

        memoryLimit = mkOption {
          type = types.str;
          default = "2G";
          description = "Memory limit for Qdrant service";
        };
      };

      qdrantUrl = mkOption {
        type = types.str;
        default = "http://127.0.0.1:6333";
        description = "Qdrant vector database URL";
      };

      embeddingModel = mkOption {
        type = types.str;
        default = "sentence-transformers/all-MiniLM-L6-v2";
        description = "Embedding model for document chunking";
      };

      chunkSize = mkOption {
        type = types.int;
        default = 512;
        description = "Chunk size for document splitting (characters)";
      };

      chunkOverlap = mkOption {
        type = types.int;
        default = 50;
        description = "Overlap between chunks";
      };

      topK = mkOption {
        type = types.int;
        default = 5;
        description = "Number of documents to retrieve";
      };

      hybridSearch = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable hybrid search (vector + BM25)";
        };

        vectorWeight = mkOption {
          type = types.float;
          default = 0.7;
          description = "Weight for vector search (0-1)";
        };

        bm25Weight = mkOption {
          type = types.float;
          default = 0.3;
          description = "Weight for BM25 keyword search (0-1)";
        };
      };

      autoRag = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Automatically detect when to use RAG";
        };

        threshold = mkOption {
          type = types.float;
          default = 0.3;
          description = "Confidence threshold below which RAG is triggered";
        };

        keywords = mkOption {
          type = types.listOf types.str;
          default = [
            "what"
            "how"
            "explain"
            "describe"
            "tell me about"
            "find"
            "search"
            "lookup"
            "who"
            "when"
            "where"
            "why"
          ];
          description = "Keywords that trigger RAG retrieval";
        };
      };

      tokenScopedCollections = mkOption {
        type = types.bool;
        default = true;
        description = "Scope knowledge bases by API token (multi-tenancy)";
      };

      reranker = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable cross-encoder reranking for better RAG precision";
        };

        model = mkOption {
          type = types.str;
          default = "BAAI/bge-reranker-v2-m3";
          description = "Reranker model name (BAAI/bge-reranker-v2-m3 recommended)";
        };
      };
    };

    # Sentry error tracking
    sentry = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Sentry error tracking";
      };

      dsn = mkOption {
        type = types.str;
        default = "";
        description = "Sentry DSN (Data Source Name)";
      };

      dsnFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = literalExpression "/run/agenix/sentry-dsn";
        description = "Path to file containing Sentry DSN (takes precedence over dsn)";
      };

      environment = mkOption {
        type = types.enum ["development" "staging" "production"];
        default = "production";
        description = "Sentry environment name";
      };

      tracesSampleRate = mkOption {
        type = types.float;
        default = 0.1;
        description = "Sample rate for performance tracing (0.0 to 1.0)";
      };
    };

    # LM Studio headless service (optional)
    lm-studio-headless = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Enable LM Studio headless service";
            };
            port = mkOption {
              type = types.port;
              default = 1234;
              description = "Port for LM Studio API server";
            };
            host = mkOption {
              type = types.str;
              default = "127.0.0.1";
              description = "Host address to bind to";
            };
            user = mkOption {
              type = types.str;
              default = "j_kro";
              description = "User to run LM Studio as";
            };
            openFirewall = mkOption {
              type = types.bool;
              default = false;
              description = "Open firewall for the configured port";
            };
          };
        }
      );
      default = null;
      description = "LM Studio headless service configuration (optional)";
    };
  };

  # Import submodules at module level
  imports = [
    ./gateway.nix
    ./router.nix
    ./monitor.nix
    ./health-monitor.nix
    ./auth
    ./qdrant.nix
  ];

  config = mkIf cfg.enable {
    # System packages
    environment.systemPackages = with pkgs; [
      config.services.ai-inference.package
      (pkgs.writeShellScriptBin "ai-inference-status" ''
        #!/bin/bash
        echo "=== AI Inference Service Status ==="
        echo "Backend: ${cfg.backend.type}"
        echo "Backend URL: ${cfg.backend.url}"
        echo "Gateway: ${cfg.gateway.host}:${toString cfg.gateway.port}"
        echo ""
        echo "=== Backend Models ==="
        ${pkgs.curl}/bin/curl -s ${cfg.backend.url}/v1/models | ${pkgs.jq}/bin/jq -r '.data[].id' || echo "Backend unavailable"
        echo ""
        echo "=== Gateway Health ==="
        ${pkgs.curl}/bin/curl -s http://${cfg.gateway.host}:${toString cfg.gateway.port}/health || echo "Gateway unavailable"
      '')
    ];

    # Open firewall for gateway and metrics
    networking.firewall.allowedTCPPorts =
      [
        cfg.gateway.port
      ]
      ++ (lib.optional cfg.monitoring.enable cfg.monitoring.port);

    # Prometheus scrape configuration
    services.prometheus.scrapeConfigs = mkIf cfg.monitoring.enable [
      {
        job_name = "ai-inference-${config.networking.hostName}";
        static_configs = [
          {
            targets = ["${cfg.gateway.host}:${toString cfg.monitoring.port}"];
            labels = {
              instance = config.networking.hostName;
              backend = cfg.backend.type;
            };
          }
        ];
      }
    ];

    # LM Studio headless service (optional)
    services.lm-studio-headless =
      mkIf (cfg.lm-studio-headless != null && cfg.lm-studio-headless.enable)
      {
        enable = true;
        inherit (cfg.lm-studio-headless) port;
        inherit (cfg.lm-studio-headless) host;
        inherit (cfg.lm-studio-headless) user;
        inherit (cfg.lm-studio-headless) openFirewall;
      };

    # Redis for gateway middleware (caching, rate limiting, circuit breaker)
    services.redis.servers.ai-gateway = {
      inherit (cfg.gateway.middleware.redis) enable;
      bind = "127.0.0.1";
      port = 6379;
    };
  };
}
