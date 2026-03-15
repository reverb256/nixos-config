# Self-Healing Alerts - Plasma Desktop Notifications
# Monitors service health and sends Plasma notifications for self-healing events
#
# Features:
# - Service failure notifications
# - Service restart notifications
# - Circuit breaker state changes
# - VIP failover notifications
# - Resource threshold alerts
#
# Requires: Plasma desktop (knotify5/notify-send)

{ config, lib, pkgs, ... }:

let
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
    # Required packages
    environment.systemPackages = with pkgs; [
      libnotify  # For notify-send command
      coreutils  # For df, free commands
    ];

    # Create alert notification script
    environment.etc."self-healing-alerts/alert.sh".source = pkgs.writeShellScript "self-healing-alert" ''
      #!/bin/bash
      # Self-Healing Alert Notification Script
      # Usage: alert.sh <type> <message> [urgency]
      # Types: failure, restart, failover, circuit_breaker, resource, recovery

      ALERT_TYPE="''${1:-info}"
      MESSAGE="''${2:-Self-healing event detected}"
      URGENCY="''${3:-normal}"  # low, normal, critical

      # Map urgency to notification timeout (ms)
      case "''${URGENCY}" in
        critical) TIMEOUT=0 ;;     # Sticky notification
        high) TIMEOUT=10000 ;;     # 10 seconds
        normal) TIMEOUT=5000 ;;    # 5 seconds
        low) TIMEOUT=3000 ;;       # 3 seconds
        *) TIMEOUT=5000 ;;
      esac

      # Map type to icon
      case "''${ALERT_TYPE}" in
        failure) ICON="dialog-error" ;;
        restart) ICON="view-refresh" ;;
        failover) ICON="network-vpn" ;;
        circuit_breaker) ICON="dialog-warning" ;;
        resource) ICON="drive-harddisk" ;;
        recovery) ICON="dialog-ok" ;;
        *) ICON="dialog-information" ;;
      esac

      # Send Plasma notification
      # Try notify-send first (works with Plasma)
      if command -v notify-send >/dev/null 2>&1; then
        notify-send \
          --icon="''${ICON}" \
          --urgency="''${URGENCY}" \
          --expire-time="''${TIMEOUT}" \
          "Self-Healing: ''${ALERT_TYPE}" \
          "''${MESSAGE}"
      else
        # Fallback: write to journal
        echo "ALERT [''${ALERT_TYPE}] ''${MESSAGE}" | systemd-cat -t self-healing -p warn
      fi
    '';

    # Service failure monitoring (monitoring path for all services)
    systemd.paths.self-healing-monitor-services = lib.mkIf (cfg.monitoredServices != []) {
      description = "Monitor service failures for self-healing alerts";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        DirectoryNotEmpty = "/run/self-healing/failures";
        MakeDirectory = true;
      };
    };

    systemd.services.self-healing-monitor-services = {
      description = "Service failure monitor for self-healing alerts";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeShellScript "service-failure-monitor" ''
          #!/bin/bash
          set -euo pipefail

          ALERT_SCRIPT="/etc/self-healing-alerts/alert.sh"
          MONITOR_DIR="/run/self-healing/failures"
          STATE_DIR="/run/self-healing/state"

          mkdir -p "''${MONITOR_DIR}" "''${STATE_DIR}"

          # Track previous failures to avoid spam
          declare -A LAST_NOTIFIED

          # Services to monitor
          SERVICES="''${cfg.monitoredServices[@]}"

          monitor_services() {
            while true; do
              for service in ''${SERVICES}; do
                # Check if service is failed
                if systemctl is-failed --quiet "''${service}.service" 2>/dev/null; then
                  STATE_FILE="''${STATE_DIR}/''${service}"

                  # Check if we already notified about this failure
                  if [ -f "''${STATE_FILE}" ]; then
                    LAST_STATE=$(cat "''${STATE_FILE}")
                    if [ "''${LAST_STATE}" = "failed" ]; then
                      continue  # Already notified, skip
                    fi
                  fi

                  # New failure detected
                  ''${ALERT_SCRIPT} failure "''${service} has entered failed state" critical

                  # Record state
                  echo "failed" > "''${STATE_FILE}"

                # Check if service recovered (active)
                elif systemctl is-active --quiet "''${service}.service" 2>/dev/null; then
                  STATE_FILE="''${STATE_DIR}/''${service}"

                  # Check if it was previously failed
                  if [ -f "''${STATE_FILE}" ] && [ "$(cat "''${STATE_FILE}")" = "failed" ]; then
                    # Service recovered!
                    ''${ALERT_SCRIPT} recovery "''${service} has recovered" normal
                  fi

                  # Update state
                  echo "active" > "''${STATE_FILE}"
                fi
              done

              # Sleep before next check
              sleep 10
            done
          }

          # Start monitoring in background
          monitor_services
        '';
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    # Service restart monitoring (via journal)
    systemd.services.self-healing-monitor-restarts = lib.mkIf (cfg.monitoredServices != []) {
      description = "Monitor service restarts for self-healing alerts";
      after = [ "network.target" "systemd-journald.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "restart-monitor" ''
          #!/bin/bash
          # Monitor for service restart events in real-time
          # This runs continuously and detects restart patterns

          ALERT_SCRIPT="/etc/self-healing-alerts/alert.sh"
          STATE_DIR="/run/self-healing/restarts"

          mkdir -p "''${STATE_DIR}"

          # Track restart counts
          declare -A RESTART_COUNT
          declare -A LAST_RESTART_TIME

          # Services to monitor
          SERVICES="''${cfg.monitoredServices[@]}"

          # Follow journal for restart events
          journalctl -f -n 0 --since now \
            --grep "Started.*\.service" \
            -o cat | while read -r line; do

            # Extract service name from log line
            for service in ''${SERVICES}; do
              if echo "''${line}" | grep -q "''${service}"; then
                NOW=$(date +%s)
                STATE_FILE="''${STATE_DIR}/''${service}"

                # Initialize if first time
                if [ ! -f "''${STATE_FILE}" ]; then
                  echo "0 ''${NOW}" > "''${STATE_FILE}"
                  continue
                fi

                # Read previous restart info
                read -r COUNT LAST_TIME < "''${STATE_FILE}"

                # Check if this is a new restart (at least 5 seconds since last)
                if [ $((NOW - LAST_TIME)) -ge 5 ]; then
                  NEW_COUNT=$((COUNT + 1))

                  # Alert on restart
                  ''${ALERT_SCRIPT} restart "''${service} restarted (count: ''${NEW_COUNT})" normal

                  # Alert on excessive restarts (>3 in 5 minutes)
                  if [ $((NOW - LAST_TIME)) -le 300 ] && [ "''${COUNT}" -ge 3 ]; then
                    ''${ALERT_SCRIPT} failure "''${service} restarting excessively! (count: ''${NEW_COUNT})" critical
                  fi

                  # Update state
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

    # VIP failover monitoring
    systemd.services.self-healing-monitor-vip = lib.mkIf cfg.enableVIPFailoverAlerts {
      description = "Monitor VIP failover events";
      after = [ "keepalived.service" ];
      wants = [ "keepalived.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "vip-monitor" ''
          #!/bin/bash
          # Monitor keepalived state changes

          ALERT_SCRIPT="/etc/self-healing-alerts/alert.sh"
          STATE_FILE="/run/self-healing/vip-state"
          VIP="10.1.1.100"

          mkdir -p "$(dirname "''${STATE_FILE}")"

          # Get current state
          get_state() {
            if ip addr show | grep -q "''${VIP}"; then
              echo "master"
            else
              echo "backup"
            fi
          }

          # Check if state changed
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

          # Save current state
          echo "''${CURRENT_STATE}" > "''${STATE_FILE}"
        '';
      };
    };

    # Timer for VIP monitoring (every 10 seconds)
    systemd.timers.self-healing-monitor-vip = lib.mkIf cfg.enableVIPFailoverAlerts {
      description = "Periodic VIP state monitoring";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnUnitActiveSec = "10s";
        AccuracySec = "1s";
      };
    };

    # Resource threshold monitoring
    systemd.services.self-healing-monitor-resources = lib.mkIf cfg.enableResourceAlerts {
      description = "Monitor resource thresholds";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "resource-monitor" ''
          #!/bin/bash

          ALERT_SCRIPT="/etc/self-healing-alerts/alert.sh"
          STATE_DIR="/run/self-healing/resources"

          mkdir -p "''${STATE_DIR}"

          # Memory check
          check_memory() {
            MEM_PERCENT=$(free | awk '/Mem/{printf("%.0f"), ($3/$2)*100}')
            MEM_STATE="''${STATE_DIR}/memory"
            THRESHOLD=''${cfg.memoryThreshold}

            if [ "''${MEM_PERCENT}" -ge "''${THRESHOLD}" ]; then
              if [ ! -f "''${MEM_STATE}" ] || [ "$(cat "''${MEM_STATE}")" != "alert" ]; then
                ''${ALERT_SCRIPT} resource "High memory usage: ''${MEM_PERCENT}%" warning
                echo "alert" > "''${MEM_STATE}"
              fi
            else
              # Reset state if below threshold
              if [ -f "''${MEM_STATE}" ]; then
                echo "ok" > "''${MEM_STATE}"
              fi
            fi
          }

          # Disk check (all mounted filesystems)
          check_disk() {
            THRESHOLD=''${cfg.diskThreshold}

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
                # Reset state if below threshold
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

    # Timer for resource monitoring (every minute)
    systemd.timers.self-healing-monitor-resources = lib.mkIf cfg.enableResourceAlerts {
      description = "Periodic resource monitoring";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnUnitActiveSec = "1m";
        AccuracySec = "1s";
      };
    };

    # Circuit breaker monitoring (via metrics endpoint)
    systemd.services.self-healing-monitor-circuit-breaker = lib.mkIf cfg.enableCircuitBreakerAlerts {
      description = "Monitor circuit breaker state changes";
      after = [ "network.target" "ai-gateway.service" ];
      wants = [ "ai-gateway.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "circuit-breaker-monitor" ''
          #!/bin/bash
          # Monitor AI Gateway circuit breaker state via metrics

          ALERT_SCRIPT="/etc/self-healing-alerts/alert.sh"
          METRICS_URL="http://127.0.0.1:8080/metrics"
          STATE_DIR="/run/self-healing/circuit-breaker"

          mkdir -p "''${STATE_DIR}"

          # Skip if gateway is not running
          if ! curl -sf -o /dev/null "''${METRICS_URL}"; then
            exit 0
          fi

          # Parse circuit breaker states from metrics
          # Format: gateway_circuit_breaker_state{backend_name="..."} N
          curl -s "''${METRICS_URL}" | grep "^gateway_circuit_breaker_state" | while read -r line; do
            # Extract backend name and state
            BACKEND=$(echo "''${line}" | sed -n 's/.*backend_name="\(.*\)".*/\1/p')
            STATE=$(echo "''${line}" | awk '{print $2}')

            STATE_FILE="''${STATE_DIR}/''${BACKEND}"

            case "''${STATE}" in
              0) STATE_NAME="CLOSED" ;;
              1) STATE_NAME="OPEN" ;;
              2) STATE_NAME="HALF_OPEN" ;;
              *) STATE_NAME="UNKNOWN" ;;
            esac

            # Check if state changed
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

            # Save current state
            echo "''${STATE_NAME}" > "''${STATE_FILE}"
          done
        '';
      };
    };

    # Timer for circuit breaker monitoring (every 30 seconds)
    systemd.timers.self-healing-monitor-circuit-breaker = lib.mkIf cfg.enableCircuitBreakerAlerts {
      description = "Periodic circuit breaker monitoring";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnUnitActiveSec = "30s";
        AccuracySec = "1s";
      };
    };
  };
}
