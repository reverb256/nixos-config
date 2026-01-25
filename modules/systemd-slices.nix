# Systemd Slices Module
# Extracted from configuration.nix - Workload isolation for gaming, mining, and builds
_: {
  # ============================================================================
  # SYSTEMD SLICES - Workload isolation for gaming, mining, and builds
  # ============================================================================
  systemd = {
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

      # Mining slice with lower priority to avoid interfering with gaming
      "mining.slice" = {
        description = "Mining processes slice";
        sliceConfig = {
          MemoryHigh = "50%"; # Limit mining memory usage
          CPUQuota = "60%"; # Limit mining CPU usage during gaming
          CPUAccounting = "yes";
          MemoryAccounting = "yes";
          TasksAccounting = "yes";
          TasksMax = 10000;
        };
      };
    };

    # Nix daemon service configuration
    services.nix-daemon.serviceConfig.Slice = "nix.slice";
  };
}
