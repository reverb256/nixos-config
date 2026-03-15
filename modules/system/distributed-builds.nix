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
#   sentry: ✅ Server (16 cores, 31GB RAM, Zen 1)   → Monitoring worker
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

    # Build machines configuration (base x86_64)
    # REFERENCE: /etc/nixos/machines (Colmena machinesFile)
    # NOTE: sshUser defaults to root when running with sudo, must specify j_kro
    # IMPORTANT: Filter out current host to avoid SSH-to-self loopback causing daemon locks
    buildMachines = lib.filter (m: m.hostName != currentHost) [
      {
        # Zephyr: 32 cores, Ryzen 9 5950X (znver3)
        # Role: K8s control plane + build coordinator + worker
        hostName = "zephyr";
        system = "x86_64-linux";
        sshUser = "j_kro";
        protocol = "ssh-ng";
        maxJobs = 4; # Increased now that we're on base x86_64
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
        maxJobs = 1; # Very conservative - only 15GB RAM
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
        maxJobs = 2; # Conservative - 31GB RAM but monitoring needs headroom
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
      cores = lib.mkForce 4;

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
        # "https://cache.nixos-cuda.org" # TEMPORARILY DISABLED - connectivity issues
      ];
      trusted-public-keys = lib.mkAfter [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="  # Garnix cache
        "reverb-os.cachix.org-1:dctKtu02bV/4fbsYbGuVVxQo9R7X6lNqUet1qj2jYzI="  # reverb-os Cachix
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
        # "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      ];

      # Maximum number of parallel build jobs (LOCAL builds on this host)
      # Per-host allocation based on RAM and role:
      # - Zephyr: 4 of 32 cores (12%) - control plane needs headroom
      # - Nexus: 6 of 24 cores (25%) - local builds only (removed from distributed builds)
      # - Sentry: 2 of 16 cores (12%) - monitoring worker
      # - Forge: 1 of 6 cores (16%) - GPU workloads, limited RAM
      # compute-workload-monitor pauses mining during builds
      #
      # CRITICAL: mkForce required because NixOS defaults max-jobs to CPU count
      max-jobs = lib.mkForce (
        if currentHost == "zephyr" then 4
        else if currentHost == "nexus" then 6
        else if currentHost == "sentry" then 2
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
