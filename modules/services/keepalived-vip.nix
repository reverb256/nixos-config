{
  config,
  lib,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
  cfg = config.services.keepalived-vip;
in {
  options.services.keepalived-vip = {
    enable = lib.mkEnableOption "Keepalived VIP for Kubernetes HA";

    vip = lib.mkOption {
      type = lib.types.str;
      default = cluster.kubernetes.vip;
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

    enableHealthCheck = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable kube-apiserver health check (reduces priority when unhealthy)";
    };

    noPreempt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Prevent BACKUP from preempting MASTER even with higher priority";
    };
  };

  config = lib.mkIf cfg.enable {
    # The NixOS keepalived module defaults to a 'keepalived_script' user for
    # vrrp_script blocks. This user must exist, otherwise the script fails and
    # the VRRP health check is silently ignored.
    users.users.keepalived_script = {
      isSystemUser = true;
      group = "nogroup";
      description = "keepalived vrrp_script user";
    };

    # keepalived-boot-delay.timer only fires at boot. If the service is
    # stopped by a deploy or crash, ensure it auto-restarts.
    systemd.services.keepalived.restartIfChanged = false;

    services.keepalived = {
      enable = lib.mkDefault true;

      vrrpInstances.kubernetes-api = {
        state =
          if cfg.priority >= 110
          then "MASTER"
          else "BACKUP";

        inherit (cfg) interface;
        virtualRouterId = cfg.vrid;
        inherit (cfg) priority;
        inherit (cfg) noPreempt;

        virtualIps = [
          {
            addr = "${cfg.vip}/24";
          }
        ];

        trackScripts = lib.optional cfg.enableHealthCheck "check-kube-apiserver";
      };

      vrrpScripts = lib.optionalAttrs cfg.enableHealthCheck {
        check-kube-apiserver = {
          # k3s /healthz requires Bearer auth (HTTP 401 without a token), so the
          # keepalived_script user can never get a 200 — the health check would
          # always "fail" and drop priority by `weight` (here -20), making this
          # node's effective priority equal to lower-priority nodes and risking
          # unnecessary VIP flapping. Curl without -f exits 0 on any HTTP response
          # (200-499) and only fails on connection errors / refused / timeout.
          # Fallback: check the k3s systemd unit state.
          script = "exec ${pkgs.curl}/bin/curl -s -o /dev/null --connect-timeout 3 --max-time 5 --insecure https://127.0.0.1:6443/healthz || systemctl is-active --quiet k3s";
          weight = -20;
          interval = 2;
          fall = 2;
          rise = 2;
        };
      };
    };

    # VRRP uses IP protocol 112 (not UDP port 112). The NixOS firewall
    # allowedUDPPorts option only handles UDP, so we need an explicit
    # nft rule for the VRRP ip protocol.
    networking.firewall.extraInputRules = ''
      ip protocol vrrp accept
    '';
  };
}
