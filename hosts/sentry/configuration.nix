# Sentry Host Configuration - Monitoring Server
# 10.1.1.140 - 16 cores, RX 5600 XT
# Features: Gaming only (no VR), CPU mining, Vulkan (ROCm disabled 2026-08-06)
#
# Module imports: Gaming, mining, monitoring, opencode are already imported
# via commonModules in flake.nix (./modules/default.nix)
# Gaming module is used here for Plasma desktop gaming optimizations
{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # GitHub Actions runners (site-agency + nixos-config) — imported 2026-08-14
    # (was dead code; sentry had no runner, site-agency CI queued forever).
    ./services.nix

    # All other modules (desktop, gaming, networking, services, etc.)
    ../../modules/default.nix

    # Kubernetes
    ../../modules/services/k3s-cluster.nix
    # Keepalived VIP for HA API server access
    ../../modules/services/keepalived-vip.nix

    # Storage assertions (partlabel/uuid/boot checks)
    ../../modules/system/storage-assertions.nix

    # SecretSpec Phase 4 credential provisioning
    ../../modules/system/secretspec-creds.nix
    ../../modules/system/secretspec-validator.nix

    # Persistence (impermanence via preservation module). Previously UNIMPORTED,
    # so /etc/ssh + age keys rotated on every rebuild (sentry host key was
    # hand-rotated in ssh.nix:121 after a rebuild). Importing activates the
    # /persistent symlinks below.
    ./preservation.nix

    # Bonsai 27B local inference (1-bit Q1_0 on AMD RX 5600 XT via Vulkan)
    ../../modules/services/bonsai.nix
    # llama-swap cluster: llama-swap across the board (unified turboquant binary)
    ../../modules/services/llama-swap-cluster.nix
    # GPU workload registry: single source for the fuzzel menu (workloads.json)
    ../../modules/services/gpu-workload-registry.nix
  ];

  # ============================================================================
  # DESKTOP — disabled for minimal headless recovery
  # ============================================================================

  # CopyQ is a GUI clipboard manager (Qt6). Sentry is headless (no sddm,
  # no graphical-session.target), so CopyQ never runs — and pkgs.copyq pulls
  # pyside6 → qtwebengine, which forces a multi-hour Chromium source build on
  # every deploy. Disable it here; desktop hosts keep it via mkDefault in the
  # standalone Layer-2 flake (home-manager-config/modules/standalone.nix).
  # home-manager.users.j_kro.programs.copyq.enable = lib.mkForce false;

  # Telegram Desktop is a Qt6 GUI app (pulls pyside6 -> qtwebengine, a
  # multi-hour Chromium source build). Sentry is headless — no GUI sessions.
  # home-manager.users.j_kro.programs.opencode.telegramDesktop = lib.mkForce false;

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  clusterNetworking = {
    enable = true;
    hostName = "sentry";
    ipAddress = "10.1.1.140";
    interfaceName = "enp7s0";
    wireless.enable = false;
    unbound.listenAddress = "10.1.1.140";
  };

  # Directly disable the systemd timer (blocking rebuilds)

  # Populate /etc/hosts from central cluster configuration
  networking = {
    # Kubernetes worker firewall rules
    firewall = {
      # mkForce: the plain mkOptionDefault list was silently dropping to [22]
      # in the dendritic eval (2026-08-14) — 10250/3100/3900/3901/9100/9900
      # never merged; only ssh's [22] survived. Forcing the full list.
      allowedTCPPorts = lib.mkForce [
        22
        10250
        3100
        3900
        3901
        9100 # Prometheus node-exporter
        9900 # Hermes A2A gateway (hermes-sentry agent card + calls)
      ]; # SSH + Kubelet API + Loki + Garage + A2A (merges with cluster defaults)
      allowedTCPPortRanges = lib.mkOptionDefault [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472 # VXLAN (Calico)
      ];
      # Open Loki port on main interface for cluster access (module only opens on tailscale0)
      interfaces."enp7s0".allowedTCPPorts = [3100];
    };
  };

  # ============================================================================
  # NODE PROFILE - Platform-level defaults
  # ============================================================================
  # This profile bundles role profiles, Kubernetes config, hardware profiles,
  # and networking configuration. Eliminates ~100 lines of duplication.
  profiles.node.sentry-monitoring.enable = true;
  # Mining role disabled — mining module removed with compute-market purge
  profiles.role.mining = lib.mkForce false;

  # ============================================================================
  # GPU COMPUTE - Vulkan support for AI inference
  # ============================================================================
  # 2026-08-06: ROCm fully disabled. Removes rocm.enable (drops the gpu=amd
  # k8s node label), the rocmPackages from the closure, and the profile's
  # OpenCL-via-ROCm (amdgpu.opencl) which pulled rocmPackages.clr into
  # hardware.graphics.extraPackages. Inference is Vulkan (RADV) only.
  # Re-enable if ROCm/HIP compute returns.
  hardware.gpu-compute = {
    enable = true;
    vulkan.enable = true;
  };
  # Kill the amdgpu profile's OpenCL enable (would re-add rocmPackages.clr
  # via hardware.graphics.extraPackages).
  hardware.amdgpu.opencl.enable = lib.mkForce false;

  # ============================================================================
  # SERVICES - All service configurations
  # ============================================================================
  services = {
    # Hermes A2A mesh node: config.yaml sections (providers/a2a peers/gateway
    # platform) rendered from Nix by hermes-config-emit. Peers are shared via
    # services.hermes-a2a (single source of truth in hermes-a2a-mesh.nix).
    hermes-cli = {
      enable = true;
      user = "j_kro";
      managedConfig = true;
    };
    hermes-a2a.enable = true;

    k3s-cluster = {
      enable = true;
      role = "server";
      clusterInit = false;
      # 2026-08-16: sentry rejoins the nexus cluster as a SERVER (control
      # plane + etcd) for 3-node HA. Previously agent: the 2026-08-08 nexus
      # recovery demoted sentry to agent to avoid the flannel-backend
      # mismatch, but that left a 2-server etcd with zero fault tolerance
      # (both nexus AND forge had to be up for quorum — the 2026-08-16 outage
      # when forge lost its k3s token). The k3s-cluster module now passes
      # --flannel-backend=none on every server, so a joining server no longer
      # disagrees with the initialized datastore. Direct nexus address avoids
      # the keepalived VIP deadlock (sentry holds VIP 10.1.1.100 but its k3s
      # was down — the VIP routed kubectl to a dead API server).
      serverAddr = "https://10.1.1.120:6443";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = "10.1.1.140";
      # At-rest encryption key MUST match the cluster (nexus/forge share it).
      # The same field in services.nix is dead code — that file is not
      # imported by configuration.nix; only comments reference it.
      secretsEncryptionKeyFile = "/run/secrets/k3s-encryption-key";
      calico.enable = true;
      # wipeState=false: never persist a wipe flag in config (one-shot only,
      # removed immediately after use; a persisted wipe destroys the cluster
      # on every subsequent boot). The 2026-08-13 recovery wiped sentry's
      # stale standalone-etcd (from the 2026-08-11 nexus outage pivot) so it
      # could rejoin nexus's HA etcd; the wipe has completed and sentry is
      # now a healthy member, so this is back to false.
      wipeState = false;

      # 2026-07-28: the FATAL "stat .../cred/supervisor.kubeconfig: no such
      # file or directory" on activation is fixed at a different layer:
      # the etcdClean=true previously in hosts/sentry/services.nix wiped the
      # k3s state on every activation; the real remediation there is the
      # mkForce false we just applied. Note: there is no declared
      # `services.k3s-cluster.secretsEncryptionKeyFile` option in nixpkgs'
      # upstream k3s module — the dormant field in services.nix (set but
      # never evaluated because enable=false) was vestigial.
    };

    # Auto-apply K8s manifests on boot (control-plane only; sentry is a
    # server now — keep disabled; manifests apply from nexus, the primary).
    k8s-manifest-autoapply.enable = false;

    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      # 2026-07-28: changed from "enp7s0" → "eth0" (predictable-name change after
      # 26.11 kernel upgrade). Sentry's actual NIC is eth0; the keepalived
      # service was failing on activation because the generated conf pointed
      # at a non-existent interface.
      interface = "eth0";
      priority = 90;
    };

    # KUBERNETES - k3s control plane (joins existing cluster)
    # Joins nexus (bootstrap) via VIP for HA

    # Auto-apply K8s manifests on boot (control-plane node)

    # Bonsai 27B: 1-bit Vulkan (port 8003)
    # Keepalived VIP for HA API server access

    # Host Dashboard - Web interface for cluster host status
    host-dashboard = {
      enable = true;
      role = "control-plane + monitoring";
      port = 8090;
      prometheusUrl = "http://127.0.0.1:9090";
      featuredServices = [
        {
          name = "Prometheus";
          url = "http://127.0.0.1:9090";
        }
        {
          name = "Grafana";
          url = "http://127.0.0.1:3000";
        }
        {
          name = "Loki";
          url = "http://127.0.0.1:3100";
        }
      ];
      services = [
        {
          name = "kubelet";
          active = true;
        }
        {
          name = "containerd";
          active = true;
        }
        {
          name = "cfssl";
          active = true;
        }
        {
          name = "keepalived";
          active = true;
        }
        {
          name = "k3s-server";
          active = true;
        }
      ];
    };
  };

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  # Base profiles provided by node-profiles.sentry-monitoring:
  # - amd.zen, amdgpu.enable, amdgpu.wayland, monitoring.enable
  #
  # Sentry-specific hardware additions:
  hardware = {
    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

    # Hardware monitoring extras (not covered by profile)
    monitoring = {
      autoDetect = false; # Disabled: sensors-detect path issues
      fanControl = false; # BIOS fan control for now
    };
  };

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  # Base role profiles provided by node-profiles.sentry-monitoring:
  # - mining, aiInference
  # Kubernetes and networking also handled by node profile
  #
  # No additional role profiles needed - all handled by node profile

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  # Base Tailscale configuration provided by node-profiles.sentry-monitoring
  # No additional network profile configuration needed

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================
  services = {
    # Crash detection and logging
    # services.crash-watchdog.enable = true; # Module not available yet

    # Compute Workload Monitor - Pause mining during builds/gaming
    # Modular workload monitoring (replaces old compute-workload-monitor monolith)
    gaming-detection.enable = false;
    gpu-profile-manager.enable = false;
    mining-coordinator.enable = false;

    # Nginx - Lightweight static file server
    nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedGzipSettings = true;

      virtualHosts."_" = {
        default = true;
        locations."= /".return = "200 'OK'";
        locations."= /".extraConfig = ''
          add_header Content-Type text/plain;
        '';
      };
    };

    xserver.videoDrivers = ["amdgpu"];

    # MINING (CPU only - 4 threads = 25% of 16 cores)
    # Note: profiles.role.mining enables services.mining automatically
    # Sentry: CPU mining DISABLED - K8s deployment scaled to 0/0
    # RX 5600 XT reserved for AI inference (llamafile ROCm)
    mining = {
    };
    # AMD GPU (RX 5600 XT) - DISABLED for AI inference
    # Sentry should only CPU mine, GPU reserved for llamafile (ROCm)
    #   enable = true;
    #   amd = {
    #     enable = true;
    #     autostart = true;
    #     devices = "0"; # RX 5600 XT (single AMD GPU)
    #     powerLimit = 140; # Safe power limit for RX 5600 XT
    #     apiPort = 4069;
    #   };
    #   pool = "10.1.1.110:3334";
    #   wallet = "krxXVNVMM7.sentry-gpu";
    #   pools = [
    #     {
    #       url = "10.1.1.110:3334"; # gpu-proxy on Zephyr
    #       wallet = "krxXVNVMM7.sentry-gpu";
    #       password = "x";
    #       tls = false;
    #     }
    #     {
    #       url = "xtm-c29-us.kryptex.network:8040"; # Direct Kryptex US (failover)
    #       wallet = "krxXVNVMM7.sentry-gpu";
    #       password = "x";
    #       tls = true;
    #     }
    #     {
    #       url = "xtm-c29-eu.kryptex.network:8040"; # Direct Kryptex EU (failover)
    #       wallet = "krxXVNVMM7.sentry-gpu";
    #       password = "x";

    # TAILSCALE
    tailscale.enable = true;

    # Encrypted cross-session memory backend (Hermes MCP points MEMLAWB_URL
    # here). Runs the memlawb fs-store server on :8080. Interim: app is the
    # /persistent/memlawb git checkout until memlawb is Nix-packaged.
    memlawb-server.enable = true;

    # Mount /etc/nixos from zephyr (single-source-of-truth)

    # Garage S3 disabled - using nexus as primary storage node
    # Access Garage S3 at: http://10.1.120:3900
    # Note: /storage/garage directory still exists for local use
    garage-cluster.enable = false;

    # Hermes Agent module removed (2026-04-06)
  };

  # ============================================================================
  # BOOTLOADER CONFIGURATION
  # ============================================================================
  # Moved from hardware-configuration.nix for centralized config
  # Base bootloader settings provided by common-host-defaults.nix:
  # - systemd-boot.enable, efi.canTouchEfiVariables, kernelPackages (linux_zen)
  # NOTE: Using CachyOS kernel — binary cached, x86-64-v3 optimized, BORE scheduler.
  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;
  boot.loader.timeout = lib.mkDefault 5;

  boot.kernelParams = lib.mkAfter [
    "hugepagesz=1G"
    "hugepages=3"
    # Override conflicting panic values — ensure 30s for journald flush on crash
    "panic=30"
    # 2026-07-28: Zen 1 (Ryzen 7 1700) hard-lockup mitigation. The earlier
    # override of "=5" here was last-wins in the kernel cmdline, UNDOING the
    # fleet's processor.max_cstate=1 mitigation in modules/system/kernel-hardening.nix.
    # CachyOS 7.1.3's aggressive C-state entry exposes the well-known Zen 1
    # C6 deep-sleep lockup, which the softlockup_panic=1 + nmi_watchdog=1 floor
    # then panics on (matching the recurring Mut-Jul / Jul-25 / today crash loop).
    # lib.mkAfter ensures this is the LAST max_cstate entry in the cmdline
    # (kernel uses last-wins for duplicates), definitively locking C6 out.
    "processor.max_cstate=1"
    # Do NOT panic on kernel oops — k3s nftables cleanup segfaults trigger oops,
    # and MCE Bank 5 errors on Ryzen are non-fatal. panic_on_oops=1 overrides this
    # from kernel-hardening.nix; put ours last so the kernel uses it.
    "panic_on_oops=0"
  ];

  # 2026-08-06: ROCm fully disabled — /opt/rocm symlinks removed with the
  # ROCm packages. Re-add the rocmEnv symlinkJoin if ROCm returns.
  systemd.tmpfiles.rules = [
    # Clean old etcd data directory before starting (NixOS-managed cleanup)
    "R /var/lib/etcd - - - - -"
  ];

  # ============================================================================
  # SECONDARY STORAGE (sda - 1TB SSD)
  # Defined in hardware-configuration.nix with subvol=@data
  # ============================================================================

  # Host-specific Tailscale override: Sentry advertises subnet routes (backup gateway)
  # This overrides the base Tailscale configuration from node profile
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  programs = {
    # 2026-08-06: ROCm fully disabled — no rocmPackages referenced here
    # (clr/clr.icd/rocminfo/rocm-smi/rocm-runtime removed with the math stack;
    # amdgpu.opencl is also mkForce'd off so graphics.extraPackages stays clean).
    nix-ld.libraries = with pkgs; [
      # OpenCL
      ocl-icd
      opencl-headers
      clinfo

      # System libraries
      zlib
      libpng
      libjpeg
      freetype
      fontconfig
      libx11
      libxext
      libxrender
      libxcb
      libxau
      libxdmcp
      SDL2
      alsa-lib
      systemd
      libusb1
      curl
      openssl
    ];

    # Git configuration now provided by common-host-defaults.nix
    # Sentry-specific git remote override (if needed):
    # programs.git.config.remote.origin.url = "git@github.com:reverb256/nixos-config.git";
  };

  # ============================================================================
  # SECURITY
  # ============================================================================
  # Sentry trusts the canonical repository CA but does not own the signing key
  # or mint ingress leaves.
  services.cluster-ca = {
    enable = true;
    generateLeaf = false;
  };

  # Disable autologin — sentry is k3s server, not interactive desktop
  services.displayManager.autoLogin.enable = lib.mkForce false;
  # ============================================================================
  # AGENIX SECRETS
  # ============================================================================
  # Centralized registry - see modules/system/agenix-secrets-registry.nix
  # SecretSpec creds provisioning (replaces sops-nix)
  services.secretspec-creds = {
    enable = true;
    secrets = import ./secretspec-creds-wiring.nix;
  };

  services.secretspec-validator = {
    enable = true;
    production = true;
    failOnMissing = true;
  };

  # Override specific secret permissions for mining service
  # ============================================================================
  # LLAMAFILE - LLM INFERENCE SERVICE (AMD RX 5600 XT - Vulkan)
  # ============================================================================
  # TEMPORARILY DISABLED: llama-cpp-rocm build failing
  # Re-enable after nixpkgs update or switch to CPU/Vulkan backend
  services.llamafile = {
    enable = false;
    # modelPath = "/home/j_kro/.lmstudio/models/unsloth/Qwen3.5-2B-GGUF/Qwen3.5-2B-IQ4_NL.gguf";
    # host = "0.0.0.0";
    # port = 8086;
    # gpu = "rocm";
    # gpuLayers = 999;
    # ctxSize = 16384;
    # threads = 8;
    # batchSize = 512;
    # ubatchSize = 512;
    # flashAttention = false;
    # enableThinking = false;
    # reasoningBudget = 0;
    # cacheTypeK = "bf16";
    # cacheTypeV = "bf16";
  };
  services.storage-assertions.enable = true;
  services.thermal-monitor.enable = true;
  # Cross-fleet read-only CPU thermal watchdog: alerts at 90C warn / 95C crit.

  # ── 2026-07-28 sentry boot-error fixes ──────────────────────────────────
  # Enable kdump so the next kernel panic leaves a /var/crash/* dmesg trace.
  # Previous Zen 1 lockups vanished into the cold-reboot ring-buffer flush,
  # leaving no forensic record. boot.kexecLikeResume is the runtime hook so
  # the kdump kernel can hot-reload on panic signal.
  # 2026-07-28: services.kdump + boot.kexecLikeResume aren't declared in
  # the current Nixpkgs pin (9ae611a455b90cf061d8f332b977e387bda8e1ca).
  # The C-state fix above (processor.max_cstate=1) is the actual mitigation
  # for the recurring Zen 1 hard-lockup panics on sentry; kdump was
  # supplementary but isn't blocking deploy.
  # Sentry is a headless Vulkan AI inference box + k3s control-plane node.
  # The CUPS subsystem currently logs "HP-Envy-7800: Unable to connect to
  # 10.1.1.173:631: Host is down" on every boot and tries to register an
  # airscan device — both useless here. modules/system/boot-error-fixes.nix
  # force-mirrors services.printing.enable from this includePrinting flag.
  services.boot-error-fixes.includePrinting = lib.mkForce false;
  # SDDM greeter NULL-derefs at every boot (sddm-helper-sta segfault at 0, core-dumped).
  # Sentry has no interactive Wayland session attached (no keyboard/monitor);
  # suppress the greeter entirely. Other hosts that need a desktop keep the
  # default.
  services.displayManager.sddm.enable = lib.mkForce false;
  # alertmanager currently fails start: it tries to gossip-join a cluster
  # mesh despite listenAddress=127.0.0.1 having no private IP for cluster
  # advertise. Sentry runs solo. Disable clustering so the unit emits the
  # indep-listen and exits gracefully instead of looping on start-limit-hit.
  services.prometheus.alertmanager.extraFlags = [
    "--cluster.listen-address="
  ];

  # ----------------------------------------------------------------------------
  # BONSAI 27B 1-bit on AMD RX 5600 XT via Vulkan (mainline llama-cpp-b9048).
  # 2026-08-16: weights moved to /storage/models (HDD, 896G free) — the SSD
  # was at 91% and kubelet image GC was failing. /storage is the 1TB HDD.
  # ICD path forced in the module so RADV is found without the system icd.d symlink.
  # ----------------------------------------------------------------------------
  services.bonsai = {
    enable = true;
    # Mainline llama.cpp with Vulkan + CUDA disabled (module default).
    # Weights live at /storage/models (HDD) — see comment above.
    onebitModel = "/storage/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
  };

  # llama-swap across the board: swappable OpenAI-style endpoint on the GPU.
  services.llama-swap-cluster.enable = true;
}
