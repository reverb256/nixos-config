# NixOS Network Switch Orchestration Module
# TP-Link Switch Management and Topology Discovery

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.networking.switch-orchestration;
  inherit (lib)
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
    networking.firewall.allowedUDPPorts = [ 161 ];

    environment.systemPackages = with pkgs; [
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
          timeout 2 bash -c "echo >/dev/tcp/$switch/80" 2>/dev/null" && echo "  Web UI: ACCESSIBLE" || echo "  Web UI: UNREACHABLE"
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

      python3
      python3Packages.requests
      python3Packages.snmp-tools
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
    };
  };
}
