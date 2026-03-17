# Distributed Build Configuration
# Enables building across nodes in the cluster
# See AGENTS.md for cluster architecture details
#
# COMPUTE WORKLOAD MONITOR INTEGRATION (2026-03-09):
#   Build detection is automatic via compute-workload-monitor:
#   - Detects: nixos-rebuild, colmena, nix-build, gcc, clang, cargo, cmake, make, ninja
#   - Action: Pauses ALL mining (GPU + CPU) during builds for maximum build performance
#   - Resumes: Automatically when build processes complete
#
# HOST PARTICIPATION (base x86_64 - reverted from v3 2026-03-14):
#   zephyr: ✅ Server (32 cores, 31GB RAM, znver3)  → Control plane
#   nexus:  ❌ REMOVED (2026-03-14)                  → Storage worker only
#   forge:  ✅ Server (6 cores, 15GB RAM)              → GPU worker (limited jobs)
#   sentry: ✅ Server (16 cores, 31GB RAM, Zen 1)   → Monitoring worker (4 jobs × 2 cores)
#
# NETWORK: 1Gbps with 4x TP-Link Easy Smart switches
#
# SELF-EXCLUSION REMOVED (2026-03-16):
#   The previous self-exclusion filter prevented hosts from using their own
#   cores for distributed builds. Nix correctly handles localhost by using
#   local cores directly without SSH when a host is in its own buildMachines.
{
  lib,
  config,
  ...
}: let
  # Current hostname for per-host configuration
  currentHost = config.networking.hostName or "unknown";
in {
  # ============================================================================
  # DISTRIBUTED BUILD CONFIGURATION
  # ============================================================================
  nix = {
    # Enabled: Distributed builds across the cluster
    distributedBuilds = lib.mkDefault true;

    # Build machines list - includes ALL hosts for distributed builds
    # Nix correctly handles localhost without SSH when building locally
    buildMachines = [
      {
        # Zephyr: 32 cores, Ryzen 9 5950X (znver3)
        # Role: K8s control plane + build coordinator + worker
        hostName = "zephyr";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 4;
        speedFactor = 8;
        supportedFeatures = ["kvm" "big-parallel"];
        mandatoryFeatures = [];
      }
      {
        # Forge: 6 cores, Intel i5-9500 (Coffee Lake)
        # Role: GPU worker (2x RTX 4060 + 2x RX 5700 XT)
        # NOTE: Limited to 1 job due to only 15GB RAM
        hostName = "forge";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 1;
        speedFactor = 2;
        supportedFeatures = ["big-parallel"];
        mandatoryFeatures = [];
      }
      {
        # Sentry: 16 cores, Ryzen 7 1700 (Zen 1 with AVX2)
        # Role: Monitoring worker
        hostName = "sentry";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 4;
        speedFactor = 3;
        supportedFeatures = ["big-parallel"];
        mandatoryFeatures = [];
      }
    ];

    # Settings for distributed builds
    settings = {
      # Note: buildMachines automatically configures builders via /etc/nix/machines
      # The ssh-ng protocol is used for efficient remote builds

      # Limit cores per build to prevent memory exhaustion
      # mkForce prevents override by NixOS auto-detection (cores = 0 = auto)
      # Per-host allocation for optimal build parallelism:
      # - Zephyr: 4 cores per build (32 cores total)
      # - Nexus: 4 cores per build (24 cores total)
      # - Sentry: 2 cores per build (16 cores total) - more parallel jobs
      # - Forge: 2 cores per build (6 cores total)
      cores = lib.mkForce (
        if currentHost == "zephyr" then 4
        else if currentHost == "nexus" then 4
        else if currentHost == "sentry" then 2
        else if currentHost == "forge" then 2
        else 4
      );

      # Use substituters on remote builders (download from cache instead of copying)
      builders-use-substitutes = true;

      # Disable signature checking temporarily (some packages lack signatures)
      require-sigs = lib.mkForce false;
      trusted-users = lib.mkForce ["root" "*" "@wheel"];

      # Binary cache configuration (1Gbps network - fast downloads)
      # Use mkAfter to append common caches after host-specific additions
      # Host-specific caches (e.g., nexus Harmonia) use mkBefore to prepend
      # Priority: Host-specific > Official caches > Personal caches
      substituters = lib.mkAfter [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.garnix.io"  # Garnix CI/CD cache
        "https://reverb-os.cachix.org"  # Personal Cachix cache
        "https://ezkea.cachix.org"
        "https://nix-gaming.cachix.org"
        "https://cache.nixos-cuda.org"  # CUDA binary cache (pre-built CUDA packages)
      ];
      trusted-public-keys = lib.mkAfter [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="  # Garnix cache
        "reverb-os.cachix.org-1:dctKtu02bV/4fbsYbGuVVxQo9R7X6lNqUet1qj2jYzI="  # reverb-os Cachix
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="  # CUDA cache key
      ];

      # Maximum number of parallel build jobs (LOCAL builds on this host)
      # Per-host allocation based on RAM and role:
      # - Zephyr: 4 of 32 cores (12%) - control plane needs headroom
      # - Nexus: 6 of 24 cores (25%) - local builds only (removed from distributed builds)
      # - Sentry: 4 of 16 cores (25%) - monitoring worker (more parallel, smaller jobs)
      # - Forge: 1 of 6 cores (16%) - GPU workloads, limited RAM
      # compute-workload-monitor pauses mining during builds
      #
      # CRITICAL: mkForce required because NixOS defaults max-jobs to CPU count
      max-jobs = lib.mkForce (
        if currentHost == "zephyr" then 4
        else if currentHost == "nexus" then 6
        else if currentHost == "sentry" then 4
        else if currentHost == "forge" then 1
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
    "d /etc/nixos/ssh 0755 root root -"
  ];

  # Copy j_kro's SSH key for nix-daemon distributed builds
  # Root SSH is disabled on remote nodes, so we use j_kro's key
  systemd.services.copy-build-ssh-key = {
    description = "Copy SSH key for distributed builds";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    before = ["nix-daemon.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Copy j_kro's SSH key to root-readable location for nix-daemon
      # ALL nodes need this for distributed builds to work bidirectionally
      if [ ! -f /etc/nixos/ssh/id_ed25519 ]; then
        install -m 600 /home/j_kro/.ssh/id_ed25519 /etc/nixos/ssh/id_ed25519
        install -m 644 /home/j_kro/.ssh/id_ed25519.pub /etc/nixos/ssh/id_ed25519.pub
      fi
    '';
  };

  # SSH config for root (nix-daemon) to use for distributed builds
  # Use copied j_kro SSH key since root SSH is disabled on remote nodes
  environment.etc."ssh/ssh_config.d/50-build-machines.conf".text = ''
    Host zephyr nexus forge sentry
      User j_kro
      IdentityFile /etc/nixos/ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
      ConnectTimeout 30
  '';

  # SSH client configuration for user sessions is managed by modules/ssh.nix

  # ============================================================================
  # /etc/nix/machines FILE GENERATION
  # ============================================================================
  # Manually create /etc/nix/machines since buildMachines activation doesn't work
  # This file is read by nix-daemon for distributed builds
  # Includes ALL hosts - Nix correctly handles localhost without SSH
  environment.etc."nix/machines".text = lib.concatMapStrings (m: ''
    ssh-ng://${m.sshUser}@${m.hostName} ${m.system} ${if m.sshKey != null then m.sshKey else "-"} ${toString m.maxJobs} ${toString m.speedFactor} ${lib.concatStringsSep "," m.supportedFeatures} ${lib.concatStringsSep "," m.mandatoryFeatures}
  '') [
    {
      hostName = "zephyr";
      system = "x86_64-linux";
      sshUser = "j_kro";
      sshKey = "/etc/nixos/ssh/id_ed25519";
      maxJobs = 4;
      speedFactor = 8;
      supportedFeatures = ["kvm" "big-parallel"];
      mandatoryFeatures = [];
    }
    {
      hostName = "forge";
      system = "x86_64-linux";
      sshUser = "j_kro";
      sshKey = "/etc/nixos/ssh/id_ed25519";
      maxJobs = 1;
      speedFactor = 2;
      supportedFeatures = ["big-parallel"];
      mandatoryFeatures = [];
    }
    {
      hostName = "sentry";
      system = "x86_64-linux";
      sshUser = "j_kro";
      sshKey = "/etc/nixos/ssh/id_ed25519";
      maxJobs = 4;
      speedFactor = 3;
      supportedFeatures = ["big-parallel"];
      mandatoryFeatures = [];
    }
  ]);

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
