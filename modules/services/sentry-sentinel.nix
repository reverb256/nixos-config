{ config, lib, pkgs, ... }:
{
  # ============================================================================
  # Sentry (10.1.1.140) liveness watchdog + Wake-on-LAN OOB recovery
  #
  # Sentry is a bare-metal k8s/monitoring node with NO IPMI/BMC/PDU/WoL in the
  # inventory (as of 2026-08-02 OOM audit). It runs its OWN Prometheus, so an
  # in-sentry "HostDown" alert can never fire when sentry is the dead node.
  # This module therefore runs the watchdog on a host that stays up - Nexus -
  # and alerts via journald (+ optional ntfy) plus a WoL magic packet.
  #
  # Enable on nexus only (see hosts/nexus/services.nix).
  # ============================================================================
  options.services.sentry-sentinel = {
    enable = lib.mkEnableOption "Sentry (10.1.1.140) liveness watchdog + WoL OOB recovery (run on nexus)";

    targetHost = lib.mkOption {
      type = lib.types.str;
      default = "10.1.1.140";
      description = "Sentry IP address to probe.";
    };

    targetMac = lib.mkOption {
      type = lib.types.str;
      default = "70:85:c2:d2:87:bf";
      description = "Sentry onboard NIC MAC (renamed to lan0). Required for the WoL magic packet.";
    };

    downForMinutes = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Consecutive down minutes before alerting + attempting WoL.";
    };

    wolCooldownMinutes = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Minimum minutes between WoL magic-packet attempts.";
    };

    ntfyUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Optional ntfy POST target for down alerts (e.g. http://10.1.1.140:9099/cluster-alerts). Best-effort only.";
    };

    intervalMinutes = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Watchdog tick interval.";
    };
  };

  config = lib.mkIf config.services.sentry-sentinel.enable {
    systemd.tmpfiles.rules = [ "d /var/lib/sentry-sentinel 0755 root root -" ];

    systemd.services.sentry-sentinel = {
      description = "Sentry liveness watchdog + Wake-on-LAN OOB recovery";
      wantedBy = [ "timers.target" ];
      path = with pkgs; [ wakeonlan iputils util-linux curl ];
      environment = {
        SENTRY_HOST = config.services.sentry-sentinel.targetHost;
        SENTRY_MAC = config.services.sentry-sentinel.targetMac;
        SENTRY_DOWN_FOR = toString config.services.sentry-sentinel.downForMinutes;
        SENTRY_WOL_COOLDOWN = toString config.services.sentry-sentinel.wolCooldownMinutes;
        SENTRY_NTFY = config.services.sentry-sentinel.ntfyUrl;
      };
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = lib.fileContents ./sentry-sentinel.sh;
    };

    systemd.timers.sentry-sentinel = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "${toString config.services.sentry-sentinel.intervalMinutes}m";
        Persistent = true;
      };
    };
  };
}
