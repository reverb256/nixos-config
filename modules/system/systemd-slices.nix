# Systemd Slices Module
# Extracted from configuration.nix - Workload isolation for gaming, mining, and builds
_: {
  # ============================================================================
  # SYSTEMD SLICES - Workload isolation for gaming, mining, and builds
  # ============================================================================
  systemd = {
    # Protect user session from OOM killer and resource exhaustion
    services."user@1000.service" = {
      serviceConfig = {
        # Prevent OOM killer from terminating the user session
        OOMScoreAdjust = -1000;
        # Ensure user session stays alive even under memory pressure
        MemoryPressureWatch = "skip";
        # Limit memory to prevent system-wide exhaustion (increased from 24G due to Discover crashes)
        MemoryLimit = "32G";
      };
      # CRITICAL: Prevent user session restart during nixos-rebuild
      # Restarting this service kills ALL user processes across ALL TTYs
      restartIfChanged = false;
    };

    # Systemd slices for workload prioritization
    slices = {
      # Systemd slice for nix builds to prevent user responsiveness degradation
      "nix.slice" = {
        description = "Nix build processes slice";
        sliceConfig = {
          MemoryHigh = "80%"; # Limit memory usage
          CPUQuota = "80%"; # Limit CPU usage
        };
      };

      # High-priority gaming slice for VR and gaming applications
      "gaming.slice" = {
        description = "Gaming applications slice";
        sliceConfig = {
          MemoryHigh = "90%"; # High memory priority for games
          CPUQuota = "95%"; # High CPU priority for games
          CPUAccounting = "yes";
          MemoryAccounting = "yes";
          TasksAccounting = "yes";
          TasksMax = 20000;
        };
      };

      # Mining slice - optimized for GPU mining (forge configuration)
      "mining.slice" = {
        description = "Mining processes slice";
        sliceConfig = {
          MemoryHigh = "8G"; # High limit before throttling
          CPUQuota = "95%"; # Allow mining to use up to 95% CPU when needed
          CPUAccounting = "yes";
          MemoryAccounting = "yes";
          TasksAccounting = "yes";
          TasksMax = 10000;
          BlockIOAccounting = "yes";
          IOWeight = 10; # Lower priority than system services
        };
      };
    };

    # Nix daemon service configuration
    services.nix-daemon.serviceConfig.Slice = "nix.slice";
  };
}
