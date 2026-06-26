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
    hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      settings = {
        model = {
          api_mode = "chat_completions";
          base_url = "https://opencode.ai/zen/go/v1";
          default = "deepseek-v4-flash";
          provider = "opencode-go";
        };
        providers = {
          zai = {
            base_url = "https://api.z.ai/api/coding/paas/v4";
            api_key_env = "ZAI_API_KEY";
            discover_models = true;
          };
          opencode-go = {
            base_url = "https://opencode.ai/zen/go/v1";
            api_key_env = "OPENCODE_GO_API_KEY";
            discover_models = true;
          };
          nvidia = {
            base_url = "https://integrate.api.nvidia.com/v1";
            api_key_env = "NVIDIA_API_KEY";
            discover_models = true;
          };
        };
        smart_model_routing = {
          enabled = true;
          max_simple_chars = 160;
          max_simple_words = 28;
          cheap_model = {
            provider = "llama-cpp-sentry";
            model = "Qwen3.5-4B-Q4_K_M.gguf";
          };
        };
        toolsets = ["all"];
        compression = {
          enabled = true;
          threshold = 0.9;
        };
        memory = {
          memory_enabled = true;
          user_profile_enabled = true;
          provider = "mnemosyne";
        };
        terminal = {
          backend = "local";
          timeout = 120;
        };
        display = {
          skin = "slate";
        };
        onboarding = {
          seen = {
            busy_input_prompt = true;
            tool_progress_prompt = true;
          };
        };
        tts = {
          provider = "edge-uv";
          providers = {
            "edge-uv" = {
              type = "command";
              command = "uv run edge-tts -f {input_path} -v {voice} --write-media {output_path}";
              output_format = "mp3";
              voice = "en-US-BrianNeural";
            };
          };
        };
        voice = {
          record_key = "ctrl+b";
          max_recording_seconds = 120;
          auto_tts = true;
          beep_enabled = true;
          silence_threshold = 200;
          silence_duration = 3.0;
        };
        stt = {
          provider = "local";
          local = {
            model = "base";
          };
        };
        approvals = {
          mcp_reload_confirm = false;
        };
      };
      environmentFiles = [ "/run/secrets/hermes-env" ];
      extraDependencyGroups = ["messaging" "voice"];
      extraPackages = with pkgs; [ripgrep jq curl];
      documents = {
        "USER.md" = ''
          NixOS/k3s homelab operator and developer.
        '';
      };
      mcpServers = {
        agentmemory = {
          command = "npx";
          args = ["-y" "@agentmemory/mcp"];
          connect_timeout = 30;
          timeout = 120;
        };
    graphiti = {
      url = "http://localhost:8000/mcp/";
      connect_timeout = 30;
      timeout = 120;
    };
        git = {
          command = "/data/agents/mcp-bridges/git-mcp.sh";
          connect_timeout = 5;
          timeout = 30;
        };
        github = {
          command = "/data/agents/mcp-bridges/github-mcp.sh";
          connect_timeout = 5;
          timeout = 120;
        };
        searxng = {
          command = "/data/agents/mcp-bridges/searxng-mcp.sh";
          connect_timeout = 30;
          timeout = 120;
        };
        sequential-thinking = {
          command = "/data/agents/mcp-bridges/sequential-thinking.sh";
          connect_timeout = 10;
          timeout = 120;
        };
        nixos-cluster = {
          command = "nix";
          args = ["run" "/etc/nixos#nixos-cluster-mcp"];
          connect_timeout = 30;
          timeout = 120;
        };
        lightpanda = {
          command = "/home/j_kro/.local/bin/lightpanda";
          args = ["mcp"];
          connect_timeout = 30;
          timeout = 120;
        };
        kubernetes = {
          command = "kubernetes-mcp-server";
          connect_timeout = 30;
          timeout = 120;
        };
        context7 = {
          command = "/data/agents/mcp-bridges/context7-mcp.sh";
          connect_timeout = 30;
          timeout = 120;
        };
        prometheus = {
          command = "prometheus-mcp-server";
          connect_timeout = 30;
          timeout = 120;
        };
        selfhosted-tools = {
          command = "/data/agents/mcp-bridges/selfhosted-mcp.sh";
          connect_timeout = 30;
          timeout = 120;
        };
        cua-driver = {
          command = "/data/agents/mcp-bridges/cua-driver-mcp.sh";
          connect_timeout = 30;
          timeout = 120;
        };
        maplespike = {
          command = "/data/agents/mcp-bridges/maplespike-mcp-std.sh";
          connect_timeout = 30;
          timeout = 120;
        };
      };
    };
    hermes-cli = {
      enable = true;
      apiKeyFile = "/run/secrets/zai-api-key";
      casdoorJwtFile = "/run/secrets/casdoor-hermes-jwt";
      # apiKey set via hermes-env for MCP server template injection
      # Hermes-mcp-servers service merges servers from Nix fallback block
      # Service enabled below for declarative MCP management.
      # model = "opencode-go/deepseek-v4-flash" not mapped to module
      # options; hermes-cli module only provides JWT/MCP/package mgmt.
    };
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "agent";
      nodeName = "zephyr";
      serverAddr = "https://${cluster.hosts.nexus.ip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = cluster.hosts.zephyr.ip;
    };

    k8s-secret-bootstrap = {
      enable = true;
      secrets = [
        {
          namespace = "auth";
          name = "casdoor-postgres-secret";
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

        keepalived-vip = {
      # Disabled: VRRP multicast is broken between nodes.
      # VIP managed by nexus via localCommands.
      enable = false;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 105;
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

    srbminer = {
      enable = true;
      tls = false;
      instances = [
        {
          name = "zephyr-3060ti";
          gpuId = 0;
          wallet = "krxXVNVMM7.zephyr-3060ti";
          pool = "stratum+tcp://prl-us.kryptex.network:7048";
          apiPort = 21553;
          powerLimit = 120;
        }
        {
          name = "zephyr-3090";
          gpuId = 1;
          wallet = "krxXVNVMM7.zephyr-3090";
          pool = "stratum+tcp://prl-us.kryptex.network:7048";
          apiPort = 21554;
          powerLimit = 250;
        }
      ];
    };

    opencode = {
      enable = true;
      clusterSync.enable = true; # skip SSH sync to cluster nodes on every activation
    };

    nixos-share = {
      enable = true;
      server.enable = true;
    };

    # NFS server for /etc/nixos only — hermes/pi moved to Nexus to break I/O loop on root NVMe
    nfs-data-server = {
      enable = true;
      exports = "";
    };

    # Sync hermes/pi state FROM Nexus (Nexus is now canonical source)
    nfs-state-sync = {
      enable = true;
      sourceHost = "nexus";
      paths = ["/data/hermes"];
      interval = "15min";
    };

    nfs-client = {
      enable = true;
      mountShared = false;
      mountHome = false;
      mountMedia = false;
    };

    # Caddy — only Tailscale ingress for this host
    # All .lan services moved to nexus (OOM prevention)
    # Uses caddy-with-modules (includes caddy-ratelimit, caddy-security, caddy-cache)
    caddy = {
      enable = false;
      package = pkgs.caddy-with-modules;
      configFile = let
        lanRoutes = import ./caddy-routes.nix {inherit cluster;};
      in
        pkgs.writeText "Caddyfile" ''
          {
            admin 127.0.0.1:2019
            auto_https off
            default_sni cluster.local
            http_port 80
            https_port 443
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
        zai = {
          enable = true;
          apiKeyFile = "/run/secrets/zai-api-key";
          baseUrl = "https://api.z.ai/api/coding/paas/v4";
          enableRetry = true;
          maxRetries = 3;
          retryDelay = 1.0;
          timeout = 300.0;
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
          "zai"
          "pollinations"
        ];
      };
      auth.mode = "none";
      monitoring.enable = true;
      rateLimit.enable = true;
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
      zaiApiKeyFile = "/run/secrets/zai-api-key";
      context7ApiKeyFile = "/run/secrets/context7-api-key";
      nvidiaNimApiKeyFile = "/run/secrets/nvidia-api-key";
      opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
      tools = {
        claude = {enable = true;};
        opencode = {enable = true;};
        droid = {enable = true;};
        crush = {enable = true;};
        pi = {enable = true;};
        omp = {enable = true;};
      };
      enableShellEnv = true;
    };
  };
  programs = {
    haven-desktop.enable = true;
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  services.appimage-updater.enable = true;

  services.sops-secrets-registry = {
    enable = true;
    aiServices = true;
    monitoring = false;
    storage = true;
    mining = true;
    cloud = true;
    kubernetes = true;
    automation = true;
    ci = true;
    selfHosting = true;
  };

  # hermes-mcp-servers enabled — merges MCP servers from Nix fallback block
  # into config.yaml. All servers (including cua-driver) are defined there.
  systemd.services.hermes-mcp-servers.enable = true;

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
    interface = "eth0";
    networkDriver = "r8169";
    port = 2222;
  };
  services.recovery-specialisation.enable = true;
  services.secret-hygiene.enable = true;
  services.btrfs-boot-snapshot.enable = lib.mkForce false; # NixOS generations sufficient

  # Create directories for hermes/pi bind mounts on Zephyr
  systemd.tmpfiles.rules = [
    "d /data/hermes 0775 j_kro j_kro -"
  ];
  services.syncthing-cluster.enable = true;

  # Add j_kro to the hermes group so the interactive CLI can read the
  # shared state under /var/lib/hermes/.hermes/ (config, .env, sessions).
  users.users.j_kro.extraGroups = [ "hermes" ];

  # Ensure eth0 has persistent static NM profile on every activation.
  # Prevents the "no IP on boot" issue caused by stale DHCP profiles
  # (enp38s0, ethernet-enp38s0) matching the same MAC 2C:F0:5D:A1:B8:EF.
  system.activationScripts.eth0-static-profile = ''
    # Clean up any auto-created DHCP profiles for this MAC
    for p in /etc/NetworkManager/system-connections/*.nmconnection; do
      [ -f "$p" ] || continue
      mac=$(grep 'mac-address=' "$p" 2>/dev/null | head -1 | cut -d= -f2)
      method=$(grep 'method=' "$p" 2>/dev/null | head -1 | cut -d= -f2)
      if [ "$mac" = "2C:F0:5D:A1:B8:EF" ] && [ "$method" = "auto" ]; then
        rm -f "$p"
      fi
    done
    # Create static profile if missing
    if [ ! -f /etc/NetworkManager/system-connections/eth0.nmconnection ]; then
      cat > /etc/NetworkManager/system-connections/eth0.nmconnection << 'NMKEYFILE'
[connection]
id=eth0
uuid=ecda2be0-391b-466f-8d38-90d707212a9d
type=ethernet
interface-name=eth0
autoconnect=true

[ethernet]
mac-address=2C:F0:5D:A1:B8:EF

[ipv4]
address1=10.1.1.110/24
gateway=10.1.1.1
method=manual
route-metric=100

[ipv6]
method=disabled

[proxy]
NMKEYFILE
      chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection
    fi
  '';

  # Sync hermes-env sops secret → user .env on every activation.
  # The hermes-agent systemd service loads hermes-env via environmentFiles,
  # but user CLI reads ~/.hermes/.env directly. This keeps them in sync.
  system.activationScripts.hermes-dotenv = lib.stringAfter ["users"] ''
    if [ -f /run/secrets/hermes-env ] && [ -s /run/secrets/hermes-env ]; then
      cp /run/secrets/hermes-env /home/j_kro/.hermes/.env
      chown j_kro:users /home/j_kro/.hermes/.env
      chmod 600 /home/j_kro/.hermes/.env
      echo "[hermes-dotenv] Synced .env from hermes-env"
    fi
  '';

  # Pass DISPLAY to hermes-agent so cua-driver MCP can access X11
  # Ensure ckb-next can find sinfo/animation binaries (they're in libexec/ not on PATH)
  system.activationScripts.ckb-next-libexec = lib.stringAfter ["users"] ''
    CKB_LIBEXEC=$(dirname $(readlink -f $(which ckb-next-daemon 2>/dev/null || echo /nonexistent)) 2>/dev/null)/../libexec
    if [ -d "$CKB_LIBEXEC" ] && [ -f "$CKB_LIBEXEC"/ckb-next-sinfo ]; then
      ln -sf "$CKB_LIBEXEC"/ckb-next-sinfo /run/current-system/sw/bin/ckb-next-sinfo 2>/dev/null || true
      echo "[ckb-next-libexec] Symlinked ckb-next-sinfo to system PATH"
    fi
  '';


  systemd.services.hermes-agent.environment = {
    DISPLAY = ":0";
  };


  time.timeZone = lib.mkForce "America/Winnipeg";
}
