# dbus-broker fd exporter — open-fd count vs soft RLIMIT_NOFILE for the user
# session broker.
#
# Canary for the 2026-08-14 failure mode: the user-session dbus-broker hit
# EMFILE at its soft limit of 1024 under Steam/gamescope load, exited fatally,
# and the whole graphical session was torn down (uwsm bindpid). The broker's
# fd count climbing toward the limit is the early warning; the session bus has
# no resource accounting, so fd usage IS the metric that matters.
#
# Mirrors the gputemps-exporter pattern: root oneshot + timer writing a
# Prometheus textfile for node-exporter's textfile collector.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.dbus-broker-exporter;
  inherit (lib) mkEnableOption mkOption types mkIf;

  textfileDir = "/var/lib/prometheus/node-exporter/textfile-collector";

  exporterScript = pkgs.writeShellScript "dbus-broker-exporter" ''
    set -euo pipefail
    OUT="${textfileDir}/dbus-broker-fds.prom.tmp"
    FINAL="${textfileDir}/dbus-broker-fds.prom"

    emit() {
      # $1 = broker pid (may be empty), $2 = instance label
      local pid="$1" label="$2"
      if [ -z "$pid" ] || [ ! -d "/proc/$pid" ]; then
        echo "dbus_broker_open_fds{instance=\"$label\"} 0" >> "$OUT"
        echo "dbus_broker_soft_limit{instance=\"$label\"} 0" >> "$OUT"
        return
      fi
      local fds limit
      fds=$(ls "/proc/$pid/fd" 2>/dev/null | wc -l)
      limit=$(awk '/Max open files/{print $4}' "/proc/$pid/limits" 2>/dev/null || echo 0)
      echo "dbus_broker_open_fds{instance=\"$label\"} $fds" >> "$OUT"
      echo "dbus_broker_soft_limit{instance=\"$label\"} $limit" >> "$OUT"
    }

    echo "# HELP dbus_broker_open_fds Open file descriptors in dbus-broker" > "$OUT"
    echo "# TYPE dbus_broker_open_fds gauge" >> "$OUT"
    echo "# HELP dbus_broker_soft_limit dbus-broker soft RLIMIT_NOFILE" >> "$OUT"
    echo "# TYPE dbus_broker_soft_limit gauge" >> "$OUT"

    # The session/system bus broker is a direct child of
    # `dbus-broker-launch --scope <scope>`. The at-spi2 accessibility broker
    # is also named dbus-broker and runs as the same uid, but its launcher
    # passes --config-file — exclude it so we always report the session bus.
    # (The system bus runs as messagebus, not root, so uid-based matching
    # would miss it.)
    broker_pid() {
      local scope="$1" launcher=""
      while read -r l; do
        [ -n "$l" ] || continue
        if ! grep -q -- '--config-file' "/proc/$l/cmdline" 2>/dev/null; then
          launcher="$l"
          break
        fi
      done < <(pgrep -f "dbus-broker-launch --scope $scope" 2>/dev/null || true)
      [ -n "$launcher" ] || return 1
      pgrep -P "$launcher" -x dbus-broker 2>/dev/null | head -1 || true
    }

    emit "$(broker_pid user || true)" "user-j_kro"
    emit "$(broker_pid system || true)" "system"

    if [ -s "$OUT" ]; then
      mv -f "$OUT" "$FINAL"
    else
      echo "# dbus-broker-exporter: empty output" > "$OUT"
      mv -f "$OUT" "$FINAL"
    fi
  '';
in {
  options.services.dbus-broker-exporter = {
    enable = mkEnableOption "dbus-broker fd usage exporter";
    interval = mkOption {
      type = types.int;
      default = 60;
      description = "Polling interval in seconds";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.dbus-broker-exporter = {
      description = "Export dbus-broker open-fd usage to Prometheus textfile";
      wantedBy = ["multi-user.target"];
      after = ["prometheus-node-exporter.service"];
      requires = ["prometheus-node-exporter.service"];
      # procps for pgrep, gawk for awk — the default NixOS service PATH has
      # neither. Must be a sibling of serviceConfig: inside serviceConfig it
      # renders as a lowercase `path=` directive that systemd ignores.
      path = with pkgs; [procps gawk];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = exporterScript;
        TimeoutStartSec = "15";
      };
    };

    systemd.timers.dbus-broker-exporter = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "60s";
        OnUnitActiveSec = "${toString cfg.interval}s";
        AccuracySec = "5s";
      };
    };
  };
}
