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
      # Run gateway as j_kro — eliminates the permission war between
      # gateway (hermes user) and CLI (j_kro). One user, one identity,
      # zero chmod conflicts. secure_parent_dir() can 0700 all it wants.
      user = "j_kro";
      group = "users";
      createUser = false;
      settings = {
        model.default = "zai";

        providers = {
          zai = {
            base_url = "https://api.z.ai/api/coding/paas/v4";
            api_key_env = "ZAI_API_KEY";
            model = "glm-4.7";
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
          nous = {
            discover_models = true;
          };
          # Local llama-cpp endpoints (network fallbacks)
          llama-cpp-sentry = {
            base_url = "http://sentry:1235/v1";
            api_key = "unused";
            model = "Qwen3.5-4B-Q4_K_M.gguf";
          };
          llama-cpp-zephyr = {
            base_url = "http://zephyr:1237/v1";
            api_key = "unused";
            model = "Carnice-Qwen3.6-MoE-35B-A3B.IQ4_XS.gguf";
          };
          forge-gemma4 = {
            base_url = "http://forge:8002/v1";
            api_key = "unused";
            model = "gemma-4-E2B-it-Q4_K_M.gguf";
          };
          forge-qwen = {
            base_url = "http://forge:8003/v1";
            api_key = "unused";
            model = "Qwen3.5-4B-Q4_K_M.gguf";
          };
        };
        fallback_providers = ["opencode-go" "zai" "nvidia" "forge-gemma4" "forge-qwen" "llama-cpp-zephyr" "llama-cpp-sentry"];
        smart_model_routing = {
          enabled = true;
          max_simple_chars = 160;
          max_simple_words = 28;
          cheap_model = {
            provider = "forge-qwen";
            model = "Qwen3.5-4B-Q4_K_M.gguf";
          };
        };
        toolsets = ["all"];
        approvals = {
          mode = "smart";
          destructive_slash_confirm = true;
          mcp_reload_confirm = false;
        };
        skills = {
          write_approval = false;
          default = [
            "windows-kvm-mgmt"
            "nixos-cluster-config"
            "nixos-hermes-config"
            "github-pr-workflow"
            "nixos-ssh"
            "nixos-home-manager"
          ];
        };
        memory = {
          memory_enabled = true;
          user_profile_enabled = true;
          provider = "mnemosyne";
          write_approval = false;
        };
        terminal = {
          backend = "local";
          timeout = 300;
        };
        compression = {
          enabled = true;
          threshold = 0.75;
        };
        mcp_discovery_timeout = 0.5;
        hooks = {};
        hooks_auto_accept = true;
        tool_output = {
          max_bytes = 150000;
        };
        tool_loop_guardrails = {
          hard_stop_enabled = true;
        };
        tts = {
          provider = "chatterbox";
          providers.kokoro = {
            type = "command";
            command = "${pkgs.kokoro-tts}/bin/kokoro-tts.sh {input_path} {output_path} {voice}";
            output_format = "mp3";
            voice = "am_fenrir";
          };
          providers.chatterbox = {
            type = "command";
            command = "${pkgs.chatterbox-tts}/bin/chatterbox-tts.sh {input_path} {output_path} {voice}";
            output_format = "mp3";
            voice = "Connor.wav";
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
          enabled = true;
          provider = "local";
          providers.local = {
            model = "base";
            language = "";
          };
          providers.openai = {
            model = "whisper-1";
          };
          providers.mistral = {
            model = "voxtral-mini-latest";
          };
          providers.elevenlabs = {
            model_id = "scribe_v2";
            language_code = "";
            tag_audio_events = false;
            diarize = false;
          };
        };
        human_delay = {
          mode = "off";
          min_ms = 800;
          max_ms = 2500;
        };
        auxiliary = {
          vision.provider = "nvidia";
          vision.model = "meta/llama-3.2-90b-vision-instruct";
          web.provider = "nvidia";
          web.model = "meta/llama-3.2-90b-vision-instruct";
          compression.provider = "nvidia";
          compression.model = "meta/llama-3.1-70b-instruct";
          session_title.provider = "nvidia";
          session_title.model = "meta/llama-3.1-70b-instruct";
        };
      };
      environmentFiles = [ "/run/secrets/hermes-env" ];
      extraDependencyGroups = ["messaging" "voice"];
      extraPackages = with pkgs; [ripgrep jq curl portaudio];
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
        casdoor = {
          command = "python3";
          args = ["/data/agents/mcp-bridges/casdoor-mcp-bridge.py"];
          connect_timeout = 30;
          timeout = 60;
        };
        yt-dlp = {
          command = "/data/agents/mcp-bridges/yt-dlp-mcp.sh";
          connect_timeout = 15;
          timeout = 300;
        };
      };
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
      enable = false;  # Replaced by peakminer
    };
    peakminer = {
      enable = true;
      instances = [
        {
          name = "zephyr-3060ti";
          wallet = "krxXVNVMM7.zephyr-3060ti";
          pools = ["stratum+tcp://prl-us.kryptex.network:7048" "stratum+tcp://prl.kryptex.network:7048"];
          devices = "0";
          gpuId = 0;
          powerLimit = 120;
          tempStop = 80;
          apiPort = 21553;
        }
        {
          name = "zephyr-3090";
          wallet = "krxXVNVMM7.zephyr-3090";
          pools = ["stratum+tcp://prl-us.kryptex.network:7048" "stratum+tcp://prl.kryptex.network:7048"];
          devices = "1";
          gpuId = 1;
          powerLimit = 250;
          tempStop = 80;
          apiPort = 21554;
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

  # Fish completions for hermes CLI (was in hermes-cli module)
  programs.fish.interactiveShellInit = lib.mkAfter ''
    if command -v hermes &>/dev/null
      hermes completion fish 2>/dev/null | grep -v '^SITECUSTOMIZE:' | source
    end
  '';

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

  # Sync sops secrets to K8s
  services.k8s-secrets-sync.enable = true;

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
never-default=no

[ipv6]
method=disabled

[proxy]
NMKEYFILE
      chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection
    fi

    # Ensure wlan0 never gets a default route (prevents duplicate routes)
    for p in /etc/NetworkManager/system-connections/*wlan*; do
      [ -f "$p" ] || continue
      if ! grep -q "never-default=yes" "$p"; then
        sed -i '/^\[ipv4\]$/a never-default=yes' "$p"
      fi
    done
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


  # ── Graphiti MCP (temporal knowledge graph) ──
  services.graphiti-mcp = {
    enable = true;
    port = 8000;
    openFirewall = false;
    openaiApiUrl = "http://10.1.1.130:8003/v1";
    modelName = "Qwen3.5-4B-Q4_K_M.gguf";
  };

  # ── Forge inference endpoints (for Herramientas) ──
  # Gemma 4 on forge:8002 (stronger, 131K ctx)
  # Qwen3.5-4B on forge:8003 (lighter, faster)
  # Sentry Qwen3.5-4B on 10.1.1.140:8001 (with --embeddings)

  # ── Chatterbox-TTS (multi-engine GPU TTS on RTX 3090) ──
  services.chatterbox-tts = {
    enable = true;
    port = 8004;
    openFirewall = true;
    gpuIndex = 1; # RTX 3090
  };

  # ── MCP Memory Servers (declarative management) ──

  # Agentmemory - 53 tools for persistent coding memory
  services.agentmemory-mcp = {
    enable = true;
  };

  # Sequential Thinking - chain reasoning steps with continuity
  services.sequential-thinking-mcp = {
    enable = true;
  };

  # Graphiti is already configured above (line 663-669)


  # ── Hermes Gateway Permissions Override ──
  # Allow sudo from gateway (same access as CLI)
  # hermes-agent module sets NoNewPrivileges=true by default - override it
  systemd.services.hermes-agent = {
    serviceConfig = {
      NoNewPrivileges = lib.mkForce false;
      ProtectSystem = lib.mkForce "yes";  # Allow /etc, /var writes
    };
  };

  # PYTHONPATH includes venv-hermes (for sitecustomize.py runtime patches)
  # and mnemosyne-venv (for the memory provider).
  systemd.services.hermes-agent.environment = {
    PYTHONPATH = lib.mkForce "/home/j_kro/.venv-hermes/lib/python3.12/site-packages:/var/lib/hermes/mnemosyne-venv/lib/python3.11/site-packages";
  };

  systemd.user.services.hermes-gateway = {
    description = "Hermes Agent Gateway - Messaging Platform Integration";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.hermes-agent}/bin/hermes gateway run";
      Restart = "always";
      RestartSec = "10s";
      StandardOutput = "journal";
      StandardError = "journal";

      WorkingDirectory = "/home/j_kro";
      Path = lib.makeBinPath [pkgs.procps];
      
      # Security hardening
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = ["/home/j_kro/.hermes"];
      NoNewPrivileges = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      RestrictRealtime = true;
      RestrictNamespaces = true;
    };
    
    environment = {
      HERMES_HOME = "/home/j_kro/.hermes";
      HERMES_MANAGED = "true";
    };
  };

  time.timeZone = lib.mkForce "America/Winnipeg";
}

