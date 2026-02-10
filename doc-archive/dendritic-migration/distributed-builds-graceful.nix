# Distributed Build Configuration with Graceful Degradation
# Enables building across all 4 nodes when available, falls back to conservative local-only when not
#
# MINING AWARENESS (2026-02-07):
#   zephyr:  Mining CPU (16 threads) + GPU (RTX 3090 @ 250W) → Conservative builds
#   nexus:   Mining GPU (2x RTX 3060 Ti @ 130W)              → High capacity (48GB)
#   forge:    Mining HEAVY (4 GPUs + 95% CPU)                → Very limited builds
#   sentry:  Mining CPU-only (8 threads)                        → Moderate capacity
#
# NETWORK: 1Gbps with 4x TP-Link Easy Smart switches
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Conservative settings for local-only builds (prevents OOM on 32GB RAM)
  localOnlySettings = {
    max-jobs = 4; # Safe for single machine with 32GB RAM
    cores = 6; # Leave headroom for desktop/gaming
  };

  # Aggressive settings when distributed builds are active
  distributedSettings = {
    max-jobs = 24; # 6 (zephyr, 32GB, mining) + 12 (nexus, 48GB) + 2 (forge, 16GB) + 4 (sentry, 32GB)
    cores = 8; # Higher core usage per job since work is distributed
  };
in {
  # ============================================================================
  # CONDITIONAL DISTRIBUTED BUILD CONFIGURATION
  # ============================================================================
  nix = {
    # Only enable distributed builds if build machines are configured and reachable
    distributedBuilds = lib.mkDefault (config.nix.buildMachines != []);

    # Build machines - configured with all cluster nodes
    buildMachines = [
      {
        # Nexus: 24 cores, 48GB RAM, 2x RTX 3060 Ti (8GB each), CUDA 13.0
        # Mining: 2x NVIDIA GPUs @ 130W power limit (moderate load)
        hostName = "nexus";
        system = "x86_64-linux";
        maxJobs = 12; # 4GB per job (48GB total)
        speedFactor = 3; # Prioritized for CPU-heavy builds (24 cores)
        supportedFeatures = ["benchmark" "big-parallel" "kvm" "cuda"];
        mandatoryFeatures = [];
      }
      {
        # Forge: 6 cores, 16GB RAM, 2x RTX 4060 (8GB each) + 2x RX 5700 XT, CUDA 13.0 + ROCm
        # Mining: HEAVY - 2x NVIDIA @ 90W + 2x AMD @ 140W + 95% CPU quota
        # CAUTION: GPU builds may impact mining profitability
        hostName = "forge";
        system = "x86_64-linux";
        maxJobs = 2; # VERY conservative due to heavy mining + only 16GB RAM
        speedFactor = 2; # Hybrid GPU acceleration (use sparingly)
        supportedFeatures = ["benchmark" "big-parallel" "cuda" "rocm"];
        mandatoryFeatures = [];
      }
      {
        # Sentry: 8 cores, 32GB RAM, RX 5600 XT, ROCm
        # Mining: CPU-only (8 threads, no GPU mining)
        hostName = "sentry";
        system = "x86_64-linux";
        maxJobs = 6; # 4GB per job (24GB total, leave 8GB overhead)
        speedFactor = 1; # Lighter builds
        supportedFeatures = ["benchmark" "big-parallel" "rocm"];
        mandatoryFeatures = [];
      }
    ];

    # Settings that ADAPT based on whether distributed builds are enabled
    settings = {
      # Use substituters on remote builders (download from cache instead of copying)
      builders-use-substitutes = true;

      # Binary cache configuration (1Gbps network - fast downloads)
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cuda.cachix.org" # GPU packages (CUDA)
        "https://rocm.cachix.org" # GPU packages (ROCm)
        "https://nix-gaming.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7k3hC7Fi6XZJ6i4y5bT0="
        "cuda.cachix.org-1:d8e9lTzW8p9pCz6DvN6dVlJ3p6sJwXr4vNtQ9w="
        "rocm.cachix.org-1:3h0G9z7yXbH3zq8x6G9Y3zq8x6G9Y3zq8x6G9Y3zq8="
        "nix-gaming.cachix.org-1:lj83ZtOqK9Pp3r4aWj9A3P5R8ZlFJ1nJ2W0vWZ4="
      ];

      # Network optimization (1Gbps networking with TP-Link Easy Smart switches)
      http-connections = 100; # More parallel downloads (1Gbps can handle it)
      connect-timeout = 30;
      max-silent-time = 3600; # Kill stuck builds after 1 hour

      # ADAPTIVE max-jobs: Conservative when alone, aggressive with builders
      max-jobs = lib.mkDefault (
        if (config.nix.distributedBuilds && config.nix.buildMachines != [])
        then distributedSettings.max-jobs # 24 jobs with builders
        else localOnlySettings.max-jobs # 4 jobs local-only
      );

      # ADAPTIVE cores: Same logic
      cores = lib.mkDefault (
        if (config.nix.distributedBuilds && config.nix.buildMachines != [])
        then distributedSettings.cores # 8 cores with builders
        else localOnlySettings.cores # 6 cores local-only
      );

      # Build logging and debugging
      keep-build-log = true;
      log-lines = 2000;
    };
  };

  # ============================================================================
  # SSH CONFIGURATION FOR BUILD MACHINES
  # ============================================================================
  programs.ssh.extraConfig = lib.mkIf config.nix.distributedBuilds ''
    # Build machine configurations for distributed Nix builds
    # NOTE: Using j_kro user which has SSH access across all cluster nodes
    Host nexus
      HostName 10.1.1.120
      User j_kro
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR

    Host forge
      HostName 10.1.1.130
      User j_kro
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR

    Host sentry
      HostName 10.1.1.140
      User j_kro
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR
  '';

  # ============================================================================
  # SSH AGENT CONFIGURATION
  # ============================================================================
  programs.ssh.startAgent = lib.mkDefault config.nix.distributedBuilds;

  # Ensure SSH key directories exist
  # NOTE: j_kro's SSH key is used to authenticate as nixbuild on remote machines
  systemd.tmpfiles.rules = lib.mkIf config.nix.distributedBuilds [
    "d /home/j_kro/.ssh 0700 j_kro users -"
    # nixbuild user is a system user with /var/empty home, authorized_keys is in /etc/ssh/authorized_keys.d/
    "d /etc/ssh/authorized_keys.d 0755 root root -"
  ];

  # ============================================================================
  # BUILD OPTIMIZATION
  # ============================================================================
  # Enable automatic GC to prevent disk space issues
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Optimize store after builds
  nix.settings.auto-optimise-store = true;

  # ============================================================================
  # HELPER SCRIPT TO TOGGLE DISTRIBUTED BUILDS
  # ============================================================================
  environment.systemPackages = lib.mkIf config.nix.distributedBuilds [
    (pkgs.writeScriptBin "nix-toggle-distributed" ''
      #!/usr/bin/env bash
      # Toggle distributed builds on/off

      if [ "$1" == "on" ]; then
        echo "Enabling distributed builds..."
        sudo mkdir -p /etc/nix
        echo '{ nix.buildMachines = [ ... ]; }' | sudo tee /etc/nix/local-distributed.nix
        echo "Run 'sudo nixos-rebuild switch' to apply"
      elif [ "$1" == "off" ]; then
        echo "Disabling distributed builds..."
        sudo rm -f /etc/nix/local-distributed.nix
        echo "Run 'sudo nixos-rebuild switch' to apply"
      else
        echo "Usage: nix-toggle-distributed [on|off]"
        echo ""
        echo "Current status:"
        systemctl --user status nix-daemon 2>/dev/null | head -3
      fi
    '')
  ];
}
