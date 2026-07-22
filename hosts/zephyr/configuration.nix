# Zephyr Host Configuration
# RTX 3090, Quest Pro, 4K HDR TV
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    # ========================================================================
    # BASE MODULES
    # ========================================================================

    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix
    # Kubernetes control plane
    ../../modules/services/k3s-cluster.nix
    # Keepalived VIP for Kubernetes HA
    ../../modules/services/keepalived-vip.nix
    # FIX: Systemd user unit reload timeout (nixos-rebuild switch hang)
    ../../modules/system/systemd-user-timeout.nix

    # All other modules auto-imported via ../../modules/default.nix
    # This includes: system, desktop, shell, gaming, development, services,
    # plus zephyr-specific modules (nvidia-common, gstreamer, spotify, cluster networking)
    ../../modules/default.nix

    # NVIDIA GPU Wayland support (host-dependent)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix

    # RGB control for peripherals and components
    ../../modules/hardware/rgb-control.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  # Note: interfaceName provided by node-profiles.zephyr-workstation
  clusterNetworking = {
    enable = true;
    hostName = "zephyr";
    ipAddress = "10.1.1.110";
    wireless = {
      enable = true;
      ipAddress = "10.1.1.115"; # Static IP for WiFi backup
    };
    usbEthernet.enable = true; # Support USB ethernet adapters
    unbound.listenAddress = "10.1.1.110";
  };

  # FIX: Disable interface renaming - use actual interface names
  systemd.network.links = lib.mkForce { };

  # ============================================================================
  # MEMORY OPTIMIZATION - zram compressed swap + kernel tuning
  # ============================================================================
  # VM sysctls (vfs_cache_pressure, swappiness, overcommit) handled by
  # vm-tuning.nix with mkForce — only host-specific overrides here.
  # Previous vfs_cache_pressure=1000 caused excessive page cache eviction,
  # forcing more SSD swap. vm-tuning.nix sets 150 (mkForce).

  # ZRAM compressed swap — reduces SSD wear, faster than disk swap
  # 25% of 31GB ≈ 8GB compressed swap (zstd compression ~2-3x ratio)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 999; # Prefer zram over disk swap
  };

  boot.kernel.sysctl = {
    # Network buffer tuning (frees unused socket buffers)
    "net.core.rmem_default" = 262144; # 256KB (default: 212992)
    "net.core.wmem_default" = 262144; # 256KB
    "net.core.rmem_max" = 16777216; # 16MB max
    "net.core.wmem_max" = 16777216;

    # CALICO CNI REQUIREMENTS
    "net.ipv4.conf.all.rp_filter" = 1; # Reverse path filtering for BGP
  };

  networking = {
    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };
    # Zephyr-specific firewall rules (in addition to cluster defaults)
    firewall = {
      allowedTCPPorts = [
        9757 # WiVRn main port
        18789 # Steam Remote Play
        18790 # Steam Remote Play (secondary)
        19898 # Moonlight/GameStream AND Spacebot Web UI
        8080 # AI Inference Gateway
        8083 # Llamafile standalone LLM service
        53317 # LocalSend (file sharing)
        8888 # CFSSL CA API server (for worker node certificate generation)
        3900 # Garage S3 API
        3901 # Garage RPC
        50000 # Nix binary cache server
        6443 # k3s API server
        2379 # etcd client
        2380 # etcd peer
        10250 # Kubelet API
        179 # Calico BGP
        5473 # Calico Typha
        9100 # Prometheus node-exporter
      ];
      allowedUDPPorts = [
        9757 # WiVRn
        9758 # WiVRn
        9759 # WiVRn
        27031 # Steam UDP
        27036 # Steam UDP
        9947 # WiVRn
        53317 # LocalSend (multicast discovery)
        8472 # VXLAN (Flannel/Calico)
        4789 # VXLAN (Calico)
      ];
      interfaces = {
        # mDNS restricted to LAN interface only (not 0.0.0.0)
        "enp38s0".allowedUDPPorts = [5353 111 2049 20048];
        "tailscale0".allowedTCPPorts = [
          18789
          18790
        ];
        # NFS server - allow local network only
        "enp38s0".allowedTCPPorts = [
          111
          2049
          20048
        ]; # rpcbind, nfs, mountd
      };
    };
  };

  # ============================================================================
  # NODE PROFILE - Platform-level defaults
  # ============================================================================
  # This profile bundles role profiles, Kubernetes config, hardware profiles,
  # and networking configuration. Eliminates ~100 lines of duplication.
  profiles.node.zephyr-workstation.enable = true;

  # MONITORING DISABLED - Protect 31GB RAM for gaming/VR/AI workloads
  # Monitoring stack moved to Nexus (46GB RAM) to prevent OOM on Zephyr
  # Prometheus/Grafana running on Kubernetes (ai-inference namespace)
  # AlertManager running on Nexus via monitoring profile
  profiles.monitoring.enable = lib.mkForce false;

  # ============================================================================
  # SECURITY AUDIT REMEDIATION
  # ============================================================================
  # Enables firewall, Tailscale SSH, and service hardening
  security.clusterAudit = {
    enable = true;
    enableFirewall = true;
    enableTailscaleSSH = true;
    bindServicesToLocalhost = true;
  };

  # Kubernetes security tools for runtime monitoring
  security.kubernetes.enable = true;

  # Trust Caddy Ingress local CA certificate
  security.caddyCa.enable = true;

  # ============================================================================
  # GPU COMPUTE - CUDA + Vulkan support for AI inference
  # ============================================================================
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true; # CUDA for NVIDIA RTX 3090 + 3060 Ti
    vulkan.enable = true; # Vulkan as fallback/universal backend
  };

  # DDC/CI support for external monitor brightness control
  # Note: hardware.video.ddcutil module doesn't exist in NixOS
  # Using ddcutil package + udev rules instead (added to systemPackages)
  services.udev.extraRules = ''
    # Give i2c group access to DDC/CI monitors
    # Allows non-root users to control monitor brightness via ddcutil
    KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"

    # Allow users to control laptop display brightness
    SUBSYSTEM=="backlight", KERNEL=="intel_backlight", MODE="0666", RUN+="${pkgs.coreutils}/bin/chown j_kro:j_kro %k/brightness"
  '';

  # ============================================================================
  # SYSTEMD - Service overrides
  # ============================================================================
  # GameMode daemon - Start at boot for gaming-detection service
  # The gaming module (programs.gamemode) configures GameMode but the daemon
  # is D-Bus activated and doesn't start until a game requests it. This
  # override ensures gamemoded runs at boot so the gaming-detection service
  # can query gaming state via `gamemoded -s` for cluster-wide coordination.
  #
  # Note: GameMode is a D-Bus session service, so we use systemd.user.services
  # to run it in the user session context, not as a system service.
  #
  # FIX: Don't override ExecStart or Type - let gaming module handle those.
  # Only add wantedBy to start at boot. This prevents duplicate ExecStart lines.
  systemd.user.services.gamemoded = {
    wantedBy = [ "default.target" ];
  };

  # ============================================================================
  # SERVICES - All service configurations consolidated here
  # ============================================================================
  services = {
    # KUBERNETES - k3s control plane (joins existing cluster)
    # Bootstrap node: nexus (clusterInit=true, oldest etcd data)
    # All servers join via VIP for HA: https://10.1.1.100:6443
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "server";
      nodeName = "zephyr";
      serverAddr = "https://10.1.1.100:6443";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = "10.1.1.110";
    };

    # Auto-apply K8s manifests on boot (control-plane node)
    k8s-manifest-autoapply.enable = true;

    # Keepalived VIP for HA API server access
    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      interface = "enp38s0";
      priority = 110;
    };

    # Crash watchdog - detect and log system crashes
    # TEMPORARILY DISABLED: Module being fixed (2026-03-23)
    # crash-watchdog.enable = true;

    # Backup to Garage S3 - automated daily backups
    backup-to-garage = {
      enable = true;
      endpoint = "http://10.1.1.110:3900";
      region = "garage";
      bucket = "backups";
      accessKeyFile = "/run/secrets/garage-s3-access-key-id";
      secretKeyFile = "/run/secrets/garage-s3-secret-key";
      retentionDays = 30;
      startAt = "02:00"; # 2 AM daily
    };
  };

  # STATUS.md auto-update (hourly from kubectl)
  services.status-auto-update.enable = true;

  # FIX: Systemd user unit reload timeout (prevents nixos-rebuild switch hang)
  services.systemd-user-timeout.enable = true;

  # Internal CA for cluster services (trusted certificates)
  services.cluster-ca.enable = true;

  # ============================================================================
  # DESKTOP - Wayland compositors (select via SDDM session picker)
  desktop.uwsm-sessions.enable = true;
  programs.niri.enable = true;
  programs.hyprland.enable = true;

  # Autologin into Plasma on boot. To switch compositor, logout
  # and pick from SDDM's session picker.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";
  # NOTE (2026-07-21, issue #300): upstream NixOS removed the bare
  # `plasma` session name from the SDDM valid-session registry. Valid
  # values are now `niri-uwsm`, `niri`, `hyprland`, `hyprland-uwsm`.
  # Uswm-managed Niri is the currently active desktop on Zephyr (see
  # desktop.nix) so keep `niri-uwsm` as the default.
  services.displayManager.defaultSession = "niri-uwsm";

  # HARDWARE PROFILES
  # ============================================================================
  # Base profiles provided by node-profiles.zephyr-workstation:
  # - amd.zen, nvidia.enable, nvidia.multiGpu, monitoring.enable
  #
  # Zephyr-specific hardware overrides/additions:
  hardware = {
    profiles = {
      corsair.enable = true; # Corsair AIO + RGB (not in node profile)
    };

    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

    # Hardware monitoring extras (not covered by profile)
    monitoring = {
      autoDetect = false; # Skip auto-detect, we know the hardware
      fanControl = true; # Custom fan curve control
    };

    # Corsair extras (not covered by profile)
    corsair = {
      aio.enable = true; # Corsair H115i AIO control
      rgb.enable = true; # OpenRGB for RGB control
      autoStartRgb = false; # Don't auto-start (conflicts with liquidctl)
    };

    # RGB control for peripherals and components
    rgb-control = {
      enable = true;
      openrgb.enable = true; # Motherboard, GPU, Corsair devices
      openrazer.enable = true; # Razer Naga Pro mouse
      temperatureReactive = {
        enable = true;
        sensor = "both"; # Monitor both CPU and GPU temps
        thresholds = {
          cool = 50;
          warm = 65;
          hot = 75;
        };
        interval = 5;
      };
    };

    # Bluetooth support via BlueZ
    bluetooth.enable = true;
  };

  # ============================================================================
  # FILESYSTEM COMPRESSION - Enable zstd on all BTRFS filesystems
  # ============================================================================
  # Root and home filesystems lack compression in hardware-configuration.nix
  # Use mkOptionDefault to add compression without breaking other options
  fileSystems = {
    "/".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
    ];
    "/home".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
    ];
  };

  # ============================================================================
  # WIRELESS HARDWARE
  # ============================================================================

  # Locale (timezone inherits cluster default: UTC)
  i18n.defaultLocale = "en_CA.UTF-8";

  # ============================================================================
  # BOOT CONFIGURATION
  # ============================================================================
  # Base bootloader settings provided by common-host-defaults.nix:
  # - systemd-boot.enable, efi.canTouchEfiVariables, kernelPackages (linux_zen)
  # NOTE: Using CachyOS kernel for better sched_ext/scx_lavd support.
  # Zen kernel lacks CONFIG_SCHED_DEADLINE which breaks scx_lavd core compaction.
  # CachyOS 6.19.11: BORE scheduler, x86-64-v3 opts, sched_ext integration.
  # Kernel binary is CACHED (no compilation). Only nvidia module needs building.
  # Uses the flake input's linuxPackages directly to hit the binary cache.
  boot.kernelPackages = inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;
  #
  # Zephyr-specific additions:
  boot = {
    # Multi-GPU kernel modules for RTX 3090 + 3060 Ti
    # (Note: hardware.profiles.nvidia.enable adds nvidia modules automatically)
    kernelModules = [
      "nvidia_uvm" # Unified Memory (CRITICAL for multi-GPU!)
    ];

    extraModprobeConfig = ''
      options nvidia NVreg_EnableBacklightHandler=1
    '';

    # Blacklist unused kernel modules to reduce memory footprint
    # Each loaded module consumes memory - disable what we don't use
    # NOTE: Bluetooth (btusb, bluetooth) and WiFi (iwlmvm, iwlwifi) ARE in use
    blacklistedKernelModules = [
      # Audio dummy modules (rarely used on desktop)
      "snd_seq_dummy"
      "snd_hrtimer"

      # Filesystems not used (Zephyr uses ext4/btrfs only)
      "ufs"
      "hfs"
      "hfsplus"
      "reiserfs"

      # Old networking protocols (not used)
      "appletalk"
      "ipx"
      "decnet"
    ];

    # Zephyr-specific kernel params for gaming
    # (Note: hardware.profiles.amd.zen adds split_lock_detect, threadirqs, preempt)
    kernelParams = [
      "amd_iommu=on" # Enable AMD IOMMU for device passthrough
      "iommu=pt" # IOMMU passthrough mode (better performance)
      "processor.max_cstate=1"
      "intel_idle.max_cstate=1"
      "hugepages=3"
      "btrfs.commit_interval=300" # From btrfs-tuning module
      "nvidia.NVreg_RegistryDwords=EnableBrightnessControl=1" # Enable laptop brightness control
    ];
  };

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  # Base role profiles provided by node-profiles.zephyr-workstation:
  # - workstation, gaming, vr, mining, aiInference
  # Kubernetes and networking also handled by node profile
  #
  # No additional role profiles needed - all handled by node profile

  # Note: profiles.role.gaming enables services.gaming automatically
  # NOTE: Distributed builds configured in modules/system/distributed-builds.nix
  # Do not override here to avoid conflicts

  # ============================================================================
  # SERVICES - Consolidated service configuration
  # ============================================================================
  # Base Kubernetes configuration provided by node-profiles.zephyr-workstation
  # (master + node roles, masterAddress, etc.)
  #
  # Zephyr-specific service additions:
  services = {
    # ============================================================================
    # Modular Workload Monitoring
    # ============================================================================
    # Replaced old compute-workload-monitor monolith with:
    # - gaming-detection: Pure sensor (GameMode + GPU fallback)
    # - gpu-profile-manager: GPU power profile actuator (nvidia-smi)
    # - mining-coordinator: PSI build detection + K8s Volcano preemption
    gaming-detection = {
      enable = true;
      checkInterval = 10;
    };

    gpu-profile-manager = {
      enable = true;
      checkInterval = 10;
    };

    mining-coordinator = {
      enable = true;
      checkInterval = 10;
      # Use conservative thresholds for memory-constrained system
      psiCpuBuildThreshold = "5.0";
      psiCpuIdleThreshold = "2.0";
    };

    # AI CODING AGENT - OpenCode with Kubernetes gateway
    opencode.enable = true;

    # NIX BINARY CACHE - Serve pre-built packages to cluster
    # Eliminates redundant builds across nodes, speeds up deployments
    # ENABLED: Required for distributed builds (2026-03-24)
    # Remote nodes need this cache available during builds
    binary-cache = {
      enable = true;
      port = 50000;
      bindAddress = "10.1.1.110";
    };

    # NOTE (2026-07-21, issue #300): the previous `services.mining` block,
    # kryptex pools/workers, NFS `services.nixos-share`, and the orphan
    # `gaming.hdr.enable` outermost statement were removed as part of the
    # peakminer-only consolidation. Pre-existing bracket typo from a botched
    # xmrig-strip cleanup was fixed in the same edit.

    # NFS removed cluster-wide (2026-05; confirmed by HEY.md run protocol).
    # Zephyr still serves the local `/etc/nixos` checkout; remote hosts track
    # `origin/main` via the git-sync timer in modules/services/nixos-sync.nix,
    # not via NFS.

    # NFS client module kept disabled for now (the option block itself
    # requires a parent `services = { ... }`); expose a placeholder entry
    # only when the NFS-server module is reintroduced.

    # Caddy reverse proxy - Replace nginx for all services
    caddy = {
      enable = true;
      # Custom Caddyfile for complex configurations (Nextcloud)
      # NOTE: Global options manually included because configFile overrides globalConfig
      configFile = pkgs.writeText "Caddyfile" ''
        # Global options
        {
          admin 127.0.0.1:2019
          default_sni cluster.local
        }

        # AI Inference Gateway (via Tailscale)
        ai.zephyr.tigris-ule.ts.net:9002 {
          header {
            Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            Referrer-Policy "strict-origin-when-cross-origin"
            -Server
          }
          encode zstd gzip
          reverse_proxy 127.0.0.1:8080
        }

        # Host Dashboard (LAN access - no TLS)
        http://zephyr.lan {
          header {
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            -Server
          }
          encode zstd gzip
          reverse_proxy 127.0.0.1:8090
        }
        http://dashboard.zephyr.lan {
          header {
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            -Server
          }
          encode zstd gzip
          reverse_proxy 127.0.0.1:8090
        }

        # Kubernetes Ingress (proxy to Caddy ingress controller on Nexus)
        # Using IP directly — Caddy's Go resolver ignores /etc/hosts
        http://search.lan, http://search.cluster.local {
          encode zstd gzip
          reverse_proxy 10.1.1.120:30080
        }
        http://ai.lan, http://ai.cluster.local {
          encode zstd gzip
          reverse_proxy 10.1.1.120:30080
        }
        http://openwebui.lan, http://openwebui.cluster.local {
          encode zstd gzip
          reverse_proxy 10.1.1.120:30080
        }

        # CivicIntel — Canadian Government Intelligence Dashboard
        http://civicintel.lan, http://10.1.1.100 {
          encode zstd gzip
          handle_path /CivicIntel/* {
            reverse_proxy 10.1.1.120:30085
          }
          handle_path /CivicIntel {
            redir /CivicIntel/ permanent
          }
        }
      '';
    };

    # NOTE: caddy-common NOT enabled because configFile overrides globalConfig
    # Global options manually included in configFile above
    # caddy-common = {
    #   enable = true;
    #   adminListenAddress = "127.0.0.1";  # Localhost only for systemd
    # };

    # Spacebot AI agent (integrated with AI Gateway)
    spacebot = {
      enable = true;
      useGateway = true;
      gatewayUrl = "http://127.0.0.1:8081"; # K8s gateway (hostNetwork, port 8081)
      host = "127.0.0.1";
      port = 19898;
      memory = "4G";
      cpu = "2";
      hideUpdateNotification = true;
      providerKeys = {
        ZAI_CODING_PLAN_KEY = "/run/secrets/zai-api-key";
        KILO_API_KEY = "/run/secrets/kilo-api-key";
      };
      discord.enable = false;
      telegram.enable = true;
      telegram.tokenFile = "/run/secrets/spacebot-telegram-token";
    };

    # Redis - For gateway rate limiting and caching
    redis.servers."".enable = true;
    # Note: redis-ai-gateway.service already provides Redis on port 6380

    # SearXNG - Privacy-respecting metasearch engine
    # MIGRATED TO KUBERNETES (2026-03-19) - See kubernetes-manifests/searxng/

    # AI Inference Service - Gateway with ALL FEATURES enabled
    ai-inference = {
      enable = true;
      backend = {
        url = "http://127.0.0.1:8083";
        type = "llama-cpp";
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
      gateway = {
        enable = false; # MOVED TO NEXUS (2026-03-23) - See hosts/nexus/ai-inference.nix
        # host = "0.0.0.0";  # Listen on all interfaces for Kubernetes access
        port = 8080;
        workers = 4;
        middleware.redis.enable = true;
        middleware.knowledgeFabric = {
          enable = true;
          rrf_k = 60;
          # All knowledge sources enabled
          rag_enabled = true;
          searxng_enabled = true;
          searxng_url = "http://10.1.1.120:30808"; # Nexus NodePort (host-accessible)
          searxng_max_results = 10;
          code_search_enabled = true;
          code_search_paths = [
            "/etc/nixos"
            "/home/j_kro"
          ];
          code_max_results = 10;
          web_search_enabled = true;
          web_max_results = 10;
          rag_top_k = 10;
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
      # Enable rate limiting
      rateLimit.enable = true;
      rateLimit.requestsPerMinute = 120;
      # Enable system prompts for different request types
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
      mcp = {
        enable = true;
        servers = {
          nix-rebuild = {
            type = "local";
            command = [
              "${(pkgs.python3.withPackages (ps: [ ps.mcp ])).interpreter}"
              "/etc/nixos/skills/nix-rebuild-mcp/server.py"
            ];
            environment.NIX_HOST = "zephyr";
            environment.NIX_ACCEPT_FLAKE_CONFIG = "1";
            enabled = true;
          };
          add-service = {
            type = "local";
            command = [
              "${(pkgs.python3.withPackages (ps: [ ps.mcp ])).interpreter}"
              "/etc/nixos/skills/add-service-mcp/server.py"
            ];
            environment = { };
            enabled = true;
          };
          context7 = {
            type = "local";
            # Use absolute path for reliable subprocess spawning
            command = [ "/run/current-system/sw/bin/mcp-context7" ];
            environment.CONTEXT7_API_KEY_FILE = "/run/secrets/context7-api-key";
            enabled = true;
          };
          searxng = {
            type = "local";
            command = [
              "python3"
              "-m"
              "ai_inference_gateway.mcp_servers.searxng_server"
            ];
            environment = {
              SEARXNG_URL = "http://searxng.search.svc.cluster.local:8080"; # Kubernetes service DNS
              SEARXNG_CACHE_TTL = "300";
            };
            enabled = true;
          };
        };
      };
      # RAG with Qdrant - FULLY ENABLED
      rag = {
        enable = true;
        qdrantUrl = "http://127.0.0.1:6333";
        embeddingModel = "sentence-transformers/all-MiniLM-L6-v2";
        chunkSize = 512;
        chunkOverlap = 50;
        topK = 10;
        hybridSearch = {
          enable = true;
          vectorWeight = 0.7;
          bm25Weight = 0.3;
        };
        autoRag = {
          enable = true;
          threshold = 0.3;
        };
        tokenScopedCollections = true;
        reranker = {
          enable = true;
          model = "BAAI/bge-reranker-v2-base";
        };
        # Qdrant service - ENABLED locally
        qdrant = {
          enable = true;
          host = "127.0.0.1";
          port = 6333;
          grpcPort = 6334;
          storagePath = "/var/lib/qdrant";
          memoryLimit = "4G";
        };
      };
      # Security options
      security = {
        maxRequestSize = 10485760; # 10MB
        enableProxy = false; # Disabled for code assistants
      };
    };

    # MCP Servers for AI tools
    mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
      servers.context7.apiKeyFile = "/run/secrets/context7-api-key";
    };

    # AI Coding Tools - Harmonized MCP configs (Droid, Claude, Crush, OpenCode)
    ai-coding-tools = {
      enable = true;
      zaiApiKeyFile = "/run/secrets/zai-api-key";
      context7ApiKeyFile = "/run/secrets/context7-api-key";
      tools.pi.packages = [
        "npm:pi-annotated-reply@0.4.1"
        "npm:pi-btw@0.2.1"
        "npm:pi-context@1.1.2"
        "npm:pi-lens@3.8.5"
        "npm:pi-powerline-footer@0.4.9"
        "npm:pi-rewind@0.5.0"
        "npm:pi-show-diffs@0.2.7"
        "npm:pi-subagents@0.12.4"
        "npm:pi-web-access@0.10.6"
        "npm:pi-worktree@1.3.3"
      ];
    };

    # WEB TESTING - Playwright/Puppeteer system dependencies
    web-testing.enable = true;

    # CI/CD - Self-hosted GitHub Actions runner
    ci-runner = {
      enable = false;
      repo = "username/nixos-config";
      autoStart = false;
    };

    # MULTIMEDIA - GStreamer support for Qt/KDE applications
    multimedia.gstreamer.enable = true;

    # Spotify with SpotX patch (ad-free, premium features)
    spotify-spotx = {
      enable = true;
      forceX11 = true;
      clearCacheOnPatch = true;
    };

    # FLATPAK - Flatpak support with Discover and Flathub
    flatpak-kde = {
      enable = true;
      autoUpdate = true;
    };

    # NOTE (2026-07-21, issue #300): GPU mining was migrated to the
    # peakminer K8s deployment long ago — see hosts/zephyr/peakminer.nix
    # and kubernetes/modules/profit-switcher.nix. The legacy
    # `services.mining` block (with Kryptex fallback pools) was held over
    # here as a no-op placeholder; per cluster-wide directional decision
    # the block is removed entirely. Cluster coordinate with peakminer
    # is handled exclusively through `services.mining-coordinator` below.

    # Vaultwarden - Self-hosted password manager with FIDO2/WebAuthn
    vaultwarden-module = {
      enable = true;
      hostName = "vaultwarden.zephyr.tigris-ule.ts.net"; # Tailscale Magic DNS
      dataDir = "/var/lib/vaultwarden";
    };

    # Syncthing P2P file sync for /etc/nixos config sync
    # NOTE (2026-07-21, issue #300): the previous `services` sub-attribute
    # (a hand-rolled list of `{ name, active }` service mesh entries) does
    # not exist as a declared option — `services.syncthing-cluster` only
    # exposes `enable` and `deviceId`. NF was silently passing through
    # until a recent bumps made it check declared options strictly. Strip.
    # Service-mesh topology tracking lives in services.nix comments.
    syncthing-cluster = {
      enable = true;
    };
  };
  # ============================================================================
  # PROGRAMS - SCOPEBUDDY, ANIME GAME LAUNCHERS, AI SERVICES
  # ============================================================================
  programs = {
    scopebuddy = {
      enable = true;
      autoDetect = {
        resolution = true;
        hdr = true;
        vrr = true;
      };
    };

    # Anime game launchers
    anime-game-launcher.enable = true;
    sleepy-launcher.enable = true;
    honkers-railway-launcher.enable = true;
    wavey-launcher.enable = true;

    # AI services
    stability-matrix.enable = true;
  };

  # Podman container runtime (for Spacebot)
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  # ============================================================================
  # AGENIX SECRETS - Centralized registry (2026-03-16 migration)
  # ============================================================================
  # All secrets managed via agenix-secrets-registry module
  # Categories: aiServices, monitoring, storage, mining, cloud, selfHosting
  # See: modules/system/agenix-secrets-registry.nix
  services.sops-secrets-registry = {
    enable = true;
    aiServices = true; # For autoresearch skill optimization (ANTHROPIC_API_KEY)
    monitoring = false; # No monitoring secrets currently needed (sentry-dsn removed with GlitchTip)
    storage = true; # Required for backup-to-garage service (S3 API key)
    mining = true;
    cloud = true;
    kubernetes = true; # k3s cluster token
    selfHosting = false; # These services run on other hosts
  };

  # Override specific secret permissions (registry defaults can be overridden)
  sops.secrets."cloud/cloudflared-token" = lib.mkForce {
    mode = "400";
    owner = "root";
    group = "root";
  };
  # Note: spacebot-telegram-token uses registry default (owner=j_kro)
  # because the hermes-agent service runs as user=j_kro

  # ============================================================================
  # AI INFERENCE SERVICE - Gateway with authentication and metrics
  # Gateway routes to various backends (ZAI, vLLM, llama.cpp, etc.)
  # Gateway: OpenAI-compatible API on port 8080
  # ============================================================================

  # ============================================================================
  # WEB TESTING - Playwright/Puppeteer system dependencies
  # Provides GTK libraries and fonts for Chromium-based browsers
  # ============================================================================

  # ============================================================================
  # CI/CD - Self-hosted GitHub Actions runner
  # ============================================================================
  # SETUP REQUIRED (one-time):
  #   sudo /etc/nixos/scripts/ci/setup-runner.sh owner/repo
  # After setup, set enable = true and autoStart = true below

  # ============================================================================
  # MINING - GPU Mining (RTX 3090)
  # DISABLED: Mining conflicts with AI inference services (LM Studio)
  # Note: profiles.role.mining enables services.mining automatically

  # ============================================================================
  # FLATPAK - Flatpak support with Discover and Flathub
  # ============================================================================

  # ============================================================================
  # PER-GPU POWER LIMITS
  # ============================================================================
  # NOTE: Power limits are now managed by the mining.nix module via
  # nvidia-gpu-power-limit.service using perGpuPowerLimits configuration.
  # The old gpu-0-power-limit and gpu-1-power-limit services have been
  # removed to avoid conflicts. Current limits: 3090 @ 250W (3060 Ti disabled).
  #
  # See: modules/mining/mining.nix -> nvidia-gpu-power-limit.service

  # Systems Intelligence Plasmoid - Cluster monitoring widget
  programs.systems-intelligence-plasmoid.enable = true;
  programs.systems-intelligence-plasmoid.prometheusUrl = "http://127.0.0.1:9090";
  programs.systems-intelligence-plasmoid.refreshInterval = 5000;
  programs.systems-intelligence-plasmoid.clusterNodes = "zephyr,nexus,forge,sentry";

  # LM Studio - Local LLM inference with GPU acceleration
  programs.lm-studio.enable = true;

  # Pi agent model registry (declarative models.json)
  # programs.pi-agent.enable = true;  # TODO: option not found — disabled for now

  # ============================================================================
  # MONITORING - Full monitoring stack
  # ============================================================================

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  # Base Tailscale configuration provided by node-profiles.zephyr-workstation
  # No additional network profile configuration needed

  # ============================================================================
  # ADDITIONAL PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    # Shell & CLI
    fish
    zoxide
    fzf
    eza
    btop

    # Version control
    tmux
    mosh
    git

    # Networking
    tailscale
    networkmanager
    dbus-broker
    slirp4netns # Required for Spacebot/Podman networking
    podman-compose # Docker Compose compatibility for Podman
    localsend # Local network file sharing (AirDrop alternative)

    # Deployment
    inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena
    (pkgs.writeShellScriptBin "spacebot" ''
      #!${pkgs.bash}/bin/bash
      # Spacebot CLI wrapper - connects to local Spacebot service
      exec ${pkgs.curl}/bin/curl --data-binary @- http://127.0.0.1:19898/api/run "$@"
    '')

    # Hardware monitoring & fan control helpers
    ddcutil # DDC/CI monitor brightness control
    (pkgs.writeShellScriptBin "fan-set" ''
      #!${pkgs.bash}/bin/bash
      # Set fan speed (0-255) for a specific fan
      # Usage: fan-set <fan_number> <pwm_value>
      # Example: fan-set 1 128 (sets fan 1 to 50%)
      if [ "$#" -ne 2 ]; then
        echo "Usage: fan-set <fan_number> <pwm_value (0-255)>"
        echo "Example: fan-set 1 128  # Set fan 1 to 50%"
        exit 1
      fi
      fan=$1
      pwm=$2
      pwm_file="/sys/class/hwmon/hwmon6/pwm$fan"
      if [ ! -w "$pwm_file" ]; then
        echo "Error: Cannot write to $pwm_file"
        echo "You may need to disable BIOS fan control first"
        exit 1
      fi
      echo "$pwm" > "$pwm_file"
      echo "Set fan $fan to PWM $pwm ($(awk "BEGIN {printf \"%.0f\", $pwm/255*100}")%)"
    '')

    (pkgs.writeShellScriptBin "fan-get" ''
      #!${pkgs.bash}/bin/bash
      # Get current fan speed and PWM for all fans
      echo "Fan Status for MSI X570 TOMAHAWK:"
      echo "────────────────────────────────────────"
      for i in 1 2 3 4 5 6 7; do
        pwm_file="/sys/class/hwmon/hwmon6/pwm''$i"
        rpm_file="/sys/class/hwmon/hwmon6/fan''${i}_input"
        label_file="/sys/class/hwmon/hwmon6/fan''${i}_label"
        if [ -f "$pwm_file" ]; then
          pwm=$(cat "$pwm_file" 2>/dev/null || echo "N/A")
          rpm=$(cat "$rpm_file" 2>/dev/null || echo "0")
          label="Fan ''$i"
          [ -f "$label_file" ] && label=$(cat "$label_file")
          percent=$(awk "BEGIN {printf \"%.0f\", $pwm/255*100}")
          printf "%-12s: %4d RPM  PWM: %3d (%3s%%)\n" "$label" "$rpm" "$pwm" "$percent"
        fi
      done
    '')

    (pkgs.writeShellScriptBin "temp-get" ''
      #!${pkgs.bash}/bin/bash
      # Get all temperature readings
      echo "Temperature Readings:"
      echo "────────────────────"
      # AMD CPU temps
      echo "AMD CPU (k10temp):"
      ${pkgs.lm_sensors}/bin/sensors -j k10temp-pci-00c3 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors k10temp-pci-00c3
      echo ""
      # Motherboard temps
      echo "Motherboard (NCT6775):"
      ${pkgs.lm_sensors}/bin/sensors -j nct6797-isa-0a20 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("temp")) | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors nct6797-isa-0a20 | grep -E "SYSTIN|CPUTIN|TSI"
      echo ""
      # NVMe temps
      echo "NVMe Drives:"
      ${pkgs.lm_sensors}/bin/sensors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("nvme")) | "  \(.key): \(.value[\"Composite\"].value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors | grep -A2 nvme
    '')

    (pkgs.writeShellScriptBin "sys-mon" ''
      #!${pkgs.bash}/bin/bash
      # Comprehensive system monitoring dashboard
      exec /etc/nixos/scripts/monitor-sensors.sh
    '')

    (pkgs.writeShellScriptBin "aio-status" ''
      #!${pkgs.bash}/bin/bash
      # Corsair AIO cooler status
      exec /etc/nixos/scripts/corsair-status.sh
    '')

    (pkgs.writeShellScriptBin "corsair-rgb" ''
      #!${pkgs.bash}/bin/bash
      # Start OpenRGB GUI for Corsair RGB control
      exec /etc/nixos/scripts/corsair-rgb
    '')

    (pkgs.writeShellScriptBin "corsair-rgb-server" ''
      #!${pkgs.bash}/bin/bash
      # Start OpenRGB server for programmatic RGB control
      exec /etc/nixos/scripts/corsair-rgb-server
    '')

    # Network discovery & mapping
    nmap
    netdiscover
    arp-scan
    iproute2 # ip, ss, route commands
    iputils # ping, traceroute
    dnsutils # dig, nslookup
    whois
    net-tools # arp, ifconfig, route

    # Development
    nodejs
    gh
    jq
    inputs.claude-native.packages.x86_64-linux.claude

    # AI & ML
    llama-cpp
    whisper-cpp
    pipx
    pkgs.python312Packages.huggingface-hub # HF CLI: hf download/upload/login
    opencode # AI coding agent (terminal-based)

    # Mining (manual only, no auto-start)

    # Desktop
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
    telegram-desktop

    # Network automation - for switch/modem configuration scripts
    python3Packages.playwright

    # Diagrams & data
    mermaid-cli # Mermaid → SVG/PNG
    graphviz # Graphviz (dot) diagrams
    python312Packages.openpyxl # Excel read/write
  ];

  # ============================================================================
  # MULTI-GPU ENVIRONMENT VARIABLES - RTX 3090 + 3060 Ti
  # ============================================================================
  environment.sessionVariables = {
    # GPU visibility
    CUDA_VISIBLE_DEVICES = "0,1";

    # NCCL (NVIDIA Collective Communications Library) settings
    NCCL_P2P_LEVEL = "2"; # PCIe bridge level (P2P limited on heterogeneous GPUs)
    NCCL_P2P_DISABLE = "0"; # Try P2P first, disable if issues occur
    NCCL_IB_DISABLE = "1"; # Disable InfiniBand (not applicable)
    NCCL_ALGO = "Tree"; # Tree algorithm for multi-GPU communication

    # llama.cpp/llama-cpp CUDA settings
    GGML_CUDA_ENABLE_UNIFIED_MEMORY = "1"; # Critical for heterogeneous GPU support
    GGML_CUDA_GPU_MEMORY_FRACTION = "0.9"; # Use 90% of GPU VRAM (leave headroom)
    LLAMA_GRAPH_POOL_SIZE = "0.2"; # CUDA Graphs pool (20% of VRAM)
    # KV cache quantization (Q4_0) is configured per-model in backend
  };

  # ============================================================================

  # ============================================================================

  # ============================================================================

  # ============================================================================

  # LLAMA-SERVER - Local LLM inference for autoresearch
  # ============================================================================

  # ============================================================================
  # SWAP - Using 32GB partition on nvme0n1p1 (configured in hardware-configuration.nix)
  # ============================================================================
  # Previous 8GB swapfile removed to use partition instead (2026-03-25)
  # Partition UUID: b733be92-f327-4613-9530-a5380ed77216

  # ============================================================================
  # SYSTEM STATE
  # ============================================================================
  system.stateVersion = "26.05";

  # ============================================================================
  # CRASH DETECTION
  # ============================================================================
  # Enable crash watchdog to detect and log system crashes
  # Configured in services block above

  # ============================================================================
  # BACKUP TO GARAGE S3
  # ============================================================================
  # Automated daily backups to Garage S3 cluster (runs at 2 AM)
  # Configured in services block above

  # ============================================================================
  # NVIDIA CDI GENERATOR FIX
  # ============================================================================
  # ============================================================================
  # UNBOUND DNS WITH DNS-OVER-TLS
  # ============================================================================
  # Local recursive DNS resolver with DNS-over-TLS to Cloudflare, Google, Quad9
  # Accessible on localhost for local applications and cluster network
  # Survives NixOS rebuilds without restart (restartIfChanged = false)
  services.unbound-common.enable = true;

  # Resolve K8s ingress hostnames to the cluster VIP (10.1.1.100)
  # Local DNS records are in modules/services/unbound-common.nix (shared
  # across all hosts). Fallback /etc/hosts entries below.

  networking.extraHosts = lib.mkOptionDefault ''
    10.1.1.100 search.lan search.cluster.local
    10.1.1.100 ai.lan ai.cluster.local
    10.1.1.100 openwebui.lan openwebui.cluster.local
    10.1.1.100 civicintel.lan civicintel.cluster.local
  '';

  # ============================================================================
  # CLAUDE CODE ROUTER - Route Claude Code to Z.AI GLM models
  # ============================================================================
  services.claude-code-router = {
    enable = true;
    port = 3456;
    openFirewall = false; # Localhost only
    zai = {
      apiKeyFile = "/run/secrets/zai-api-key";
      defaultModel = "glm-4.7";
      thinkModel = "glm-4.7";
    };
  };
}
# Force rebuild - Thu 12 Mar 2026 09:59:02 PM UTC
# Refactored 2026-07-21 (#300): scrubbed pre-peakminer mining residue, repaired
# orphan syntax from prior xmrig-strip cleanup.
