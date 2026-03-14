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
# HOST PARTICIPATION (v3 migration - conservative to prevent OOM):
#   zephyr: ✅ Server (32 cores, 31GB RAM, znver3)  → Control plane, conservative builds
#   nexus:  ✅ Server (24 cores, 46GB RAM, znver2)  → Storage worker, conservative builds
#   forge:  ❌ Client only (6 cores, 15GB RAM)      → GPU worker, no remote builds
#   sentry: ✅ Server (16 cores, 31GB RAM, Zen 1)   → Monitoring worker, conservative builds

# V3 MIGRATION NOTE: Using max-jobs=2, cores=2 on all nodes to prevent OOM
# during heavy v3 compilation. After migration, these can be increased.
#
# NETWORK: 1Gbps with 4x TP-Link Easy Smart switches
#
# SELF-EXCLUSION FIX (2026-03-10):
#   Each host must NOT list itself as a builder to avoid SSH-to-self loopback
#   which causes nix-daemon lock contention (multiple daemons competing for same store)
{
  lib,
  config,
  ...
}: let
  # Current hostname for self-exclusion
  currentHost = config.networking.hostName or "unknown";
in {
  # ============================================================================
  # DISTRIBUTED BUILD CONFIGURATION
  # ============================================================================
  nix = {
    # Enabled: Distributed builds across the cluster
    distributedBuilds = lib.mkDefault true;

    # Build machines configuration (v3 migration - conservative settings)
    # REFERENCE: /etc/nixos/machines.nix (Colmena machinesFile)
    # NOTE: sshUser defaults to root when running with sudo, must specify j_kro
    # V3 MIGRATION: All nodes use 2 jobs/2 cores to prevent OOM
    # IMPORTANT: Filter out current host to avoid SSH-to-self loopback causing daemon locks
    buildMachines = lib.filter (m: m.hostName != currentHost) [
      {
        # Zephyr: 32 cores, Ryzen 9 5950X (znver3)
        # Role: K8s control plane + build coordinator + worker
        # V3 MIGRATION: Conservative 2 jobs/2 cores to prevent OOM during heavy builds
        hostName = "zephyr";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 2; # V3 MIGRATION: Very conservative to prevent crashes
        speedFactor = 8;
        supportedFeatures = ["kvm" "big-parallel" "x86-64-v3"];
        mandatoryFeatures = [];
      }
      {
        # Nexus: 24 cores, Ryzen 9 3900X (znver2)
        # Role: K8s storage worker + NFS server
        # V3 MIGRATION: Conservative 2 jobs/2 cores (was 6, reduced after OOM)
        hostName = "nexus";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 2; # V3 MIGRATION: Very conservative to prevent crashes
        speedFactor = 5;
        supportedFeatures = ["big-parallel" "x86-64-v3"];
        mandatoryFeatures = [];
      }
      {
        # Sentry: 16 cores, Ryzen 7 1700 (Zen 1 with AVX2)
        # Role: Monitoring worker
        # V3 MIGRATION: Now participating as build server (was client only)
        hostName = "sentry";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 2; # V3 MIGRATION: Conservative 2 jobs/2 cores
        speedFactor = 3;
        supportedFeatures = ["big-parallel" "x86-64-v3"];
        mandatoryFeatures = [];
      }
    ];

    # Settings for distributed builds
    settings = {
      # Note: buildMachines automatically configures builders via /etc/nix/machines
      # The ssh-ng protocol is used for efficient remote builds

      # V3 MIGRATION: Limit cores per build to prevent memory exhaustion
      # mkForce prevents override by NixOS auto-detection (cores = 0 = auto)
      cores = lib.mkForce 2;

      # Use substituters on remote builders (download from cache instead of copying)
      builders-use-substitutes = true;

      # Binary cache configuration (1Gbps network - fast downloads)
      # Use mkForce to completely override default substituters and prevent duplicates
      # Local Harmonia cache is first (port 5000, not 50000 which was old nix-serve)
      substituters = lib.mkForce [
        "http://10.1.1.110:5000?trusted=1"
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://ezkea.cachix.org"
        # "https://cache.nixos-cuda.org" # TEMPORARILY DISABLED - connectivity issues
        "https://nix-gaming.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        "nexus-cache:qR+dIToYHrN3iJlg2puMRM8zrMtgZ4H7cISSR9E0iEE="
        # "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
      ];

      # Maximum number of parallel build jobs (LOCAL builds on this host)
      # Per-host allocation for v3 migration (conservative to prevent OOM):
      # - Zephyr: 2 of 32 cores (6%) - control plane needs headroom
      # - Nexus: 2 of 24 cores (8%) - NFS/storage needs headroom
      # - Sentry: 2 of 16 cores (12%) - monitoring worker
      # - Forge: 2 of 6 cores (33%) - GPU workloads
      # compute-workload-monitor pauses mining during builds
      #
      # CRITICAL: mkForce required because NixOS defaults max-jobs to CPU count
      # which would cause OOM on all nodes during heavy builds (KDE/Qt)
      max-jobs = lib.mkForce (
        if currentHost == "zephyr" then 2
        else if currentHost == "nexus" then 2
        else if currentHost == "sentry" then 2
        else if currentHost == "forge" then 2
        else 2
      );

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
