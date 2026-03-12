# Distributed Build Configuration
# Enables building across all 4 nodes in the cluster
# See AGENTS.md for cluster architecture details
#
# COMPUTE WORKLOAD MONITOR INTEGRATION (2026-03-09):
#   Build detection is automatic via compute-workload-monitor:
#   - Detects: nixos-rebuild, colmena, nix-build, gcc, clang, cargo, cmake, make, ninja
#   - Action: Pauses ALL mining (GPU + CPU) during builds for maximum build performance
#   - Resumes: Automatically when build processes complete
#
# HOST PARTICIPATION (K8s-aware v3):
#   zephyr: ✅ Enabled (32 cores, 31GB RAM, znver3)  → Control plane, conservative builds
#   nexus:  ✅ Enabled (24 cores, 46GB RAM, znver2)  → Storage worker, NFS headroom
#   forge:  ✅ Enabled (6 cores, 15GB RAM, skylake)   → Mixed GPU worker, minimal builds
#   sentry: ✅ Enabled (16 cores, 31GB RAM, znver1)  → Monitoring worker, light builds
#
# NETWORK: 1Gbps with 4x TP-Link Easy Smart switches
#
# SELF-EXCLUSION FIX (2026-03-10):
#   Each host must NOT list itself as a builder to avoid SSH-to-self loopback
#   which causes nix-daemon lock contention (multiple daemons competing for same store)
{lib, config, ...}: let
  # Current hostname for self-exclusion
  currentHost = config.networking.hostName or "unknown";
in {
  # ============================================================================
  # DISTRIBUTED BUILD CONFIGURATION
  # ============================================================================
  nix = {
    # Enabled: Distributed builds across the cluster
    distributedBuilds = lib.mkDefault true;

    # Build machines configuration (K8s-aware v3 with CPU microarchitecture tuning)
    # REFERENCE: /etc/nixos/machines.nix (Colmena machinesFile)
    # NOTE: sshUser defaults to root when running with sudo, must specify j_kro
    # All 4 hosts participate with compute-workload-monitor managing mining pause
    # IMPORTANT: Filter out current host to avoid SSH-to-self loopback causing daemon locks
    # TEMPORARILY DISABLED: Fixing deployment issue - will re-enable after deployment
    # buildMachines = lib.filter (m: m.hostName != currentHost) [
    #   {
    #     # Zephyr: 32 cores, Ryzen 9 5950X (znver3)
    #     # Role: K8s control plane + build coordinator + worker
    #     # K8s-AWARE: Conservative maxJobs (apiserver/etcd need CPU)
    #     hostName = "zephyr";
    #     system = "x86_64-linux";
    #     sshUser = "j_kro";
    #     protocol = "ssh-ng";
    #     maxJobs = 8; # CONSERVATIVE - apiserver/etcd need CPU headroom
    #     speedFactor = 8; # Fast (Zen 3), but not prioritized over K8s stability
    #     supportedFeatures = ["kvm" "big-parallel"];
    #     mandatoryFeatures = [];
    #   }
    #   {
    #     # Nexus: 24 cores, Ryzen 9 3900X (znver2)
    #     # Role: K8s storage worker + NFS server
    #     # K8s-AWARE: Moderate maxJobs for NFS/PVC I/O headroom
    #     hostName = "nexus";
    #     system = "x86_64-linux";
    #     sshUser = "j_kro";
    #     protocol = "ssh-ng";
    #     maxJobs = 6; # MODERATE - leave cores for NFS/PVC operations
    #     speedFactor = 5;
    #     supportedFeatures = ["big-parallel"];
    #     mandatoryFeatures = [];
    #   }
    #   {
    #     # Forge: 6 cores, i5-9500 (skylake, Coffee Lake)
    #     # Role: K8s multi-GPU worker (MIXED NVIDIA/AMD)
    #     # K8s-AWARE: Minimal maxJobs - GPU pods need CPU, mixed vendor = chaos
    #     hostName = "forge";
    #     system = "x86_64-linux";
    #     sshUser = "j_kro";
    #     protocol = "ssh-ng";
    #     maxJobs = 2; # MINIMAL - GPU pods need CPU more than builds
    #     speedFactor = 2; # Deprioritized - GPUs matter more than builds
    #     supportedFeatures = ["kvm"]; # No big-parallel - keep resources for GPU
    #     mandatoryFeatures = [];
    #   }
    #   {
    #     # Sentry: 16 cores, Ryzen 7 1700 (znver1)
    #     # Role: K8s monitoring worker + AMD GPU
    #     # K8s-AWARE: Light maxJobs - Prometheus/Grafana/Loki need CPU
    #     hostName = "sentry";
    #     system = "x86_64-linux";
    #     sshUser = "j_kro";
    #     protocol = "ssh-ng";
    #     maxJobs = 4; # LIGHT - monitoring stack needs CPU headroom
    #     speedFactor = 4;
    #     supportedFeatures = ["big-parallel"];
    #     mandatoryFeatures = [];
    #   }
    # ];

    # Settings for distributed builds
    settings = {
      # Note: buildMachines automatically configures builders via /etc/nix/machines
      # The ssh-ng protocol is used for efficient remote builds

      # Use substituters on remote builders (download from cache instead of copying)
      builders-use-substitutes = true;

      # Binary cache configuration (1Gbps network - fast downloads)
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        # "https://cache.nixos-cuda.org" # TEMPORARILY DISABLED - connectivity issues
        "https://nix-gaming.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        # "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
      ];

      # Maximum number of parallel build jobs (LOCAL builds on this host)
      # Per-host allocation based on core count and workload:
      # - Zephyr: 24 of 32 cores (75%) - control plane needs headroom
      # - Nexus: 18 of 24 cores (75%) - NFS/storage needs headroom
      # - Sentry: 12 of 16 cores (75%) - monitoring stack needs headroom
      # - Forge: 4 of 6 cores (67%) - GPU workloads need CPU
      # compute-workload-monitor pauses mining during builds
      max-jobs = lib.mkMerge [
        (lib.mkIf (currentHost == "zephyr") 24)  # 32 cores, K8s control plane
        (lib.mkIf (currentHost == "nexus") 18)   # 24 cores, NFS/storage
        (lib.mkIf (currentHost == "sentry") 12)  # 16 cores, monitoring
        (lib.mkIf (currentHost == "forge") 4)    # 6 cores, GPU workloads
        (lib.mkDefault 4) # Safe fallback for unknown hosts
      ];

      # Network optimization (1Gbps networking with TP-Link Easy Smart switches)
      http-connections = 100; # More parallel downloads (1Gbps can handle it)
      connect-timeout = 30;
      max-silent-time = 3600; # Kill stuck builds after 1 hour

      # Build logging and debugging
      keep-build-log = true;
      log-lines = 2000;
    };
  };

  # ============================================================================
  # SSH AGENT CONFIGURATION
  # ============================================================================
  programs.ssh.startAgent = true;

  # Ensure SSH directories exist with correct permissions
  systemd.tmpfiles.rules = [
    "d /home/j_kro/.ssh 0700 j_kro users -"
    "d /root/.ssh 0700 root root -"
  ];

  # SSH config for root (nix-daemon) to use for distributed builds
  environment.etc."ssh/ssh_config.d/50-build-machines.conf".text = ''
    Host zephyr nexus forge sentry
      User j_kro
      IdentityFile /root/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
      ConnectTimeout 30
  '';

  # SSH client configuration for user sessions is managed by modules/ssh.nix

  # ============================================================================
  # BUILD OPTIMIZATION
  # ============================================================================
  # Enable automatic GC to prevent disk space issues on builders
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Optimize store after builds
  nix.settings.auto-optimise-store = true;
}
