# Kubernetes API Server Restart Logger
# Logs all kube-apiserver restarts with timestamps
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.kube-apiserver-logger;
in {
  options.services.kube-apiserver-logger = {
    enable = lib.mkEnableOption "kube-apiserver restart logger";
    
    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/kube-apiserver-restarts.log";
      description = "Log file path for API server restarts";
    };
  };

  config = lib.mkIf cfg.enable {
    # systemd service to monitor API server restarts
    systemd.services.kube-apiserver-logger = {
      description = "Kubernetes API Server Restart Logger";
      after = ["kube-apiserver.service"];
      wants = ["kube-apiserver.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = ''
          ${pkgs.bash}/bin/bash -c '
            # Monitor kube-apiserver restarts
            LOG_FILE="${lib.escapeShellArg cfg.logFile}"
            LAST_PID=""

            # Ensure log file exists
            touch "$LOG_FILE"
            chmod 644 "$LOG_FILE"

            while true; do
              # Get current kube-apiserver PID
              CURRENT_PID=$(systemctl show -p MainPID --value kube-apiserver.service 2>/dev/null || echo "0")

              # Check if PID changed (restart detected)
              if [[ -n "$LAST_PID" ]] && [[ "$CURRENT_PID" != "0" ]] && [[ "$CURRENT_PID" != "$LAST_PID" ]]; then
                {
                  echo "=========================================="
                  echo "🔄 kube-apiserver RESTART DETECTED"
                  echo "Time: $(date -Iseconds)"
                  echo "Previous PID: $LAST_PID"
                  echo "New PID: $CURRENT_PID"
                  echo "Node: $(hostname)"
                  echo "Uptime: $(uptime -p)"
                  echo "=========================================="
                  echo ""
                } >> "$LOG_FILE"

                # Also log to journal for visibility
                journalctl -t kube-apiserver-logger -n 1 --no-pager
              fi

              LAST_PID="$CURRENT_PID"
              sleep 5
            done
          '
        '';
        
        Restart = "always";
        RestartSec = "5s";
        
        # Security settings
        ReadOnlyPaths = "/";
        ReadWritePaths = [cfg.logFile];
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    # logrotate configuration for the log file
    services.logrotate.settings = {
      kube-apiserver-restarts = {
        files = [cfg.logFile];
        rotate = 52;  # Keep 52 weeks (1 year) of logs
        weekly = true;
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
        maxage = 365;
      };
    };
  };
}
