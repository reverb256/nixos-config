# Distributed Build Configuration
# Enables building across all 4 nodes in the cluster (51 cores total)
# See AGENTS.md for cluster architecture details
{
  config,
  lib,
  pkgs,
  ...
}: {
  # ============================================================================
  # DISTRIBUTED BUILD CONFIGURATION
  # ============================================================================
  nix = {
    # ENABLED: Distributed builds across 4-node cluster (51 cores total)
    distributedBuilds = true;

    # Build machines - ALL 4 NODES (51 cores total)
    buildMachines = [
      # Local machine (zephyr) - 32 cores, RTX 3090
      {
        hostName = "localhost";
        systems = ["x86_64-linux" "i686-linux"];
        maxJobs = 16;
        speedFactor = 4;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm" "cuda"];
        mandatoryFeatures = [];
      }
      # Nexus - 16 cores, RTX 3060 Ti
      {
        hostName = "nexus";
        systems = ["x86_64-linux" "i686-linux"];
        maxJobs = 16;
        speedFactor = 4;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
        mandatoryFeatures = [];
      }
      # Forge - 6 cores, 2x RTX 4060 + 2x RX 5700 XT
      {
        hostName = "forge";
        systems = ["x86_64-linux" "i686-linux"];
        maxJobs = 6;
        speedFactor = 3;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
        mandatoryFeatures = [];
      }
      # Sentry - 4 cores, no GPU
      {
        hostName = "sentry";
        systems = ["x86_64-linux" "i686-linux"];
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel"];
        mandatoryFeatures = [];
      }
    ];

    # Settings for distributed builds
    settings = {
      # Use substituters on remote builders (download from cache instead of copying)
      builders-use-substitutes = true;

      # Maximum number of parallel build jobs across all machines
      # Use mkDefault to allow host-specific overrides
      max-jobs = lib.mkDefault 21; # 8 (zephyr) + 6 (nexus) + 3 (forge) + 4 (sentry)

      # Connect timeout for builders (in seconds)
      connect-timeout = 30;
    };
  };

  # ============================================================================
  # SSH CONFIGURATION FOR BUILD MACHINES
  # ============================================================================
  programs.ssh.extraConfig = ''
    # Build machine configurations for distributed Nix builds
    Host nexus
      HostName 10.1.1.120
      User nixbuild
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR

    Host forge
      HostName 10.1.1.130
      User nixbuild
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR

    Host sentry
      HostName 10.1.1.140
      User nixbuild
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR
  '';

  # ============================================================================
  # SSH AGENT CONFIGURATION
  # ============================================================================
  programs.ssh.startAgent = true;

  # Ensure SSH key exists and has correct permissions
  systemd.tmpfiles.rules = [
    "d /home/j_kro/.ssh 0700 j_kro users -"
    "d /home/nixbuild/.ssh 0700 nixbuild nixbuild -"
  ];

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
