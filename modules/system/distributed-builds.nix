# Distributed Build Configuration
# Enables building across the cluster (Zephyr + Nexus)
# See AGENTS.md for cluster architecture details
#
# COMPUTE WORKLOAD MONITOR INTEGRATION (2026-03-09):
#   Build detection is automatic via compute-workload-monitor:
#   - Detects: nixos-rebuild, colmena, nix-build, gcc, clang, cargo, cmake, make, ninja
#   - Action: Pauses ALL mining (GPU + CPU) during builds for maximum build performance
#   - Resumes: Automatically when build processes complete
#
# HOST PARTICIPATION:
#   zephyr: ✅ Enabled (32 cores, 31GB RAM)  → Coordinator + Worker
#   nexus:  ✅ Enabled (24 cores, 46GB RAM)  → Worker (high capacity, prioritized)
#   forge:  ❌ Disabled (CUDA bug on nexus)  → Local builds only
#   sentry: ❌ Disabled (CPU mining focus)  → Local builds only
#
# NETWORK: 1Gbps with 4x TP-Link Easy Smart switches
{lib, ...}: {
  # ============================================================================
  # DISTRIBUTED BUILD CONFIGURATION
  # ============================================================================
  nix = {
    # Enabled: Distributed builds across the cluster
    distributedBuilds = true;

    # Build machines configuration
    # NOTE: sshUser defaults to root when running with sudo, must specify j_kro
    # Only Zephyr and Nexus participate (Forge and Sentry have distributedBuilds disabled)
    buildMachines = [
      {
        # Zephyr: 32 cores, 31GB RAM, RTX 3090, Ryzen 5950X
        # Role: Control plane + build coordinator + worker
        # compute-workload-monitor pauses all mining during builds
        hostName = "zephyr";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 6; # 4GB per job (31GB total, conservative for RAM headroom)
        speedFactor = 2; # Moderate speed (32 cores, but reserves capacity for control plane)
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm" "cuda"];
        mandatoryFeatures = [];
      }
      {
        # Nexus: 24 cores, 46GB RAM, 2x RTX 3060 Ti (8GB each), Ryzen 3900X
        # Role: Storage node + primary build worker (high capacity)
        # compute-workload-monitor pauses all mining during builds
        hostName = "nexus";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 12; # 4GB per job (48GB total, prioritized for CPU-heavy builds)
        speedFactor = 3; # High priority for CPU builds (24 cores, 46GB RAM)
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm" "cuda"];
        mandatoryFeatures = [];
      }
    ];

    # Settings for distributed builds
    settings = {
      # Use substituters on remote builders (download from cache instead of copying)
      builders-use-substitutes = true;

      # Binary cache configuration (1Gbps network - fast downloads)
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.nixos-cuda.org" # CUDA packages (official mirror)
        "https://nix-gaming.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
      ];

      # Maximum number of parallel build jobs across all machines
      # Use mkDefault to allow host-specific overrides
      # RAM-based allocation: 4GB per job
      # compute-workload-monitor pauses mining during builds, so full capacity available
      max-jobs = lib.mkDefault 18; # 6 (zephyr) + 12 (nexus) = 18 total parallel jobs

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
