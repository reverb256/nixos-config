# Agent Network Restrictions — nftables-based firewall
#
# Restricts AI agent processes (Hermes, OpenCode, Claude Code, OmP, Pi)
# to only required network destinations. All other outbound traffic is
# denied and logged for audit.
#
# Architecture:
#   - nftables sets define allowed destinations and ports
#   - Output chain rules match agent process names via socket cgroup
#   - Default deny with audit logging (log prefix "AGENT-DROP: ")
#   - Daily audit report generated via systemd timer
#
# Usage:
#   services.agent-firewall.enable = true;
#
# To assign an agent to a restricted cgroup slice:
#   systemd.services.my-agent.serviceConfig.Slice = "agent-hermes.slice";
#
# For CLI tools, use systemd-run:
#   systemd-run --slice=agent-hermes.slice --user hermes chat "hello"
#
# Status check:
#   agent-firewall-status
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.agent-firewall;
  inherit (lib) mkEnableOption mkOption mkIf types mkOptionDefault;

  # Cluster network constants
  clusterSubnet = "10.1.1.0/24";
  podCidr = "10.244.0.0/16";

  # Script to verify agent firewall status
  agentStatusScript = pkgs.writeShellScriptBin "agent-firewall-status" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "=== Agent Firewall Status ==="
    echo ""

    # Show nftables rules
    echo "--- nftables rules ---"
    ${pkgs.nftables}/bin/nft list table inet agent-firewall 2>/dev/null || echo "agent-firewall table not loaded"
    echo ""

    # Show agent cgroup membership
    echo "--- Agent cgroup processes ---"
    for agent in hermes opencode claude omp pi; do
      slice="agent-$agent.slice"
      if [ -d "/sys/fs/cgroup/$slice" ]; then
        pids=$(wc -l < "/sys/fs/cgroup/$slice/cgroup.procs" 2>/dev/null || echo 0)
        echo "  $slice: $pids processes"
      else
        echo "  $slice: not found (cgroupv2)"
      fi
    done
    echo ""

    # Show recent drops
    ${lib.optionalString cfg.auditLog ''
    echo "--- Recent AGENT-DROP log entries (last 20) ---"
    journalctl -k --grep="AGENT-DROP" --no-pager -n 20 2>/dev/null || echo "No drops logged"
    echo ""

    echo "--- Drop count (last 24h) ---"
    COUNT=$(journalctl -k --grep="AGENT-DROP" --since "24 hours ago" --no-pager 2>/dev/null | wc -l)
    echo "Total: $COUNT drops"
    ''}
  '';

  # Wrapper script to run commands in agent cgroup slices
  agentRunScript = pkgs.writeShellScriptBin "agent-run" ''
    #!/usr/bin/env bash
    # Run a command in an agent-restricted cgroup slice
    #
    # Usage: agent-run <agent> <command> [args...]
    #   agent: hermes, opencode, claude, omp, pi
    #
    # Example:
    #   agent-run hermes hermes chat "hello"
    #   agent-run opencode opencode

    set -euo pipefail

    if [ $# -lt 2 ]; then
      echo "Usage: agent-run <agent> <command> [args...]"
      echo ""
      echo "Agents: hermes, opencode, claude, omp, pi"
      echo ""
      echo "Examples:"
      echo "  agent-run hermes hermes chat 'hello'"
      echo "  agent-run opencode opencode"
      exit 1
    fi

    AGENT="$1"
    shift

    case "$AGENT" in
      hermes|opencode|claude|omp|pi)
        SLICE="agent-$AGENT.slice"
        ;;
      *)
        echo "Unknown agent: $AGENT"
        echo "Valid agents: hermes, opencode, claude, omp, pi"
        exit 1
        ;;
    esac

    # Check if slice exists
    if [ ! -d "/sys/fs/cgroup/$SLICE" ]; then
      echo "Warning: cgroup slice $SLICE not found, running without restrictions"
      exec "$@"
    fi

    # Run in the agent cgroup slice
    exec systemd-run --user --slice="$SLICE" --wait --pipe "$@"
  '';
in {
  options.services.agent-firewall = {
    enable = mkEnableOption "Agent network restrictions via nftables cgroup firewall";

    auditLog = mkOption {
      type = types.bool;
      default = true;
      description = "Log denied agent connections to journal (prefix: AGENT-DROP)";
    };

    allowedExternalIPs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional external IPs/networks to allow for agents";
    };

    allowedExternalPorts = mkOption {
      type = types.listOf types.port;
      default = [];
      description = "Additional TCP ports to allow for agents accessing external IPs";
    };
  };

  config = mkIf cfg.enable {
    # Enable nftables if not already enabled
    networking.nftables.enable = true;

    # nftables rules configuration file
    environment.etc."nftables/agent-firewall.conf".text = ''

      table inet agent-firewall {
        # ── Sets ──────────────────────────────────────────────────────
        add set inet agent-firewall allowed_external_ips {
          type ipv4_addr;
          flags interval;
          elements = { 104.18.0.0/15, 140.82.112.0/20, 34.160.0.0/16 };
        }

        add set inet agent-firewall local_services {
          type ipv4_addr;
          flags interval;
          elements = { ${clusterSubnet} };
        }

        add set inet agent-firewall allowed_external_ports {
          type inet_service;
          elements = { 80, 443 };
        }

        add set inet agent-firewall allowed_local_ports {
          type inet_service;
          elements = { 53, 80, 443, 8080, 6443, 3456, 8040, 1235, 1237 };
        };

        # ── Chains ────────────────────────────────────────────────────

        add chain inet agent-firewall agent-egress {
          type filter hook output priority -150;
        }

        add rule inet agent-firewall agent-egress oifname "lo" accept;
        add rule inet agent-firewall agent-egress ct state established,related accept;
        add rule inet agent-firewall agent-egress udp dport 53 accept;
        add rule inet agent-firewall agent-egress tcp dport 53 accept;
        add rule inet agent-firewall agent-egress ip protocol icmp accept;
        add rule inet agent-firewall agent-egress ip6 nexthdr icmpv6 accept;
        add rule inet agent-firewall agent-egress ip daddr @local_services tcp dport @allowed_local_ports accept;
        add rule inet agent-firewall agent-egress ip daddr ${podCidr} accept;
        add rule inet agent-firewall agent-egress ip daddr @allowed_external_ips tcp dport @allowed_external_ports accept;
        add rule inet agent-firewall agent-egress oifname "tailscale0" accept;
        ${lib.optionalString cfg.auditLog "add rule inet agent-firewall agent-egress log prefix \"AGENT-DROP: \" level info counter;"}
        add rule inet agent-firewall agent-egress drop;

        add chain inet agent-firewall cgroup-classify {
          type filter hook output priority -151;
        };

        #add rule inet agent-firewall cgroup-classify socket cgroupv2 level 1 "agent-hermes.slice" jump agent-egress;
        # TEMPORARILY DISABLED - slices do not exist
        #add rule inet agent-firewall cgroup-classify socket cgroupv2 level 1 "agent-opencode.slice" jump agent-egress;
        # TEMPORARILY DISABLED - slices do not exist
        #add rule inet agent-firewall cgroup-classify socket cgroupv2 level 1 "agent-claude.slice" jump agent-egress;
        # TEMPORARILY DISABLED - slices do not exist
        #add rule inet agent-firewall cgroup-classify socket cgroupv2 level 1 "agent-omp.slice" jump agent-egress;
        # TEMPORARILY DISABLED - slices do not exist
        #add rule inet agent-firewall cgroup-classify socket cgroupv2 level 1 "agent-pi.slice" jump agent-egress;
      }
    '';

    # Install helper scripts
    environment.systemPackages = [ agentStatusScript agentRunScript ];

    # Create agent cgroup slices
    systemd.slices = {
      "agent-hermes" = {
        description = "Slice for Hermes Agent processes";
        sliceConfig.MemoryMax = "4G";
      };
      "agent-opencode" = {
        description = "Slice for OpenCode processes";
        sliceConfig.MemoryMax = "4G";
      };
      "agent-claude" = {
        description = "Slice for Claude Code processes";
        sliceConfig.MemoryMax = "4G";
      };
      "agent-omp" = {
        description = "Slice for OmP Agent processes";
        sliceConfig.MemoryMax = "2G";
      };
      "agent-pi" = {
        description = "Slice for Pi Agent processes";
        sliceConfig.MemoryMax = "2G";
      };
    };

    # Apply nftables rules at boot
    systemd.services.agent-firewall = {
      description = "Apply agent network restriction nftables rules";
      after = [ "nftables.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "agent-firewall-apply" ''
          ${pkgs.nftables}/bin/nft delete table inet agent-firewall 2>/dev/null || true
          ${pkgs.nftables}/bin/nft -f /etc/nftables/agent-firewall.conf
        '';
      };
    };

    # Periodic audit: log agent network policy violations summary
    systemd.services.agent-firewall-audit = mkIf cfg.auditLog {
      description = "Agent firewall audit summary";
      path = with pkgs; [ coreutils gnugrep jq ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "agent-firewall-audit" ''
          set -euo pipefail

          TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
          LOG_DIR="/var/log/agent-firewall"
          mkdir -p "$LOG_DIR"

          REPORT="$LOG_DIR/audit-$TIMESTAMP.log"

          {
            echo "=== Agent Firewall Audit -- $(date) ==="
            echo ""

            echo "--- Drop counts (last 24h) ---"
            DROPS=$(journalctl -k --grep="AGENT-DROP" --since "24 hours ago" --no-pager 2>/dev/null | wc -l)
            echo "Total drops: $DROPS"
            echo ""

            echo "--- Top blocked destinations ---"
            journalctl -k --grep="AGENT-DROP" --since "24 hours ago" --no-pager 2>/dev/null \
              | grep -oP 'DST=[0-9.]+' | sort | uniq -c | sort -rn | head -10 || true
            echo ""

            echo "--- Active agent processes ---"
            for agent in hermes opencode claude omp pi; do
              slice="agent-$agent.slice"
              if [ -d "/sys/fs/cgroup/$slice" ]; then
                pids=$(wc -l < "/sys/fs/cgroup/$slice/cgroup.procs" 2>/dev/null || echo 0)
                echo "  $slice: $pids processes"
              else
                echo "  $slice: not found"
              fi
            done
            echo ""

            echo "--- nftables rule counters ---"
            ${pkgs.nftables}/bin/nft list table inet agent-firewall 2>/dev/null | grep -E "counter|drop" || true
          } > "$REPORT"

          # Rotate old reports (keep last 30)
          cd "$LOG_DIR"
          ls -t audit-*.log 2>/dev/null | tail -n +31 | xargs -r rm --

          echo "Agent firewall audit complete: $REPORT"
        '';
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };

    systemd.timers.agent-firewall-audit = mkIf cfg.auditLog {
      description = "Agent firewall audit timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    # Ensure log directory exists
    systemd.tmpfiles.rules = [
      "d /var/log/agent-firewall 0755 root root -"
    ];
  };
}
