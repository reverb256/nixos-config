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
        # Soft throttle at 28G, hard kill at 30G — leaves 1-3G for kernel/critical services
        # Previous 32G limit matched total RAM with zero headroom (31GB system)
        MemoryHigh = "28G";
        MemoryMax = "30G";
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
          OOMScoreAdjust = -1000; # Maximum protection from OOM killer
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
