_: {
  systemd = {
    services."user@1000.service" = {
      serviceConfig = {
        OOMScoreAdjust = -1000;
        MemoryPressureWatch = "skip";
        MemoryHigh = "28G";
        MemoryMax = "30G";
      };
      restartIfChanged = false;
    };

    slices = {
      "nix.slice" = {
        description = "Nix build processes slice";
        sliceConfig = {
          MemoryHigh = "80%";
          CPUQuota = "80%";
        };
      };

      "gaming.slice" = {
        description = "Gaming applications slice";
        sliceConfig = {
          OOMScoreAdjust = -1000;
          MemoryHigh = "90%";
          CPUQuota = "95%";
          CPUAccounting = "yes";
          MemoryAccounting = "yes";
          TasksAccounting = "yes";
          TasksMax = 20000;
        };
      };

      "mining.slice" = {
        description = "Mining processes slice";
        sliceConfig = {
          MemoryHigh = "8G";
          CPUQuota = "95%";
          CPUAccounting = "yes";
          MemoryAccounting = "yes";
          TasksAccounting = "yes";
          TasksMax = 10000;
          BlockIOAccounting = "yes";
          IOWeight = 10;
        };
      };
    };

    services.nix-daemon.serviceConfig.Slice = "nix.slice";
  };
}
