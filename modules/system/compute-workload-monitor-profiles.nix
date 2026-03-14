# Compute Workload Monitor - Node-Specific PSI Profiles
# Per-node tuning based on hardware capacity and role

{
  lib,
  config,
  ...
}: let
    hostname = config.networking.hostName;
  in {
    options.services.compute-workload-monitor = {
      # Per-node PSI threshold profiles
      profile = lib.mkOption {
        type = lib.types.enum ["conservative" "balanced" "aggressive" "custom"];
        default = "balanced";
        description = "PSI detection sensitivity profile";
      };

      # Custom thresholds (when profile = "custom")
      customThresholds = {
        cpuBuild = lib.mkOption {
          type = lib.types.str;
          default = "5.0";
          description = "CPU PSI avg10 threshold for build detection";
        };
        cpuIdle = lib.mkOption {
          type = lib.types.str;
          default = "2.0";
          description = "CPU PSI avg10 threshold for idle state";
        };
        memSome = lib.mkOption {
          type = lib.types.str;
          default = "1.0";
          description = "Memory PSI some avg10 threshold";
        };
        memFull = lib.mkOption {
          type = lib.types.str;
          default = "0.5";
          description = "Memory PSI full avg10 threshold (thrashing)";
        };
        ioSome = lib.mkOption {
          type = lib.types.str;
          default = "2.0";
          description = "I/O PSI some avg10 threshold";
        };
        ioFull = lib.mkOption {
          type = lib.types.str;
          default = "0.3";
          description = "I/O PSI full avg10 threshold";
        };
      };
    };

    config = let
      # Profile definitions based on node capabilities
      profiles = {
        zephyr = {
          # 32 cores, 31GB RAM - Can handle more pressure
          # Control plane needs headroom for apiserver/etcd
          conservative = {
            cpuBuild = "3.0";   # More sensitive (pause earlier)
            cpuIdle = "1.5";
            memSome = "0.5";    # Memory pressure is critical with 31GB
            memFull = "0.3";
            ioSome = "1.5";
            ioFull = "0.2";
          };
          balanced = {
            cpuBuild = "5.0";
            cpuIdle = "2.0";
            memSome = "1.0";
            memFull = "0.5";
            ioSome = "2.0";
            ioFull = "0.3";
          };
          aggressive = {
            cpuBuild = "8.0";   # Let builds run longer
            cpuIdle = "3.0";
            memSome = "2.0";
            memFull = "1.0";
            ioSome = "3.0";
            ioFull = "0.5";
          };
        };
        nexus = {
          # 24 cores, 46GB RAM, NFS server - More RAM, I/O sensitive
          # NFS operations need low I/O latency
          conservative = {
            cpuBuild = "3.0";
            cpuIdle = "1.5";
            memSome = "0.5";
            memFull = "0.3";
            ioSome = "1.0";    # More sensitive (NFS server)
            ioFull = "0.2";
          };
          balanced = {
            cpuBuild = "5.0";
            cpuIdle = "2.0";
            memSome = "1.0";
            memFull = "0.5";
            ioSome = "2.0";
            ioFull = "0.3";
          };
          aggressive = {
            cpuBuild = "8.0";
            cpuIdle = "3.0";
            memSome = "2.0";
            memFull = "1.0";
            ioSome = "3.0";
            ioFull = "0.5";
          };
        };
        forge = {
          # 6 cores, 15GB RAM, 4x GPU - Smallest node, memory constrained
          # GPU mining is primary workload
          conservative = {
            cpuBuild = "2.0";    # Very sensitive (only 6 cores)
            cpuIdle = "1.0";
            memSome = "0.3";    # Memory constrained (15GB)
            memFull = "0.2";
            ioSome = "1.0";
            ioFull = "0.1";
          };
          balanced = {
            cpuBuild = "4.0";
            cpuIdle = "1.5";
            memSome = "0.5";
            memFull = "0.3";
            ioSome = "1.5";
            ioFull = "0.2";
          };
          aggressive = {
            cpuBuild = "6.0";
            cpuIdle = "2.5";
            memSome = "1.0";
            memFull = "0.5";
            ioSome = "2.5";
            ioFull = "0.3";
          };
        };
        sentry = {
          # 16 cores, 31GB RAM, 1x AMD - Monitoring node
          # Monitoring needs to stay responsive
          conservative = {
            cpuBuild = "3.0";
            cpuIdle = "1.5";
            memSome = "0.5";
            memFull = "0.3";
            ioSome = "1.5";
            ioFull = "0.2";
          };
          balanced = {
            cpuBuild = "5.0";
            cpuIdle = "2.0";
            memSome = "1.0";
            memFull = "0.5";
            ioSome = "2.0";
            ioFull = "0.3";
          };
          aggressive = {
            cpuBuild = "8.0";
            cpuIdle = "3.0";
            memSome = "2.0";
            memFull = "1.0";
            ioSome = "3.0";
            ioFull = "0.5";
          };
        };
      };

    in lib.mkIf config.services.compute-workload-monitor.enable (let
      # Select profile for current node
      nodeProfiles = profiles.${hostname} or profiles.zephyr;
      selectedProfile = if config.services.compute-workload-monitor.profile != "custom"
        then nodeProfiles.${config.services.compute-workload-monitor.profile}
        else {
          cpuBuild = config.services.compute-workload-monitor.customThresholds.cpuBuild;
          cpuIdle = config.services.compute-workload-monitor.customThresholds.cpuIdle;
          memSome = config.services.compute-workload-monitor.customThresholds.memSome;
          memFull = config.services.compute-workload-monitor.customThresholds.memFull;
          ioSome = config.services.compute-workload-monitor.customThresholds.ioSome;
          ioFull = config.services.compute-workload-monitor.customThresholds.ioFull;
        };
    in {
      # Pass thresholds to the service via environment
      systemd.services.compute-workload-monitor = {
        environment = {
          PSI_CPU_BUILD_THRESHOLD = selectedProfile.cpuBuild;
          PSI_CPU_IDLE_THRESHOLD = selectedProfile.cpuIdle;
          PSI_MEM_SOME_THRESHOLD = selectedProfile.memSome;
          PSI_MEM_FULL_THRESHOLD = selectedProfile.memFull;
          PSI_IO_SOME_THRESHOLD = selectedProfile.ioSome;
          PSI_IO_FULL_THRESHOLD = selectedProfile.ioFull;
        };
      };

      # Runtime config file for imperative overrides
      environment.etc."compute-workload-monitor/thresholds.conf".text = ''
        # PSI Thresholds - Auto-generated from NixOS config
        # To override imperatively, edit /run/compute-workload-monitor/thresholds.conf
        PSI_CPU_BUILD_THRESHOLD=${selectedProfile.cpuBuild}
        PSI_CPU_IDLE_THRESHOLD=${selectedProfile.cpuIdle}
        PSI_MEM_SOME_THRESHOLD=${selectedProfile.memSome}
        PSI_MEM_FULL_THRESHOLD=${selectedProfile.memFull}
        PSI_IO_SOME_THRESHOLD=${selectedProfile.ioSome}
        PSI_IO_FULL_THRESHOLD=${selectedProfile.ioFull}
      '';

      # Runtime override directory (writable, for imperative changes)
      systemd.tmpfiles.rules = [
        "d /run/compute-workload-monitor 0755 root root - -"
      ];
    });
}
