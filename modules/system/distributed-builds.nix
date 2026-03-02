# Distributed Build Configuration with Graceful Degradation
# Enables building across all 4 nodes in the cluster
# See AGENTS.md for cluster architecture details
#
# MINING AWARENESS (2026-02-10):
#   zephyr: Mining CPU (16 threads @ 100%) + GPU (RTX 3090 @ 250W) → Moderate builds
#   nexus:   Mining GPU (2x RTX 3060 Ti @ 130W)              → High capacity (46GB)
#   forge:    Mining HEAVY (2x NVIDIA @ 90W + 2x AMD @ 140W, 95% CPU) → Very limited builds (GPU only)
#   sentry:  Mining CPU (8 threads @ 100% CPU quota)              → Moderate builds
#   NOTE: All AMD CPUs (Ryzen 5950X, 3900X, 1700X) mine at 50% quota
#   XMrig HTTP API available on localhost:18088 for pause/resume
#   Build-wrapper scripts pause mining before builds and resume after completion
#
# GRACEFUL DEGRADATION (2026-02-28):
#   - Fast SSH timeouts (5s) to fail quickly on unreachable hosts
#   - Dynamic builder discovery via health-check scripts
#   - Falls back to local builds when remote builders unavailable
#   - Use ~/{nix,scripts}/builder-health.sh to check status
#
# NETWORK: 1Gbps with 4x TP-Link Easy Smart switches
{lib, pkgs, ...}: {
  # ============================================================================
  # DISTRIBUTED BUILD CONFIGURATION
  # ============================================================================
  nix = {
    # FORCE DISABLED - No remote builders
    distributedBuilds = false;

    # Build machines configuration - DISABLED
    buildMachines = lib.mkForce [
      {
        # Zephyr: 32 cores, 31GB RAM, RTX 3090, AMD Wayland (localhost, skip)
        # Mining: CPU (16 threads @ 100%) + GPU (RTX 3090 @ 250W)
        # Pause mining before builds (16 threads left for OS + apps)
        hostName = "zephyr";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 6; # 4GB per job (31GB total, 6 threads for mining + 20 for OS/apps)
        speedFactor = 2; # Moderate builds with mining-aware scheduling
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm" "cuda"];
        mandatoryFeatures = [];
      }
      {
        # Nexus: 24 cores, 46GB RAM, 2x RTX 3060 Ti (8GB each), CUDA 13.0
        # Mining: 2x NVIDIA GPUs @ 130W power limit (moderate load)
        hostName = "nexus";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 12; # 4GB per job (48GB total)
        speedFactor = 3; # Prioritized for CPU-heavy builds (24 cores)
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm" "cuda"];
        mandatoryFeatures = [];
      }
      {
        # Forge: 6 cores, 15GB RAM, 2x RTX 4060 (8GB each) + 2x RX 5700 XT, CUDA 13.0 + ROCm
        # Mining: HEAVY - 2x NVIDIA @ 90W + 2x AMD @ 140W + 95% CPU quota (GPU only)
        # CAUTION: GPU builds may impact mining profitability
        hostName = "forge";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 2; # VERY conservative due to heavy mining + only 15GB RAM
        speedFactor = 2; # Hybrid GPU acceleration (use sparingly)
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "cuda" "rocm"];
        mandatoryFeatures = [];
      }
      # Sentry temporarily disabled - connection timeout
      # {
      #   # Sentry: 16 cores (8 physical + 16 threads), 31GB RAM, Ryzen 7 1700X, RX 5600 XT, ROCm
      #   # Mining: CPU-only (8 threads @ 100% CPU quota, no GPU mining)
      #   hostName = "sentry";
      #   system = "x86_64-linux";
      #   sshUser = "j_kro";
      #   protocol = "ssh-ng";
      #   maxJobs = 8; # 4GB per job (31GB total, leave 8GB for overhead)
      #   speedFactor = 1; # Lighter builds
      #   supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "rocm"];
      #   mandatoryFeatures = [];
      # }
    ];

    # Settings for distributed builds with graceful degradation
    settings = {
      # Use substituters on remote builders (download from cache instead of copying)
      builders-use-substitutes = true;

      # GRACEFUL DEGRADATION: Fast timeouts for quick fallback to local builds
      # SSH connection timeout: fail fast if builder unreachable (was 30s, now 5s)
      connect-timeout = 5;

      # Maximum time without output before killing build (was 1 hour, keep for long builds)
      max-silent-time = 3600;

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

      # Maximum number of parallel build jobs - LOCAL ONLY
      max-jobs = lib.mkDefault 4; # Local builds only

      # Network optimization (1Gbps networking with TP-Link Easy Smart switches)
      http-connections = 100; # More parallel downloads (1Gbps can handle it)

      # Build logging and debugging
      keep-build-log = true;
      log-lines = 2000;

      # GRACEFUL DEGRADATION: Fallback behavior
      # Continue building locally if remote builders fail
      keep-going = true;
    };
  };

  # ============================================================================
  # SSH AGENT CONFIGURATION
  # ============================================================================
  programs.ssh.startAgent = true;

  # Ensure SSH key exists and has correct permissions
  systemd.tmpfiles.rules = [
    "d /home/j_kro/.ssh 0700 j_kro users -"
  ];

  # SSH client configuration for build machines is managed by modules/ssh.nix

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
