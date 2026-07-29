{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  cluster = config.networking.cluster;
in {
  services = {
    # zephyr runs NO k3s (control plane is nexus/forge/sentry).
    k3s-cluster = {
      enable = false;
    };

    k8s-secret-bootstrap = {
      enable = true;
      secrets = [
        {
          namespace = "auth";
          keys = ["POSTGRES_PASSWORD"];
        }
        {
          namespace = "auth";
          name = "oauth2-proxy-secrets";
          keys = ["client-secret" "cookie-secret"];
        }
        {
          namespace = "automation";
          name = "n8n-secrets";
          keys = ["postgres-password"];
        }
        {
          namespace = "mcp";
          name = "grafana-admin-secret";
          keys = ["admin-password"];
        }
      ];
    };

    # Disabled: zephyr is now a k3s agent (not server), so the VIP
    # should live on the server nodes (sentry) for k3s API access.
    keepalived-vip = {
      enable = true;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 80;
    };

    backup-to-garage = {
      enable = true;
      endpoint = "http://${cluster.hosts.zephyr.ip}:3900";
      region = "garage";
      bucket = "backups";
      secretKeyFile = "/run/secrets/garage-s3-secret-key";
      retentionDays = 30;
      startAt = "02:00";
    };

    gaming-detection = {
      enable = true;
      checkInterval = 10;
    };

    nexus-exec = {
      enable = true;
    };

    gpu-profile-manager = {
      enable = true;
      checkInterval = 10;
    };

    lpminer = {
      enable = true;
      instances = [
        {
          name = "3060ti";
          gpuId = 0;
          wallet = "krxXVNVMM7.zephyr-3060ti";
          powerLimit = 100;
          pool = "stratum+ssl://prl-us.kryptex.network:8048,stratum+ssl://prl.kryptex.network:8048";
        }
        {
          name = "3090";
          gpuId = 1;
          wallet = "krxXVNVMM7.zephyr-3090";
          powerLimit = 150;
          pool = "stratum+ssl://prl-us.kryptex.network:8048,stratum+ssl://prl.kryptex.network:8048";
        }
      ];
    };

    opencode = {
      enable = true;
      clusterSync.enable = false; # skip SSH sync to cluster nodes on every activation
    };



    # Sync hermes/pi state FROM Nexus (Nexus is now canonical source)


    # Caddy — only Tailscale ingress for this host
    # All .lan services moved to nexus (OOM prevention)
    # Uses caddy-with-modules (includes caddy-ratelimit, caddy-security, caddy-cache)
    caddy = {
      enable = true;
      package = pkgs.caddy-with-modules;
      configFile = let
        lanRoutes = import ./caddy-routes.nix {inherit cluster;};
      in
        pkgs.writeText "Caddyfile" ''
          {
            admin 127.0.0.1:2019
            auto_https off
            default_sni cluster.local
          }

          # ── Tailscale Funnel Route (public-facing) ──────────────
          # Rate limited: 100 req/min per IP to protect against brute force/DDoS.
          # Requires caddy-with-modules (mholt/caddy-ratelimit plugin).
          ai.zephyr.taila21e09.ts.net:9002 {
            rate_limit {
              zone funnel_per_ip {
                key    {remote_host}
                events 100
                window 1m
              }
            }
            forward_auth 127.0.0.1:30890 {
              uri /oauth2/auth
              copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
              handle_response {
                @is401 expression {http.reverse_proxy.status_code} == 401
                redir @is401 https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} temporary
              }
            }
            header {
              Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
              X-Content-Type-Options "nosniff"
              X-Frame-Options "SAMEORIGIN"
              Referrer-Policy "strict-origin-when-cross-origin"
              -Server
            }
            encode zstd gzip
            reverse_proxy 127.0.0.1:30880
          }
          ${lanRoutes}
        '';
    };

    # ai-inference: Uses K8s gateway (30880) via Caddy routing
    # Keep config for declarative completeness but backend routes to K8s
    ai-inference = {
      enable = true;
      backend = {
        url = "http://127.0.0.1:30880"; # Proxy to K8s gateway
        type = "llama-cpp";
        local = {
          url = "http://127.0.0.1:30880";
          model = "qwen3.6-35b-a3b";
        };
        nvidia-nim = {
          enable = true;
          apiKeyFile = "/run/secrets/nvidia-api-key";
        };
        pollinations = {
          enable = true;
          apiKeyFile = "/run/secrets/pollinations-api-key";
          baseUrl = "https://text.pollinations.ai";
        };
      };
      routing = {
        enable = true;
        defaultModel = "qwen3.5-35b-a3b";
        fallbackChain = [
          "vllm"
          "pollinations"
        ];
      };
      auth.mode = "none";
      monitoring.enable = lib.mkForce false;
      rateLimit.enable = lib.mkForce false;
      rateLimit.requestsPerMinute = 120;
      systemPrompts = {
        enable = true;
        default = "You are a helpful AI assistant with access to comprehensive knowledge sources.";
        coding = "You are an expert coding assistant. Write clean, efficient, and well-documented code. Use the retrieved knowledge to provide accurate implementations.";
        reasoning = "You are an expert reasoning assistant. Think step-by-step and provide clear explanations backed by retrieved information.";
        analysis = "You are an expert analysis assistant. Provide thorough and structured analysis using multiple sources.";
        agentic = "You are an autonomous agent capable of multi-step planning and execution. Use available tools to complete complex tasks.";
        fast = "You are a fast and efficient assistant. Provide concise, direct answers.";
        custom = {
          nixos = "You are a NixOS configuration expert. Always use lib.mkOptionDefault for shared modules. Reference the cluster documentation.";
          kubernetes = "You are a Kubernetes expert. Use best practices for manifests, deployments, and troubleshooting.";
        };
      };
      security = {
        maxRequestSize = 10485760;
        enableProxy = false;
      };
    };

    mcp-servers = {
      enable = true;
    };

    mcp-registry = {
      enable = true;
      generateHermes = true;
      generateClaudeCode = true;
      generateNetworkPolicies = true;
      generateCasdoorApps = true;
    };

    cachix-auth = {
      enable = true;
    };

    ai-coding-tools = {
      enable = true;
      user = "j_kro";
      context7ApiKeyFile = "/run/secrets/context7-api-key";
      nvidiaNimApiKeyFile = "/run/secrets/nvidia-api-key";
      opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
      tools = {
        claude = {enable = lib.mkForce false;};
        opencode = {enable = lib.mkForce false;};
        droid = {enable = lib.mkForce false;};
        crush = {enable = lib.mkForce false;};
        pi = {enable = lib.mkForce false;};
        omp = {enable = lib.mkForce false;};
      };
      enableShellEnv = true;
    };

    # ── Nix-managed Hermes config.yaml ────────────────────────────
    # Providers, fallback chain, and base_url/key mappings live in Nix.
    # Imperative sections (telegram channel_profiles, MCP servers, etc.)
    # are preserved on disk across rebuilds by systemd hermes-config-emit.
    hermes-cli = {
      enable = true;
      user = "j_kro";

      # Phase 2 E2 migration (2026-07-25 pilot): secretspec-resolved
      # credentials via cachix-fork sops:// NDJSON dispatcher (Phase 1a).
      # The hermes-config-secrets.service runs `secretspec get <route>`
      # for each entry and writes the resolved value to ~/.hermes/.env
      # AFTER the Path B sops-nix blocks (Path A wins for any env var
      # defined in both paths). The E1 fallback (Path B = `*ApiKeyFile = "..."`)
      # remains active until operator confirms and drops the stale lines.
      #
      # Note: HUGGINGFACE_TOKEN + GITHUB_TOKEN are listed for forward
      # consistency with /etc/nixos/secretspec.toml, but neither has a
      # wired `*ApiKeyFile = "..."` line in this host config — they will
      # resolve via Path A only. If `secretspec get` returns empty for
      # those routes, Path A logs WARN and Herme doesn't get those env
      # vars (caller falls through to ~/.hermes/.env defaults / vault).
      secretspecEnvVarMappings = {
        "NVIDIA_API_KEY"      = "NVIDIA_API_KEY";
        "OPENCODE_API_KEY"    = "OPENCODE_ZEN_API_KEY";
        "OPENCODE_GO_API_KEY" = "OPENCODE_GO_API_KEY";
        "HUGGINGFACE_TOKEN"   = "HUGGINGFACE_TOKEN";
        "GITHUB_TOKEN"        = "GITHUB_TOKEN";
        "MEMLAWB_PASSPHRASE"  = "MEMLAWB_PASSPHRASE";
      };

      nvidiaApiKeyFile = "/run/secrets/nvidia-api-key";
      opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
      opencodeZenApiKeyFile = "/run/secrets/opencode-api-key";
      gatewayUrl = "http://${cluster.hosts.zephyr.ip}:${toString cluster.kubernetes.nodePorts.ai-inference-gateway}/v1";

      managedConfig = true;
      managedProviders = {
        # Cloud-only providers that drive the picker. Local inference
        # (forge/llama-cpp) lives outside this config — exposed via the
        # AI inference gateway and used by smart_model_routing, not the
        # model picker.
        "opencode-zen" = {
          api_key_env = "OPENCODE_API_KEY";
          base_url = "https://opencode.ai/zen/v1";
          discover_models = true;
          model = "nemotron-3-ultra-free";
        };
        "opencode-go" = {
          api_key_env = "OPENCODE_GO_API_KEY";
          base_url = "https://opencode.ai/zen/go/v1";
          discover_models = true;
        };
        "nvidia" = {
          api_key_env = "NVIDIA_API_KEY";
          base_url = "https://integrate.api.nvidia.com/v1";
          discover_models = true;
        };
        "llama-cpp-sentry" = {
          base_url = "http://llama-server-sentry.ai-inference.svc.cluster.local:1235/v1";
          api_key = "unused";
          model = "Qwen3.5-4B-Q4_K_M.gguf";
        };
      };
      managedFallbackProviders = [
        "opencode-zen"
        "opencode-go"
        "nvidia"
      ];
      # MoA config is imperative in ~/.hermes/config.yaml (moa: section).
      # hermes-moa-declarative.nix is DEAD CODE — see its header for details.
      # Do NOT uncomment this import without syncing presets from the live config first.
    };
  };
  programs = {
    haven-desktop.enable = lib.mkForce false;
  };

  virtualisation.podman = {
    enable = lib.mkForce false;
    dockerCompat = true;
    dockerSocket.enable = false;
  };

  services.appimage-updater.enable = lib.mkForce false;

  # Phase 1b/1c (2026-07-25): explicit per-host opt-in for the secretspec-validator
  # systemd unit. The cachix-fork secretspec is now a flake input (Phase 1a) — no
  # impure-eval coupling needed. cluster.localSealSupport option was removed
  # (vestigial after Phase 1a made the fork probe unnecessary).
  services.secretspec-validator.enable = true;

  services.sops-secrets-registry = {
    # ALL categories enabled — verified decrypt OK on all categories
    # (cloud/storage/mining/automation/ci/selfHosting/monitoring all test clean)
    enable = true;
    aiServices = true;
    monitoring = true;
    storage = true;
    mining = true;
    kubernetes = true;
    automation = true;
    ci = true;
    selfHosting = true;
  };

  # Mining user for secret ownership (ZEPHYR monitors mining but doesn't run workers)
  users.users.mining = {
    isSystemUser = true;
    group = "mining";
    description = "Mining service user";
  };

  users.groups.mining = {};

  # Initrd SSH recovery + BTRFS snapshots
  services.initrd-ssh-recovery = {
    enable = true;
    interface = "enp38s0";
    networkDriver = "r8169";
    port = 2222;
  };
  services.recovery-specialisation.enable = true;
  services.secret-hygiene.enable = lib.mkForce false;
  services.btrfs-boot-snapshot.enable = false; # NixOS generations sufficient

  # Create directories for hermes/pi bind mounts on Zephyr.
  # Also symlink /etc/cdi -> /var/run/cdi so podman finds the nvidia-container-toolkit
  # CDI spec (the generator writes to /var/run/cdi; podman reads /etc/cdi by default).
  # This exposes nvidia.com/gpu={0,1,all}, incl. the RTX 3090.
  systemd.tmpfiles.rules = [
    "d /data/hermes 0775 j_kro j_kro -"
    "L+ /etc/cdi - - - - /var/run/cdi"
  ];

  # Moved to K3s deployment (kubernetes-manifests/ingress/cloudflared-tunnel.yaml)
  # services.cloudflared-tunnel = { ... }
}
