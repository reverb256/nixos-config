# Keepalived VIP Module for Kubernetes HA
# Provides Virtual IP (VIP) failover using VRRP protocol
# VIP floats to highest-priority healthy node
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.keepalived-vip;
in {
  options.services.keepalived-vip = {
    enable = lib.mkEnableOption "Keepalived VIP for Kubernetes HA";

    vip = lib.mkOption {
      type = lib.types.str;
      default = "10.1.1.100";
      description = "Virtual IP address for Kubernetes API";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      example = "enp38s0";
      description = "Network interface for VRRP advertisements";
    };

    priority = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "VRRP priority (higher = preferred master)";
    };

    vrid = lib.mkOption {
      type = lib.types.int;
      default = 51;
      description = "VRRP Virtual Router ID (must match across cluster)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.keepalived = {
      enable = true;

      vrrpInstances.kubernetes-api = {
        # MASTER state if priority >= 110, otherwise BACKUP
        state = lib.mkIf (cfg.priority >= 110) "MASTER" else "BACKUP";

        interface = cfg.interface;
        virtualRouterId = cfg.vrid;
        priority = cfg.priority;

        virtualIps = [
          {
            addr = "${cfg.vip}/24";
          }
        ];

        # VRRP packet settings
        advertInt = 1; # Send advertisements every second
        authPass = "k8s-ha-vrrp"; # Simple authentication (consider upgrading to HMAC)

        # Health check: only be master if API server is healthy
        trackScripts = [
          {
            name = "check-kube-apiserver";
            # Weight 20 means decrease priority by 20 if script fails
            weight = -20;
          }
        ];
      };
    };

    # Health check script for kube-apiserver
    systemd.services.keepalived.healthcheck = {
      script = ''
        #!/bin/sh
        # Check if kube-apiserver is responding
        curl -f -s -o /dev/null --connect-timeout 3 http://127.0.0.1:6443/healthz
      '';
      wantedBy = ["keepalived.service"];
    };

    # Firewall: allow VRRP protocol (IP protocol 112)
    networking.firewall.allowedUDPPorts = [112];

    # Log VRRP state changes
    systemd.services.keepalived.serviceConfig.StandardOutput = [
      "journal"
      "/var/log/keepalived.log"
    ];
  };
}
