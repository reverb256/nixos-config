# GPU Metrics Exporters for Prometheus
# Exports NVIDIA and AMD GPU metrics for cluster monitoring
#
# NVIDIA: Uses prometheus-nvidia-gpu-exporter (nvidia-smi based)
# AMD: Uses custom textfile exporter via rocm-smi
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.gpu-exporters;
  inherit (lib) mkEnableOption mkOption types mkIf;

in {
  options.services.gpu-exporters = {
    enable = mkEnableOption "GPU metrics exporters for Prometheus";

    # NVIDIA GPU configuration
    nvidia = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable NVIDIA GPU exporter";
      };

      port = mkOption {
        type = types.port;
        default = 9400;
        description = "Port for NVIDIA GPU exporter";
      };
    };

    # AMD GPU configuration
    amd = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable AMD GPU exporter";
      };

      port = mkOption {
        type = types.port;
        default = 9104;
        description = "Port for AMD GPU exporter (via node-exporter textfile collector)";
      };
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # NVIDIA GPU EXPORTER
    # ============================================================================
    # Disable the built-in exporter that has duplicate flag issues
    services.prometheus.exporters.nvidia-gpu.enable = mkIf cfg.nvidia.enable false;

    # Use custom service instead of prometheus.exporters.nvidia-gpu to avoid
    # duplicate nvidia-smi-command flag issues when multiple NVIDIA packages exist
    systemd.services.prometheus-nvidia-gpu-exporter = mkIf cfg.nvidia.enable {
      description = "Prometheus NVIDIA GPU Metrics Exporter";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "nvidia-gpu-exporter";
        Group = "nvidia-gpu-exporter";
        DynamicUser = true;
        ExecStart = "${pkgs.prometheus-nvidia-gpu-exporter}/bin/nvidia_gpu_exporter --web.listen-address 127.0.0.1:${toString cfg.nvidia.port} --nvidia-smi-command ${config.hardware.nvidia.package.bin}/bin/nvidia-smi";

        Restart = "always";
        RestartSec = "10s";
        StandardOutput = "journal";
        StandardError = "journal";

        # Security hardening from upstream module
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

    # Create user/group for the exporter (matches upstream module)
    users.users.nvidia-gpu-exporter = mkIf cfg.nvidia.enable {
      isSystemUser = true;
      group = "nvidia-gpu-exporter";
    };
    users.groups.nvidia-gpu-exporter = mkIf cfg.nvidia.enable { };

    # ============================================================================
    # AMD GPU EXPORTER
    # ============================================================================
    # Use textfile collector with a script that polls rocm-smi
    systemd.services.prometheus-amdgpu-exporter = mkIf cfg.amd.enable {
      description = "Prometheus AMD GPU Metrics Exporter";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "node-exporter";
        Group = "node-exporter";
        # Add ROCm and libdrm library paths for rocm-smi
        Environment = [
          "LD_LIBRARY_PATH=/run/opengl-driver/lib:${pkgs.libdrm}/lib:${pkgs.rocmPackages.clr}/lib"
          "PATH=/run/current-system/sw/bin:/run/wrappers/bin"
        ];
        # Add supplementary groups for GPU access
        SupplementaryGroups = [ "video" "render" ];
        # Allow access to GPU devices
        PrivateDevices = false;
        ExecStart = pkgs.writers.writeBash "amdgpu-exporter" ''
          set -uo pipefail

          # Textfile collector directory
          TEXTFILE_DIR="/var/lib/prometheus/node-exporter/textfile-collector"

          # Ensure directory exists (tmpfiles creates it, but just in case)
          mkdir -p "$TEXTFILE_DIR" 2>/dev/null || true

          # Output file (fixed name for node-exporter textfile collector)
          OUTPUT_FILE="$TEXTFILE_DIR/amdgpu.prom"
          TEMP_FILE="$OUTPUT_FILE.tmp"

          # Helper function to escape Prometheus labels
          escape_label() {
            ${pkgs.gnused}/bin/sed 's/"/\\"/g; s/[^a-zA-Z0-9:_]/_/g'
          }

          # Get hostname for instance label
          HOSTNAME="$(${pkgs.hostname}/bin/hostname)"
          INSTANCE_LABEL="\"$(echo "$HOSTNAME" | escape_label)\""

          # Fetch AMD GPU metrics using rocm-smi
          fetch_metrics() {
            # Path to rocm-smi
            ROCM_SMI="/run/current-system/sw/bin/rocm-smi"

            # Check if rocm-smi exists
            if [ ! -x "$ROCM_SMI" ]; then
              echo "ERROR: rocm-smi not found at $ROCM_SMI" >&2
              return 1
            fi

            # Get GPU count - count unique GPU indices (lines with GPU[N]: followed by GUID)
            GPU_COUNT=$("$ROCM_SMI" --showid 2>/dev/null | ${pkgs.gnugrep}/bin/grep "^GPU\[" | ${pkgs.gnugrep}/bin/grep -oP "GPU\[\K[0-9]+" | ${pkgs.coreutils}/bin/sort -u | wc -l)

            if [ "$GPU_COUNT" -eq 0 ]; then
              # Try alternate method using sysfs
              GPU_COUNT=$(${pkgs.coreutils}/bin/ls -d /sys/class/drm/card*/device/gpu_gid 2>/dev/null | wc -l)
            fi

            echo "# HELP amdgpu_gpu_count Total number of AMD GPUs" > "$TEMP_FILE"
            echo "# TYPE amdgpu_gpu_count gauge" >> "$TEMP_FILE"
            echo "amdgpu_gpu_count{instance=$INSTANCE_LABEL} $GPU_COUNT" >> "$TEMP_FILE"

            # Fetch per-GPU metrics
            for gpu in $(${pkgs.coreutils}/bin/seq 0 $((GPU_COUNT - 1))); do
              GPU_LABEL="\"$gpu\""

              # Temperature (edge/junction/memory)
              TEMPS=$("$ROCM_SMI" --showtemp --showpower --showuse 2>/dev/null || echo "")

              if [ -n "$TEMPS" ]; then
                # Parse temperature - actual format: "GPU[0]		: Temperature (Sensor edge) (C): 56.0"
                TEMP=$(echo "$TEMPS" | ${pkgs.gnugrep}/bin/grep "GPU\[$gpu\]" -A 2 | ${pkgs.gnugrep}/bin/grep -oP "Sensor edge.*?:\s*\K[0-9.]+" | head -1 || echo "0")
                if [ "$TEMP" != "0" ]; then
                  echo "amdgpu_temperature_celsius{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL,sensor=\"edge\"} $TEMP" >> "$TEMP_FILE"
                fi

                # Junction temp
                JUNCTION_TEMP=$(echo "$TEMPS" | ${pkgs.gnugrep}/bin/grep "GPU\[$gpu\]" -A 2 | ${pkgs.gnugrep}/bin/grep -oP "Sensor junction.*?:\s*\K[0-9.]+" | head -1 || echo "0")
                if [ "$JUNCTION_TEMP" != "0" ]; then
                  echo "amdgpu_temperature_celsius{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL,sensor=\"junction\"} $JUNCTION_TEMP" >> "$TEMP_FILE"
                fi

                # Memory temp
                MEM_TEMP=$(echo "$TEMPS" | ${pkgs.gnugrep}/bin/grep "GPU\[$gpu\]" -A 2 | ${pkgs.gnugrep}/bin/grep -oP "Sensor memory.*?:\s*\K[0-9.]+" | head -1 || echo "0")
                if [ "$MEM_TEMP" != "0" ]; then
                  echo "amdgpu_temperature_celsius{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL,sensor=\"memory\"} $MEM_TEMP" >> "$TEMP_FILE"
                fi
              fi

              # Power usage (Watts) - separate call since --showpower doesn't work with -i
              POWER_OUTPUT=$("$ROCM_SMI" --showpower 2>/dev/null || echo "")
              POWER=$(echo "$POWER_OUTPUT" | ${pkgs.gnugrep}/bin/grep "GPU\[$gpu\]" | ${pkgs.gnugrep}/bin/grep -oP "Average Graphics Package Power.*?:\s*\K[0-9.]+" | head -1 || echo "0")
              if [ "$POWER" != "0" ]; then
                echo "amdgpu_power_watts{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL} $POWER" >> "$TEMP_FILE"
              fi

              # Utilization percentage - separate call
              UTIL_OUTPUT=$("$ROCM_SMI" --showuse 2>/dev/null || echo "")
              UTIL=$(echo "$UTIL_OUTPUT" | ${pkgs.gnugrep}/bin/grep "GPU\[$gpu\]" | ${pkgs.gnugrep}/bin/grep -oP "GPU use.*?:\s*\K[0-9.]+" | head -1 || echo "0")
              if [ "$UTIL" != "0" ]; then
                echo "amdgpu_utilization_percent{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL} $UTIL" >> "$TEMP_FILE"
              fi

              # Clock speeds (MHz) - separate call
              CLOCK_OUTPUT=$("$ROCM_SMI" --showclocks 2>/dev/null || echo "")
              # sclk = core clock, format: "sclk clock level: 1: (1845Mhz)"
              CORE_CLOCK=$(echo "$CLOCK_OUTPUT" | ${pkgs.gnugrep}/bin/grep "GPU\[$gpu\]" | ${pkgs.gnugrep}/bin/grep "sclk" | ${pkgs.gnugrep}/bin/grep -oP "\(([0-9]+)Mhz\)" | ${pkgs.gnugrep}/bin/grep -oP "[0-9]+" | head -1 || echo "0")
              if [ "$CORE_CLOCK" != "0" ]; then
                echo "amdgpu_clock_mhz{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL,clock=\"sclk\"} $CORE_CLOCK" >> "$TEMP_FILE"
              fi

              # mclk = memory clock, format: "mclk clock level: 3: (875Mhz)"
              MEM_CLOCK=$(echo "$CLOCK_OUTPUT" | ${pkgs.gnugrep}/bin/grep "GPU\[$gpu\]" | ${pkgs.gnugrep}/bin/grep "mclk" | ${pkgs.gnugrep}/bin/grep -oP "\(([0-9]+)Mhz\)" | ${pkgs.gnugrep}/bin/grep -oP "[0-9]+" | head -1 || echo "0")
              if [ "$MEM_CLOCK" != "0" ]; then
                echo "amdgpu_clock_mhz{instance=$INSTANCE_LABEL,gpu=$GPU_LABEL,clock=\"mclk\"} $MEM_CLOCK" >> "$TEMP_FILE"
              fi
            done

            # Add timestamp
            echo "# Generated at $(${pkgs.coreutils}/bin/date -Iseconds)" >> "$TEMP_FILE"
          }

          # Main loop - write metrics every 15 seconds
          while true; do
            if fetch_metrics; then
              # Atomic move to final location
              mv "$TEMP_FILE" "$OUTPUT_FILE"
            fi
            sleep 15
          done
        '';

        Restart = "always";
        RestartSec = "30s";
        StandardOutput = "journal";
        StandardError = "journal";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = "/";
        ReadWritePaths = "/var/lib/prometheus/node-exporter";
      };
    };

    # Create prometheus directories with correct ownership using tmpfiles
    # Note: node-exporter runs as node-exporter user, so textfile-collector needs to be writable by that user
    systemd.tmpfiles.rules = [
      "d /var/lib/prometheus 0755 root root -"
      "d /var/lib/prometheus/node-exporter 0755 root root -"
      "d /var/lib/prometheus/node-exporter/textfile-collector 0775 node-exporter node-exporter -"
    ];

    # Open firewall ports for NVIDIA exporter (AMD uses node-exporter textfile)
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.optional cfg.nvidia.enable cfg.nvidia.port;

    # Also open on main LAN interface for local prometheus scraping
    networking.firewall.allowedTCPPorts = lib.optional cfg.nvidia.enable cfg.nvidia.port;
  };
}
