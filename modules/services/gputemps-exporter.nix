# GPU Temperature Exporter (GDDR6/GDDR6X VRAM per-module via BAR0 MMIO)
# Uses ThomasBaruzier/gddr6-core-junction-vram-temps (gputemps binary)
# Writes Prometheus textfile format for node-exporter textfile collector
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.gputemps-exporter;
  inherit (lib) mkEnableOption mkOption types mkIf;

  textfileDir = "/var/lib/prometheus/node-exporter/textfile-collector";

  # Python helper that parses gputemps JSON and emits Prometheus text format
  parseScript = pkgs.writeText "gputemps2prom.py" ''
    import json, sys, os

    data = json.load(sys.stdin)
    hostname = os.uname().nodename.split('.')[0]

    for gpu in data.get('gpus', []):
        idx = gpu.get('index', 0)
        labels = f'gpu="{idx}",instance="{hostname}"'

        core = gpu.get('core')
        if core is not None:
            print(f'gputemps_core_temperature_celsius{{{labels}}} {core}')

        junction = gpu.get('junction')
        if junction is not None:
            print(f'gputemps_junction_temperature_celsius{{{labels}}} {junction}')

        vram = gpu.get('vram')
        if vram is not None:
            print(f'gputemps_vram_temperature_celsius{{{labels}}} {vram}')
  '';

  # Shell wrapper: run gputemps, pipe to Python parser, write to textfile dir
  exporterScript = pkgs.writeShellScript "gputemps-exporter" ''
    set -euo pipefail

    OUT="${textfileDir}/gputemps.prom.tmp"
    FINAL="${textfileDir}/gputemps.prom"

    # Fetch JSON data from gputemps (requires iomem=relaxed + root for /dev/mem access)
    if ! DATA=$(${lib.getExe pkgs.gputemps} --once --json 2>&1); then
      echo "# HELP gputemps_up 1 if the gputemps binary ran successfully" > "$OUT"
      echo "# TYPE gputemps_up gauge" >> "$OUT"
      echo "gputemps_up{gpu=\"all\"} 0" >> "$OUT"
      mv -f "$OUT" "$FINAL"
      exit 0
    fi

    # HEADER block
    echo "# HELP gputemps_up 1 if the gputemps binary ran successfully" > "$OUT"
    echo "# TYPE gputemps_up gauge" >> "$OUT"
    echo "gputemps_up{gpu=\"all\"} 1" >> "$OUT"

    echo "# HELP gputemps_core_temperature_celsius GPU core temperature" >> "$OUT"
    echo "# TYPE gputemps_core_temperature_celsius gauge" >> "$OUT"
    echo "# HELP gputemps_junction_temperature_celsius GPU junction (hotspot) temperature" >> "$OUT"
    echo "# TYPE gputemps_junction_temperature_celsius gauge" >> "$OUT"
    echo "# HELP gputemps_vram_temperature_celsius GDDR6/GDDR6X VRAM junction temperature (per-module hotspot)" >> "$OUT"
    echo "# TYPE gputemps_vram_temperature_celsius gauge" >> "$OUT"

    # Pipe JSON to Python parser
    echo "$DATA" | ${lib.getExe' pkgs.python3 "python3"} ${parseScript} >> "$OUT" || true

    # Validate and atomically write
    if [ -s "$OUT" ]; then
      mv -f "$OUT" "$FINAL"
    else
      echo "# gputemps-exporter: empty output" > "$OUT"
      mv -f "$OUT" "$FINAL"
    fi
  '';
in
{
  options.services.gputemps-exporter = {
    enable = mkEnableOption "GDDR6/GDDR6X per-module VRAM temperature exporter (gputemps)";
    interval = mkOption {
      type = types.int;
      default = 30;
      description = "Polling interval in seconds";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.gputemps ];

    systemd.services.gputemps-exporter = {
      description = "Export per-module GDDR6/GDDR6X VRAM junction temperatures to Prometheus textfile";
      wantedBy = [ "multi-user.target" ];
      after = [ "prometheus-node-exporter.service" ];
      requires = [ "prometheus-node-exporter.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = exporterScript;
        TimeoutStartSec = "15";
      };
    };

    systemd.timers.gputemps-exporter = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "60s";
        OnUnitActiveSec = "${toString cfg.interval}s";
        AccuracySec = "5s";
      };
    };
  };
}
