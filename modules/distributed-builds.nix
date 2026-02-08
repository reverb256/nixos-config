# Distributed Build Configuration
# Enables building across all 4 nodes in the cluster
# See AGENTS.md for cluster architecture details
#
# MINING AWARENESS (2026-02-07):
#   zephyr:  Mining CPU (16 threads) + GPU (RTX 3090 @ 250W) → Conservative builds
#   nexus:   Mining GPU (2x RTX 3060 Ti @ 130W)              → High capacity (48GB)
#   forge:    Mining HEAVY (4 GPUs + 95% CPU)                → Very limited builds
#   sentry:  Mining CPU-only (8 threads)                        → Moderate capacity
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
    buildMachines = [
      {
        # Nexus: 24 cores, 48GB RAM, 2x RTX 3060 Ti (8GB each), CUDA 13.0
        # Mining: 2x NVIDIA GPUs @ 130W power limit (moderate load)
        hostName = "nexus";
        system = "x86_64-linux";
        protocol = "ssh-ng";
        maxJobs = 12;  # 4GB per job (48GB total)
        speedFactor = 3;  # Prioritized for CPU-heavy builds (24 cores)
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm" "cuda"];
        mandatoryFeatures = [];
      }
      {
        # Forge: 6 cores, 16GB RAM, 2x RTX 4060 (8GB each) + 2x RX 5700 XT, CUDA 13.0 + ROCm
        # Mining: HEAVY - 2x NVIDIA @ 90W + 2x AMD @ 140W + 95% CPU quota
        # CAUTION: GPU builds may impact mining profitability
        hostName = "forge";
        system = "x86_64-linux";
        protocol = "ssh-ng";
        maxJobs = 2;  # VERY conservative due to heavy mining + only 16GB RAM
        speedFactor = 2;  # Hybrid GPU acceleration (use sparingly)
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "cuda" "rocm"];
        mandatoryFeatures = [];
      }
      {
        # Sentry: 8 cores, 32GB RAM, RX 5600 XT, ROCm
        # Mining: CPU-only (8 threads, no GPU mining)
        hostName = "sentry";
        system = "x86_64-linux";
        protocol = "ssh-ng";
        maxJobs = 6;  # 4GB per job (24GB total, leave 8GB overhead)
        speedFactor = 1;  # Lighter builds
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "rocm"];
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
        "https://cuda.cachix.org"  # GPU packages (CUDA)
        "https://rocm.cachix.org"  # GPU packages (ROCm)
        "https://nix-gaming.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7k3hC7Fi6XZJ6i4y5bT0="
        "cuda.cachix.org-1:d8e9lTzW8p9pCz6DvN6dVlJ3p6sJwXr4vNtQ9w="
        "rocm.cachix.org-1:3h0G9z7yXbH3zq8x6G9Y3zq8x6G9Y3zq8x6G9Y3zq8="
        "nix-gaming.cachix.org-1:lj83ZtOqK9Pp3r4aWj9A3P5R8ZlFJ1nJ2W0vWZ4="
      ];

      # Maximum number of parallel build jobs across all machines
      # Use mkDefault to allow host-specific overrides
      # RAM-based allocation: 4GB per job
      # Mining-aware: zephyr mining CPU (16 threads) + GPU (RTX 3090 @ 250W)
      max-jobs = lib.mkDefault 24; # 6 (zephyr, mining) + 12 (nexus) + 2 (forge) + 4 (sentry)

      # Network optimization (1Gbps networking with TP-Link Easy Smart switches)
      http-connections = 100;  # More parallel downloads (1Gbps can handle it)
      connect-timeout = 30;
      max-silent-time = 3600;  # Kill stuck builds after 1 hour

      # Build logging and debugging
      keep-build-log = true;
      log-lines = 2000;
    };
  };

  # ============================================================================
  # SSH AGENT CONFIGURATION
  # ============================================================================
  programs.ssh.startAgent = true;

  # Ensure SSH key exists and has correct permissions
  systemd.tmpfiles.rules = [
    "d /home/j_kro/.ssh 0700 j_kro users -"
    "d /home/nixbuild/.ssh 0700 nixbuild nixbuild -"
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
