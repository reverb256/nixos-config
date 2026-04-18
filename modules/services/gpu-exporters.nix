{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.gpu-exporters;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.services.gpu-exporters = {
    enable = mkEnableOption "GPU metrics exporters for Prometheus";

    nvidia = {
      enable = mkOption {
        type = types.bool;
        default = config.hardware.gpu-compute.cuda.enable;
        example = true;
        description = "Enable NVIDIA GPU exporter (defaults from hardware.gpu-compute.cuda.enable)";
      };

      port = mkOption {
        type = types.port;
        default = 9400;
        example = 9401;
        description = "Port for NVIDIA GPU exporter";
      };
    };

    amd = {
      enable = mkOption {
        type = types.bool;
        default = config.hardware.gpu-compute.rocm.enable;
        example = true;
        description = "Enable AMD GPU exporter (defaults from hardware.gpu-compute.rocm.enable)";
      };

      port = mkOption {
        type = types.port;
        default = 9104;
        example = 9105;
        description = "Port for AMD GPU exporter (via node-exporter textfile collector)";
      };
    };
  };

  config = mkIf cfg.enable {
    services.prometheus.exporters.nvidia-gpu.enable = mkIf cfg.nvidia.enable false;

    users.users.nvidia-gpu-exporter = mkIf cfg.nvidia.enable {
      isSystemUser = true;
      group = "nvidia-gpu-exporter";
    };
    users.groups.nvidia-gpu-exporter = mkIf cfg.nvidia.enable { };

    systemd = {
      services.prometheus-nvidia-gpu-exporter = mkIf cfg.nvidia.enable {
        description = "Prometheus NVIDIA GPU Metrics Exporter";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        serviceConfig = {
          Type = "simple";
          User = "nvidia-gpu-exporter";
          Group = "nvidia-gpu-exporter";
          DynamicUser = true;
          ExecStart =
            lib.getExe pkgs.prometheus-nvidia-gpu-exporter
            + " --web.listen-address 127.0.0.1:${toString cfg.nvidia.port} --nvidia-smi-command ${lib.getExe config.hardware.nvidia.package.bin}";

          Restart = "always";
          RestartSec = "10s";
          StandardOutput = "journal";
          StandardError = "journal";

          CapabilityBoundingSet = "";
          DeviceAllow = "";
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          NoNewPrivileges = true;
          PrivateDevices = false;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectSystem = "strict";
          RemoveIPC = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          UMask = "0077";
          WorkingDirectory = "/tmp";
        };
      };

      services.prometheus-amdgpu-exporter = mkIf cfg.amd.enable {
        description = "Prometheus AMD GPU Metrics Exporter";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        serviceConfig = {
          Type = "simple";
          User = "node-exporter";
          Group = "node-exporter";
          Environment = [
            "LD_LIBRARY_PATH=/run/opengl-driver/lib:${pkgs.libdrm}/lib:${pkgs.rocmPackages.clr}/lib"
            "PATH=/run/current-system/sw/bin:/run/wrappers/bin"
          ];
          SupplementaryGroups = [
            "video"
            "render"
          ];
          PrivateDevices = false;
          ExecStart = pkgs.writers.writeBash "amdgpu-exporter" ''
            set -uo pipefail

            TEXTFILE_DIR="/var/lib/prometheus/node-exporter/textfile-collector"

            mkdir -p "$TEXTFILE_DIR" 2>/dev/null || true

            OUTPUT_FILE="$TEXTFILE_DIR/amdgpu.prom"
            TEMP_FILE="$OUTPUT_FILE.tmp"

            escape_label() {
              ${pkgs.gnused}/bin/sed 's/"/\\"/g; s/[^a-zA-Z0-9:_]/_/g'
            }

            HOSTNAME="$(${pkgs.hostname}/bin/hostname)"
            INSTANCE_LABEL="\"$HOSTNAME\""

            fetch_metrics() {
              ROCM_SMI="/run/current-system/sw/bin/rocm-smi"

              if [ ! -x "$ROCM_SMI" ]; then
                echo "ERROR: rocm-smi not found at $ROCM_SMI" >&2
                return 1
              fi

              GPU_COUNT=$("$ROCM_SMI" --showid 2>/dev/null | ${pkgs.gnugrep}/bin/grep "^GPU\\[" | ${pkgs.gnugrep}/bin/grep -oP "GPU\\[\\K[0-9]+" | ${pkgs.coreutils}/bin/sort -u | wc -l)

              if [ "$GPU_COUNT" -eq 0 ]; then
                GPU_COUNT=$(${pkgs.coreutils}/bin/ls -d /sys/class/drm/card*/device/gpu_gid 2>/dev/null | wc -l)
              fi

              echo "# HELP amdgpu_gpu_count Total number of AMD GPUs" > "$TEMP_FILE"
              echo "# TYPE amdgpu_gpu_count gauge" >> "$TEMP_FILE"
              echo "amdgpu_gpu_count{instance=$INSTANCE_LABEL} $GPU_COUNT" >> "$TEMP_FILE"

              for gpu in $(${pkgs.coreutils}/bin/seq 0 $((GPU_COUNT - 1))); do
                GPU_LABEL="\"$gpu\""

                TEMPS=$("$ROCM_SMI" --showtemp --showpower --showuse 2>/dev/null || echo "")

                if [ -n "$TEMPS" ]; then
                  TEMP=$(echo "$TEMPS" | ${pkgs.gnugrep}/bin/grep "GPU\\[$gpu\\]" -A 2 | ${pkgs.gnugrep}/bin/grep -oP "Sensor edge.*?:\\s*\\K[0-9.]+" | head -1 || echo "0")
                  if [ "$TEMP" != "0" ]; then
                    echo "amdgpu_temperature_celsius{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL,sensor=\"edge\"} $TEMP" >> "$TEMP_FILE"
                  fi

                  JUNCTION_TEMP=$(echo "$TEMPS" | ${pkgs.gnugrep}/bin/grep "GPU\\[$gpu\\]" -A 2 | ${pkgs.gnugrep}/bin/grep -oP "Sensor junction.*?:\\s*\\K[0-9.]+" | head -1 || echo "0")
                  if [ "$JUNCTION_TEMP" != "0" ]; then
                    echo "amdgpu_temperature_celsius{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL,sensor=\"junction\"} $JUNCTION_TEMP" >> "$TEMP_FILE"
                  fi

                  MEM_TEMP=$(echo "$TEMPS" | ${pkgs.gnugrep}/bin/grep "GPU\\[$gpu\\]" -A 2 | ${pkgs.gnugrep}/bin/grep -oP "Sensor memory.*?:\\s*\\K[0-9.]+" | head -1 || echo "0")
                  if [ "$MEM_TEMP" != "0" ]; then
                    echo "amdgpu_temperature_celsius{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL,sensor=\"memory\"} $MEM_TEMP" >> "$TEMP_FILE"
                  fi
                fi

                POWER_OUTPUT=$("$ROCM_SMI" --showpower 2>/dev/null || echo "")
                POWER=$(echo "$POWER_OUTPUT" | ${pkgs.gnugrep}/bin/grep "GPU\\[$gpu\\]" | ${pkgs.gnugrep}/bin/grep -oP "Average Graphics Package Power.*?:\\s*\\K[0-9.]+" | head -1 || echo "0")
                if [ "$POWER" != "0" ]; then
                  echo "amdgpu_power_watts{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL} $POWER" >> "$TEMP_FILE"
                fi

                UTIL_OUTPUT=$("$ROCM_SMI" --showuse 2>/dev/null || echo "")
                UTIL=$(echo "$UTIL_OUTPUT" | ${pkgs.gnugrep}/bin/grep "GPU\\[$gpu\\]" | ${pkgs.gnugrep}/bin/grep -oP "GPU use.*?:\\s*\\K[0-9.]+" | head -1 || echo "0")
                if [ "$UTIL" != "0" ]; then
                  echo "amdgpu_utilization_percent{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL} $UTIL" >> "$TEMP_FILE"
                fi

                CLOCK_OUTPUT=$("$ROCM_SMI" --showclocks 2>/dev/null || echo "")
                CORE_CLOCK=$(echo "$CLOCK_OUTPUT" | ${pkgs.gnugrep}/bin/grep "GPU\\[$gpu\\]" | ${pkgs.gnugrep}/bin/grep "sclk" | ${pkgs.gnugrep}/bin/grep -oP "\\(([0-9]+)Mhz\\)" | ${pkgs.gnugrep}/bin/grep -oP "[0-9]+" | head -1 || echo "0")
                if [ "$CORE_CLOCK" != "0" ]; then
                  echo "amdgpu_clock_mhz{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL,clock=\"sclk\"} $CORE_CLOCK" >> "$TEMP_FILE"
                fi

                MEM_CLOCK=$(echo "$CLOCK_OUTPUT" | ${pkgs.gnugrep}/bin/grep "GPU\\[$gpu\\]" | ${pkgs.gnugrep}/bin/grep "mclk" | ${pkgs.gnugrep}/bin/grep -oP "\\(([0-9]+)Mhz\\)" | ${pkgs.gnugrep}/bin/grep -oP "[0-9]+" | head -1 || echo "0")
                if [ "$MEM_CLOCK" != "0" ]; then
                  echo "amdgpu_clock_mhz{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL,clock=\"mclk\"} $MEM_CLOCK" >> "$TEMP_FILE"
                fi
              done

              echo "# Generated at $(${pkgs.coreutils}/bin/date -Iseconds)" >> "$TEMP_FILE"
            }

            while true; do
              if fetch_metrics; then
                mv "$TEMP_FILE" "$OUTPUT_FILE"
              fi
              sleep 15
            done
          '';

          Restart = "always";
          RestartSec = "30s";
          StandardOutput = "journal";
          StandardError = "journal";

          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadOnlyPaths = "/";
          ReadWritePaths = "/var/lib/prometheus/node-exporter";
        };
      };

      tmpfiles.rules = [
        "d /var/lib/prometheus 0755 root root -"
        "d /var/lib/prometheus/node-exporter 0755 root root -"
        "d /var/lib/prometheus/node-exporter/textfile-collector 0775 node-exporter node-exporter -"
      ];
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.optional cfg.nvidia.enable cfg.nvidia.port;

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault (
      lib.optional cfg.nvidia.enable cfg.nvidia.port
    );
  };
}
