# AI Inference Service - Main Module
# Integrates with existing LM Studio installation
{
  config,
  lib,
  pkgs,
  options,
  ...
}:

let
  cfg = config.services.ai-inference;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkDefault
    types
    optionalString
    literalExpression
    ;

  # Python package for the gateway
  gatewayEnv = pkgs.python3.withPackages (ps: [
    ps.fastapi
    ps.uvicorn
    ps.httpx
    ps.prometheus-client
    ps.pyjwt
    ps.cryptography
    ps.python-multipart
  ]);

in
{
  options.services.ai-inference = {
    enable = mkEnableOption "AI Inference Service (integrates with LM Studio)";

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
          "zai"
        ];
        default = "lm-studio";
        description = "Backend inference engine type";
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

        baseUrl = mkOption {
          type = types.str;
          default = "https://api.z.ai/v1";
          description = "ZAI API base URL";
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
        default = "127.0.0.1";
        description = "Gateway listen address (use Tailscale IP for network access)";
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
        type = types.listOf (types.str);
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
            };
          }
        );
        default = [
          {
            minTokens = 0;
            maxTokens = 4096;
            model = "qwen3.5-2b";
            priority = 10;
          }
          {
            minTokens = 4097;
            maxTokens = 32768;
            model = "qwen3.5-4b";
            priority = 20;
          }
          {
            minTokens = 32769;
            maxTokens = 999999;
            model = "qwen3.5-35b-a3b@q4_k_m";
            priority = 30;
          }
        ];
        description = "Model routing rules by token count";
      };

      defaultModel = mkOption {
        type = types.str;
        default = "qwen3.5-4b";
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
          default = [ ];
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
  };

  # Import submodules at module level
  imports = [
    ./gateway.nix
    ./router.nix
    ./monitor.nix
    ./auth
  ];

  config = mkIf cfg.enable {
    # Python environment for the gateway - shared with gateway.nix via config
    services.ai-inference.package = gatewayEnv;

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
    networking.firewall.allowedTCPPorts = [
      cfg.gateway.port
    ]
    ++ (lib.optional cfg.monitoring.enable cfg.monitoring.port);

    # Prometheus scrape configuration
    services.prometheus.scrapeConfigs = mkIf cfg.monitoring.enable [
      {
        job_name = "ai-inference-${config.networking.hostName}";
        static_configs = [
          {
            targets = [ "${cfg.gateway.host}:${toString cfg.monitoring.port}" ];
            labels = {
              instance = config.networking.hostName;
              backend = cfg.backend.type;
            };
          }
        ];
      }
    ];
  };
}
