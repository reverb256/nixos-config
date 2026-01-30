# Distributed Build Configuration
# Enables building across all 4 nodes in the cluster (51 cores total)
# See AGENTS.md for cluster architecture details
{
  config,
  lib,
  pkgs,
  ...
}: let
  # SSH options for connecting to build machines
  sshOpts = "-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new";
in {
  # ============================================================================
  # DISTRIBUTED BUILD CONFIGURATION
  # ============================================================================
  nix = {
    # DISABLED: SSH authentication issues with remote builders
    # Building locally only until SSH keys are properly configured
    distributedBuilds = false;

    # Build machines configuration
    buildMachines = [
      # Local machine (zephyr) - 32 cores, RTX 3090
      {
        hostName = "localhost";
        systems = ["x86_64-linux" "i686-linux"];
        maxJobs = 8;
        speedFactor = 4;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm" "cuda"];
        mandatoryFeatures = [];
      }
      # Nexus - 24 cores, 2x RTX 3060 Ti
      {
        hostName = "nexus";
        sshUser = "j_kro";
        sshKey = "/home/j_kro/.ssh/id_rsa";
        systems = ["x86_64-linux" "i686-linux"];
        maxJobs = 6;
        speedFactor = 3;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm" "cuda"];
        mandatoryFeatures = [];
      }
      # Forge - 6 cores, 2x RTX 4060 + 2x RX 5700 XT
      {
        hostName = "forge";
        sshUser = "j_kro";
        sshKey = "/home/j_kro/.ssh/id_rsa";
        systems = ["x86_64-linux" "i686-linux"];
        maxJobs = 3;
        speedFactor = 1;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm" "cuda"];
        mandatoryFeatures = [];
      }
      # Sentry - 8 cores, RX 5600 XT
      {
        hostName = "sentry";
        sshUser = "j_kro";
        sshKey = "/home/j_kro/.ssh/id_rsa";
        systems = ["x86_64-linux" "i686-linux"];
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
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
    # Build machine configurations
    Host nexus
      HostName 10.1.1.120
      User j_kro
      IdentityFile ~/.ssh/id_ed25519
      ${sshOpts}
      
    Host forge
      HostName 10.1.1.130
      User j_kro
      IdentityFile ~/.ssh/id_ed25519
      ${sshOpts}
      
    Host sentry
      HostName 10.1.1.140
      User j_kro
      IdentityFile ~/.ssh/id_ed25519
      ${sshOpts}
  '';

  # ============================================================================
  # SSH AGENT CONFIGURATION
  # ============================================================================
  programs.ssh.startAgent = true;

  # Ensure SSH key exists and has correct permissions
  systemd.tmpfiles.rules = [
    "d /home/j_kro/.ssh 0700 j_kro users -"
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
