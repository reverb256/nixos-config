{
  config,
  lib,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
  cfg = config.services.self-healing-alerts;
in {
  options.services.self-healing-alerts = {
    enable = lib.mkEnableOption "Self-healing alerts via Plasma notifications";

    monitoredServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "kubelet"
        "kube-apiserver"
        "kube-scheduler"
        "kube-controller-manager"
        "containerd"
        "etcd"
        "keepalived"
        "ai-gateway"
        "gpu-proxy"
      ];
      description = "Systemd services to monitor for failures and restarts";
    };

    enableCircuitBreakerAlerts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable alerts for circuit breaker state changes";
    };

    enableVIPFailoverAlerts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable alerts for VIP failover events";
    };

    enableResourceAlerts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable alerts for resource thresholds (memory, disk)";
    };

    memoryThreshold = lib.mkOption {
      type = lib.types.int;
      default = 90;
      description = "Memory usage percentage to trigger alert";
    };

    diskThreshold = lib.mkOption {
      type = lib.types.int;
      default = 90;
      description = "Disk usage percentage to trigger alert";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      libnotify
      coreutils
    ];

    environment.etc."self-healing-alerts/alert.sh".source = pkgs.writeShellScript "self-healing-alert" ''
      #!/bin/bash

      ALERT_TYPE="''${1:-info}"
      MESSAGE="''${2:-Self-healing event detected}"
      URGENCY="''${3:-normal}"

      case "''${URGENCY}" in
        critical) TIMEOUT=0 ;;
        high) TIMEOUT=10000 ;;
        normal) TIMEOUT=5000 ;;
        low) TIMEOUT=3000 ;;
        *) TIMEOUT=5000 ;;
      esac

      case "''${ALERT_TYPE}" in
        failure) ICON="dialog-error" ;;
        restart) ICON="view-refresh" ;;
        failover) ICON="network-vpn" ;;
        circuit_breaker) ICON="dialog-warning" ;;
        resource) ICON="drive-harddisk" ;;
        recovery) ICON="dialog-ok" ;;
        *) ICON="dialog-information" ;;
      esac

      if command -v notify-send >/dev/null 2>&1; then
        notify-send \
          --icon="''${ICON}" \
          --urgency="''${URGENCY}" \
          --expire-time="''${TIMEOUT}" \
          "Self-Healing: ''${ALERT_TYPE}" \
          "''${MESSAGE}"
      else
        echo "ALERT [''${ALERT_TYPE}] ''${MESSAGE}" | systemd-cat -t self-healing -p warn
      fi
    '';

    systemd.paths.self-healing-monitor-services = lib.mkIf (cfg.monitoredServices != []) {
      description = "Monitor service failures for self-healing alerts";
      wantedBy = ["multi-user.target"];
      pathConfig = {
        DirectoryNotEmpty = "/run/self-healing/failures";
        MakeDirectory = true;
      };
    };

    systemd.services.self-healing-monitor-services = {
      description = "Service failure monitor for self-healing alerts";
      after = ["network.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeShellScript "service-failure-monitor" ''
          #!/bin/bash
          set -euo pipefail

          ALERT_SCRIPT="/etc/self-healing-alerts/alert.sh"
          MONITOR_DIR="/run/self-healing/failures"
          STATE_DIR="/run/self-healing/state"

          mkdir -p "''${MONITOR_DIR}" "''${STATE_DIR}"

          declare -A LAST_NOTIFIED

          SERVICES="${lib.concatStringsSep " " cfg.monitoredServices}"

          monitor_services() {
            while true; do
              for service in ''${SERVICES}; do
                if systemctl is-failed --quiet "''${service}.service" 2>/dev/null; then
                  STATE_FILE="''${STATE_DIR}/''${service}"

                  if [ -f "''${STATE_FILE}" ]; then
                    LAST_STATE=$(cat "''${STATE_FILE}")
                    if [ "''${LAST_STATE}" = "failed" ]; then
                      continue
                    fi
                  fi

                  ''${ALERT_SCRIPT} failure "''${service} has entered failed state" critical

                  echo "failed" > "''${STATE_FILE}"

                elif systemctl is-active --quiet "''${service}.service" 2>/dev/null; then
                  STATE_FILE="''${STATE_DIR}/''${service}"

                  if [ -f "''${STATE_FILE}" ] && [ "$(cat "''${STATE_FILE}")" = "failed" ]; then
                    ''${ALERT_SCRIPT} recovery "''${service} has recovered" normal
                  fi

                  echo "active" > "''${STATE_FILE}"
                fi
              done

              sleep 10
            done
          }

          monitor_services
        '';
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    systemd.services.self-healing-monitor-restarts = lib.mkIf (cfg.monitoredServices != []) {
      description = "Monitor service restarts for self-healing alerts";
      after = ["network.target" "systemd-journald.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "restart-monitor" ''
          #!/bin/bash

          ALERT_SCRIPT="/etc/self-healing-alerts/alert.sh"
          STATE_DIR="/run/self-healing/restarts"

          mkdir -p "''${STATE_DIR}"

          declare -A RESTART_COUNT
          declare -A LAST_RESTART_TIME

          SERVICES="${lib.concatStringsSep " " cfg.monitoredServices}"

          journalctl -f -n 0 --since now \
            --grep "Started.*\.service" \
            -o cat | while read -r line; do

            for service in ''${SERVICES}; do
              if echo "''${line}" | grep -q "''${service}"; then
                NOW=$(date +%s)
                STATE_FILE="''${STATE_DIR}/''${service}"

                if [ ! -f "''${STATE_FILE}" ]; then
                  echo "0 ''${NOW}" > "''${STATE_FILE}"
                  continue
                fi

                read -r COUNT LAST_TIME < "''${STATE_FILE}"

                if [ $((NOW - LAST_TIME)) -ge 5 ]; then
                  NEW_COUNT=$((COUNT + 1))

                  ''${ALERT_SCRIPT} restart "''${service} restarted (count: ''${NEW_COUNT})" normal

                  if [ $((NOW - LAST_TIME)) -le 300 ] && [ "''${COUNT}" -ge 3 ]; then
                    ''${ALERT_SCRIPT} failure "''${service} restarting excessively! (count: ''${NEW_COUNT})" critical
                  fi

                  echo "''${NEW_COUNT} ''${NOW}" > "''${STATE_FILE}"
                fi

                break
              fi
            done
          done
        '';
        Restart = "on-failure";
        RestartSec = "60s";
      };
    };

    systemd.services.self-healing-monitor-vip = lib.mkIf cfg.enableVIPFailoverAlerts {
      description = "Monitor VIP failover events";
      after = ["keepalived.service"];
      wants = ["keepalived.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "vip-monitor" ''
          #!/bin/bash

          ALERT_SCRIPT="/etc/self-healing-alerts/alert.sh"
          STATE_FILE="/run/self-healing/vip-state"
          VIP=cluster.kubernetes.vip

          mkdir -p "$(dirname "''${STATE_FILE}")"

          get_state() {
            if ip addr show | grep -q "''${VIP}"; then
              echo "master"
            else
              echo "backup"
            fi
          }

          CURRENT_STATE=$(get_state)

          if [ -f "''${STATE_FILE}" ]; then
            PREV_STATE=$(cat "''${STATE_FILE}")

            if [ "''${PREV_STATE}" != "''${CURRENT_STATE}" ]; then
              HOSTNAME=$(hostname)
              case "''${CURRENT_STATE}" in
                master)
                  ''${ALERT_SCRIPT} failover "''${HOSTNAME} is now MASTER (VIP acquired)" normal
                  ;;
                backup)
                  ''${ALERT_SCRIPT} failover "''${HOSTNAME} is now BACKUP (VIP lost)" warning
                  ;;
              esac
            fi
          fi

          echo "''${CURRENT_STATE}" > "''${STATE_FILE}"
        '';
      };
    };

    systemd.timers.self-healing-monitor-vip = lib.mkIf cfg.enableVIPFailoverAlerts {
      description = "Periodic VIP state monitoring";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnUnitActiveSec = "10s";
        AccuracySec = "1s";
      };
    };

    systemd.services.self-healing-monitor-resources = lib.mkIf cfg.enableResourceAlerts {
      description = "Monitor resource thresholds";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "resource-monitor" ''
          #!/bin/bash

          ALERT_SCRIPT="/etc/self-healing-alerts/alert.sh"
          STATE_DIR="/run/self-healing/resources"

          mkdir -p "''${STATE_DIR}"

          check_memory() {
            MEM_PERCENT=$(free | awk '/Mem/{printf("%.0f"), ($3/$2)*100}')
            MEM_STATE="''${STATE_DIR}/memory"
            THRESHOLD=${toString cfg.memoryThreshold}

            if [ "''${MEM_PERCENT}" -ge "''${THRESHOLD}" ]; then
              if [ ! -f "''${MEM_STATE}" ] || [ "$(cat "''${MEM_STATE}")" != "alert" ]; then
                ''${ALERT_SCRIPT} resource "High memory usage: ''${MEM_PERCENT}%" warning
                echo "alert" > "''${MEM_STATE}"
              fi
            else
              if [ -f "''${MEM_STATE}" ]; then
                echo "ok" > "''${MEM_STATE}"
              fi
            fi
          }

          check_disk() {
            THRESHOLD=${toString cfg.diskThreshold}

            df -H | grep -vE '^Filesystem|tmpfs|cdrom|devtmpfs' | while read -r line; do
              USAGE=$(echo "''${line}" | awk '{print $5}' | sed 's/%//')
              MOUNT=$(echo "''${line}" | awk '{print $6}')

              if [ "''${USAGE}" -ge "''${THRESHOLD}" ]; then
                STATE_FILE="''${STATE_DIR}/disk-$(echo "''${MOUNT}" | tr '/' '_')"

                if [ ! -f "''${STATE_FILE}" ] || [ "$(cat "''${STATE_FILE}")" != "alert" ]; then
                  ''${ALERT_SCRIPT} resource "High disk usage on ''${MOUNT}: ''${USAGE}%" warning
                  echo "alert" > "''${STATE_FILE}"
                fi
              else
                STATE_FILE="''${STATE_DIR}/disk-$(echo "''${MOUNT}" | tr '/' '_')"
                if [ -f "''${STATE_FILE}" ]; then
                  echo "ok" > "''${STATE_FILE}"
                fi
              fi
            done
          }

          check_memory
          check_disk
        '';
      };
    };

    systemd.timers.self-healing-monitor-resources = lib.mkIf cfg.enableResourceAlerts {
      description = "Periodic resource monitoring";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnUnitActiveSec = "1m";
        AccuracySec = "1s";
      };
    };

    systemd.services.self-healing-monitor-circuit-breaker = lib.mkIf cfg.enableCircuitBreakerAlerts {
      description = "Monitor circuit breaker state changes";
      after = ["network.target" "ai-gateway.service"];
      wants = ["ai-gateway.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "circuit-breaker-monitor" ''
          #!/bin/bash

          ALERT_SCRIPT="/etc/self-healing-alerts/alert.sh"
          METRICS_URL="http://127.0.0.1:8080/metrics"
          STATE_DIR="/run/self-healing/circuit-breaker"

          mkdir -p "''${STATE_DIR}"

          if ! curl -sf -o /dev/null "''${METRICS_URL}"; then
            exit 0
          fi

          curl -s "''${METRICS_URL}" | grep "^gateway_circuit_breaker_state" | while read -r line; do
            BACKEND=$(echo "''${line}" | sed -n 's/.*backend_name="\(.*\)".*/\1/p')
            STATE=$(echo "''${line}" | awk '{print $2}')

            STATE_FILE="''${STATE_DIR}/''${BACKEND}"

            case "''${STATE}" in
              0) STATE_NAME="CLOSED" ;;
              1) STATE_NAME="OPEN" ;;
              2) STATE_NAME="HALF_OPEN" ;;
              *) STATE_NAME="UNKNOWN" ;;
            esac

            if [ -f "''${STATE_FILE}" ]; then
              PREV_STATE_NAME=$(cat "''${STATE_FILE}")

              if [ "''${PREV_STATE_NAME}" != "''${STATE_NAME}" ]; then
                case "''${STATE_NAME}" in
                  OPEN)
                    ''${ALERT_SCRIPT} circuit_breaker "Circuit breaker OPEN for ''${BACKEND}" critical
                    ;;
                  HALF_OPEN)
                    ''${ALERT_SCRIPT} circuit_breaker "Circuit breaker HALF_OPEN for ''${BACKEND} (testing recovery)" normal
                    ;;
                  CLOSED)
                    ''${ALERT_SCRIPT} recovery "Circuit breaker CLOSED for ''${BACKEND} (recovered)" normal
                    ;;
                esac
              fi
            fi

            echo "''${STATE_NAME}" > "''${STATE_FILE}"
          done
        '';
      };
    };

    systemd.timers.self-healing-monitor-circuit-breaker = lib.mkIf cfg.enableCircuitBreakerAlerts {
      description = "Periodic circuit breaker monitoring";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnUnitActiveSec = "30s";
        AccuracySec = "1s";
      };
    };
  };
}
