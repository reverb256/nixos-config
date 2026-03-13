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
        state = if cfg.priority >= 110 then "MASTER" else "BACKUP";

        interface = cfg.interface;
        virtualRouterId = cfg.vrid;
        priority = cfg.priority;

        virtualIps = [
          {
            addr = "${cfg.vip}/24";
          }
        ];

        # Optional: enable health checks (disabled for initial setup, enable after cluster is stable)
        # trackScripts = ["check-kube-apiserver"];
      };

      # Health check script for kube-apiserver (disabled by default)
      # Uncomment vrrpScripts and trackScripts above to enable
      # vrrpScripts.check-kube-apiserver = {
      #   script = ''
      #     #!/bin/sh
      #     # Check if kube-apiserver is responding
      #     ${pkgs.curl}/bin/curl -f -s -o /dev/null --connect-timeout 3 http://127.0.0.1:6443/healthz
      #   '';
      #   weight = -20; # Decrease priority by 20 if script fails
      #   interval = 2; # Check every 2 seconds
      #   fall = 2; # Need 2 failures to fail
      #   rise = 2; # Need 2 successes to recover
      # };
    };

    # Firewall: allow VRRP protocol (UDP port 112 for VRRP)
    networking.firewall.allowedUDPPorts = [112];
  };
}
