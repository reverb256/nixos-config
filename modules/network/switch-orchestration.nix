# NixOS Network Switch Orchestration Module
# TP-Link Switch Management and Topology Discovery
{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.networking.switch-orchestration;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.networking.switch-orchestration = {
    enable = mkEnableOption "TP-Link switch orchestration and management";

    switches = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            ip = mkOption {
              type = types.str;
              description = "Switch management IP address";
            };
            name = mkOption {
              type = types.str;
              description = "Switch identifier";
            };
            description = mkOption {
              type = types.str;
              description = "Zone or function description";
            };
            model = mkOption {
              type = types.str;
              default = "TL-SG105E";
              description = "Switch model (e.g., TL-SG105E)";
            };
            ports = mkOption {
              type = types.int;
              default = 5;
              description = "Number of ports";
            };
          };
        }
      );
      default = [
        {
          ip = "10.1.1.10";
          name = "switch1";
          description = "Gaming Zone";
        }
        {
          ip = "10.1.1.11";
          name = "switch2";
          description = "Mining Zone";
        }
        {
          ip = "10.1.1.12";
          name = "switch3";
          description = "Backup Storage";
        }
        {
          ip = "10.1.1.13";
          name = "switch4";
          description = "Management Network";
        }
      ];
    };

    credentials = mkOption {
      type = types.submodule {
        options = {
          username = mkOption {
            type = types.str;
            default = "admin";
            description = "Switch username";
          };
          password = mkOption {
            type = types.str;
            defaultFile = lib.mkOptionDefault {
              default = "/run/agenix/switch-password";
              example = "/run/agenix/switch-password";
            };
            description = "Switch password (use agenix secret)";
          };
        };
      };
      default = { };
    };

    vlans = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            id = mkOption {
              type = types.int;
              description = "VLAN ID";
            };
            name = mkOption {
              type = types.str;
              description = "VLAN name";
            };
            description = mkOption {
              type = types.str;
              description = "VLAN purpose";
            };
            priority = mkOption {
              type = types.int;
              default = 1;
              description = "VLAN priority for QoS";
            };
          };
        }
      );
      default = {
        gaming = {
          id = 10;
          name = "gaming";
          description = "Gaming traffic (WiVRn, Steam, Moonlight)";
          priority = 1;
        };
        ai = {
          id = 20;
          name = "ai";
          description = "AI services (LM Studio, Inference Gateway)";
          priority = 1;
        };
        storage = {
          id = 30;
          name = "storage";
          description = "Storage traffic (NFS, SMB)";
          priority = 1;
        };
        mining = {
          id = 40;
          name = "mining";
          description = "Mining traffic (XMig, lolMiner API)";
          priority = 1;
        };
        monitoring = {
          id = 50;
          name = "monitoring";
          description = "Monitoring traffic (Prometheus, Grafana)";
          priority = 1;
        };
        backup = {
          id = 60;
          name = "backup";
          description = "Backup storage traffic";
          priority = 1;
        };
        management = {
          id = 99;
          name = "management";
          description = "Switch management VLAN";
          priority = 0;
        };
      };
    };

    port_assignments = mkOption {
      type = types.attrs;
      default = {
        zephyr.gaming = {
          switch = "switch1";
          port = 1;
          vlan = "gaming";
        };
        zephyr.ai = {
          switch = "switch1";
          port = 2;
          vlan = "ai";
        };
        nexus.storage = {
          switch = "switch2";
          port = 1;
          vlan = "storage";
        };
        forge.mining = {
          switch = "switch2";
          port = 2;
          vlan = "mining";
        };
        sentry.monitoring = {
          switch = "switch3";
          port = 1;
          vlan = "monitoring";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [ 80 ];
    networking.firewall.allowedUDPPorts = [
      161
      29808
      29809
    ];
    networking.firewall.allowedTCPPortRanges = [
      {
        from = 9116;
        to = 9116;
      }
    ];

    environment.systemPackages = with pkgs; [
      # Python TP-Link switch management library
      (pkgs.python3.withPackages (ps: with ps; [ requests ]))

      # CLI Tools
      (pkgs.writeShellScriptBin "switch-discover" ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "TP-Link Switch Discovery Tool"
        echo "=============================="
        echo ""

        SWITCHES="10.1.1.10 10.1.1.11 10.1.1.12 10.1.1.13"
        DESCS="switch1:GamingZone switch2:MiningZone switch3:BackupStorage switch4:Management"

        I=0
        for switch in $SWITCHES; do
          echo -n "Checking $switch... "
          if timeout 2 bash -c "echo >/dev/tcp/$switch/80" 2>/dev/null; then
            STATUS="UP"
            curl -s -m 2 "http://$switch" | grep -o "TL-SG[0-9]*E" | head -1 || echo "TP-Link"
          else
            STATUS="DOWN"
            curl -s -m 2 "http://$switch" || true
          fi
          I=$((I+1))
        done
      '')

      (pkgs.writeShellScriptBin "switch-status" ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "Network Switch Status"
        echo "====================="
        echo ""

        SWITCHES="10.1.1.10:switch1 10.1.1.11:switch2 10.1.1.12:switch3 10.1.1.13:switch4"
        DESCS="switch1:GamingZone switch2:MiningZone switch3:BackupStorage switch4:Management"

        for entry in $SWITCHES; do
          switch="''${entry%%:*}"
          name="''${entry##*:}"
          echo "Switch: $switch ($name)"
          ping -c 2 -W 1 $switch 2>/dev/null && echo "  Status: ONLINE" || echo "  Status: OFFLINE"
          timeout 2 bash -c "echo >/dev/tcp/$switch/80" 2>/dev/null && echo "  Web UI: ACCESSIBLE" || echo "  Web UI: UNREACHABLE"
          echo ""
        done
      '')

      (pkgs.writeShellScriptBin "switch-topology" ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "Network Topology: Cluster Infrastructure"
        echo "======================================"
        echo ""
        echo "Switch Network: 10.1.1.0/24"
        echo "Gateway: 10.1.1.1"
        echo ""
        echo "Managed Switches:"
        echo "-------------------"
        echo ""
        echo "  switch1 (Gaming Zone)"
        echo "    IP: 10.1.1.10"
        echo "    Model: TL-SG105E"
        echo "    Ports: 5"
        echo ""
        echo "  switch2 (Mining Zone)"
        echo "    IP: 10.1.1.11"
        echo "    Model: TL-SG105E"
        echo "    Ports: 5"
        echo ""
        echo "  switch3 (Backup Storage)"
        echo "    IP: 10.1.1.12"
        echo "    Model: TL-SG105E"
        echo "    Ports: 5"
        echo ""
        echo "  switch4 (Management Network)"
        echo "    IP: 10.1.1.13"
        echo "    Model: TL-SG105E"
        echo "    Ports: 5"
        echo ""
        echo "Host Assignments:"
        echo "-----------------"
        echo ""
        echo "  zephyr-gaming: 10.1.1.10 Port 1 (VLAN: gaming)"
        echo "  zephyr-ai: 10.1.1.10 Port 2 (VLAN: ai)"
        echo "  nexus-storage: 10.1.1.11 Port 1 (VLAN: storage)"
        echo "  forge-mining: 10.1.1.11 Port 2 (VLAN: mining)"
        echo "  sentry-monitoring: 10.1.1.12 Port 1 (VLAN: monitoring)"
      '')

      (pkgs.writeShellScriptBin "switch-ctl" ''
                #!/usr/bin/env bash
                set -euo pipefail

                # switch-ctl - TP-Link Switch Management CLI
                # Usage: switch-ctl <command> [options]

                SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"
                PYTHON_LIB="''${SCRIPT_DIR}/../packages/tplink-switch/tplink_switch"

                # Default credentials from agenix secret
                CRED_FILE="/run/agenix/switch-admin"
                USERNAME="admin"
                PASSWORD=""

                # Read credentials from agenix secret
                if [[ -f "$CRED_FILE" ]]; then
                  PASSWORD=$(grep "^password=" "$CRED_FILE" | cut -d= -f2)
                fi

                # If no password found, use command line argument
                if [[ -z "$PASSWORD" ]]; then
                  echo "Warning: No password found in $CRED_FILE"
                  echo "Usage: switch-ctl <command> --password <password>"
                  exit 1
                fi

                usage() {
                  echo "switch-ctl - TP-Link Switch Management CLI"
                  echo ""
                  echo "Usage: switch-ctl <command> [options]"
                  echo ""
                  echo "Commands:"
                  echo "  status <ip>              Show switch status"
                  echo "  ports <ip>               Show port status"
                  echo "  vlan <ip>                Show VLAN configuration"
                  echo "  info <ip>                Show system information"
                  echo "  reboot <ip>              Reboot switch"
                  echo "  port-set <ip> <port> <0|1>  Enable (1) or disable (0) port"
                  echo "  discover                 Discover switches on network"
                  echo ""
                  echo "Options:"
                  echo "  --password <password>    Override password from secret"
                  echo "  --username <username>    Override username (default: admin)"
                  echo ""
                  echo "Examples:"
                  echo "  switch-ctl status 10.1.1.10"
                  echo "  switch-ctl ports 10.1.1.10"
                  echo "  switch-ctl vlan 10.1.1.10"
                  echo "  switch-ctl reboot 10.1.1.11"
                  echo "  switch-ctl port-set 10.1.1.10 3 1  # Enable port 3"
                }

                # Parse arguments
                COMMAND="''${1:-}"
                shift || true

                case "$COMMAND" in
                  status|ports|vlan|info|reboot|port-set)
                    ;;
                  discover)
                    # Use Python discover function
                    python3 -c "
        import sys
        sys.path.insert(0, '/etc/nixos/packages/tplink-switch')
        from tplink_switch import discover_switches
        switches = discover_switches()
        for s in switches:
            print(f'IP: {s['ip']}, MAC: {s['mac']}, Type: {s['type']}')"
                    exit 0
                    ;;
                  -h|--help|help)
                    usage
                    exit 0
                    ;;
                  "")
                    usage
                    exit 1
                    ;;
                  *)
                    echo "Unknown command: $COMMAND"
                    usage
                    exit 1
                    ;;
                esac

                # Parse optional password/username overrides
                while [[ $# -gt 0 ]]; do
                  case "$1" in
                    --password)
                      PASSWORD="''${2:-}"
                      shift 2
                      ;;
                    --username)
                      USERNAME="''${2:-}"
                      shift 2
                      ;;
                    *)
                      break
                      ;;
                  esac
                done

                # Get IP address
                IP="''${1:-}"
                if [[ -z "$IP" ]]; then
                  echo "Error: IP address required"
                  usage
                  exit 1
                fi

                # Execute command
                python3 -c "
        import sys
        sys.path.insert(0, '/etc/nixos/packages/tplink-switch')
        from tplink_switch import TPLinkSwitch

        switch = TPLinkSwitch('$IP', '$USERNAME', '$PASSWORD')

        if switch.login():
            print('Connected to $IP')
            command = '$COMMAND'

            if command == 'status':
                info = switch.get_system_info()
                print(f'Model: {info.get(\"model\", \"Unknown\")}')
                print(f'Hostname: {info.get(\"hostname\", \"Unknown\")}')
                print(f'IP: {info.get(\"ip\", \"Unknown\")}')
                print(f'MAC: {info.get(\"mac\", \"Unknown\")}')
                print(f'Firmware: {info.get(\"firmware\", \"Unknown\")}')
            elif command == 'ports':
                ports = switch.get_port_status()
                print('Port Status:')
                for p in ports:
                    status = 'UP' if p['status'] == 'up' else 'DOWN'
                    print(f'  Port {p[\"port\"]}: {status} ({p[\"speed\"]} Mbps)')
            elif command == 'vlan':
                vlans = switch.get_vlan_config()
                print('VLAN Configuration:')
                for vid, vlan in vlans.items():
                    print(f'  VLAN {vid}: {vlan[\"name\"]}')
            elif command == 'info':
                info = switch.get_system_info()
                for k, v in info.items():
                    print(f'{k}: {v}')
            elif command == 'reboot':
                if switch.reboot():
                    print('Switch reboot initiated')
                else:
                    print('Failed to reboot switch')
                    sys.exit(1)
            elif command == 'port-set':
                import sys
                port = sys.argv[4]
                state = sys.argv[5]
                if switch.set_port_state(int(port), state == '1'):
                    print(f'Port {port} set to {state}')
                else:
                    print(f'Failed to set port {port}')
                    sys.exit(1)

            switch.logout()
        else:
            print('Failed to connect to switch')
            sys.exit(1)
        " "$@"
      '')

      # SNMP monitoring tools
      prometheus-snmp-exporter
      python3
      python3Packages.requests
    ];

    systemd.services = {
      "switch-discovery" = {
        description = "TP-Link Switch Discovery Service";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "switch-discovery-run" ''
            #!/usr/bin/env bash
            /run/current-system/sw/bin/switch-discover > /etc/nixos/switch-discovery.log 2>&1
            echo "Discovery completed at $(date)" >> /etc/nixos/switch-discovery.log
          ''}";
        };
      };

      # SNMP Exporter for TP-Link switches
      "snmp-exporter-switches" = {
        description = "Prometheus SNMP Exporter for TP-Link Switches";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.prometheus-snmp-exporter}/bin/snmp_exporter --config.file=/etc/snmp-exporter/switches.yml";
          Restart = "on-failure";
          RestartSec = "10s";
        };
      };
    };

    # SNMP Exporter configuration for TP-Link switches
    environment.etc."snmp-exporter/switches.yml".text = ''
      modules:
        tplink_easy_smart:
          walk:
            - 1.3.6.1.2.1.1.1.0  # sysDescr
            - 1.3.6.1.2.1.1.5.0  # sysName
            - 1.3.6.1.2.1.1.6.0  # sysLocation
            - 1.3.6.1.2.1.2.2.1.2  # ifDescr
            - 1.3.6.1.2.1.2.2.1.5  # ifSpeed
            - 1.3.6.1.2.1.2.2.1.7  # ifAdminStatus
            - 1.3.6.1.2.1.2.2.1.8  # ifOperStatus
            - 1.3.6.1.2.1.2.2.1.10  # ifInOctets
            - 1.3.6.1.2.1.2.2.1.11  # ifInUcastPkts
            - 1.3.6.1.2.1.2.2.1.12  # ifInDiscards
            - 1.3.6.1.2.1.2.2.1.13  # ifInErrors
            - 1.3.6.1.2.1.2.2.1.14  # ifInUnknownProtos
            - 1.3.6.1.2.1.2.2.1.16  # ifOutOctets
            - 1.3.6.1.2.1.2.2.1.17  # ifOutUcastPkts
            - 1.3.6.1.2.1.2.2.1.18  # ifOutDiscards
            - 1.3.6.1.2.1.2.2.1.19  # ifOutErrors
            - 1.3.6.1.2.1.2.2.1.20  # ifOutQLen
          metrics:
            - name: sysDescr
              oid: 1.3.6.1.2.1.1.1.0
              type: DisplayString
            - name: sysName
              oid: 1.3.6.1.2.1.1.5.0
              type: DisplayString
            - name: ifDescr
              oid: 1.3.6.1.2.1.2.2.1.2
              type: DisplayString
              indexes:
                - labelname: ifIndex
                  type: gauge
            - name: ifSpeed
              oid: 1.3.6.1.2.1.2.2.1.5
              type: gauge
              indexes:
                - labelname: ifIndex
                  type: gauge
            - name: ifAdminStatus
              oid: 1.3.6.1.2.1.2.2.1.7
              type: gauge
              indexes:
                - labelname: ifIndex
                  type: gauge
            - name: ifOperStatus
              oid: 1.3.6.1.2.1.2.2.1.8
              type: gauge
              indexes:
                - labelname: ifIndex
                  type: gauge
            - name: ifInOctets
              oid: 1.3.6.1.2.1.2.2.1.10
              type: counter
              indexes:
                - labelname: ifIndex
                  type: gauge
            - name: ifOutOctets
              oid: 1.3.6.1.2.1.2.2.1.16
              type: counter
              indexes:
                - labelname: ifIndex
                  type: gauge
    '';
  };
}
