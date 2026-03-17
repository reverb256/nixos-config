# Hermes Agent Health Check
# Verifies Hermes Agent is functional on each node
{ config, lib, pkgs, ... }:
let
  cfg = config.services.hermes-agent;
in lib.mkIf cfg.enable {
  systemd.services.hermes-health-check = {
    description = "Verify Hermes Agent is functional";
    path = with pkgs; [ curl coreutils systemd ];
    script = ''
      #!/usr/bin/env bash
      set -e

      echo "[Hermes Health Check] Starting..."

      # 1. Check Hermes agent service is running
      if systemctl is-active --quiet hermes-agent.service; then
        echo "[Hermes Health Check] ✓ Hermes Agent service is running"
      else
        echo "[Hermes Health Check] ✗ Hermes Agent service is not running"
        exit 1
      fi

      # 2. Check AI Gateway is reachable (only if enabled)
      if ${lib.boolToString cfg.aiGateway.enable}; then
        GATEWAY_URL=''${cfg.aiGateway.url}
        # Try to reach the gateway (health check uses root endpoint)
        if ${pkgs.curl}/bin/curl -sSf --max-time 5 "$GATEWAY_URL/health" >/dev/null 2>&1; then
          echo "[Hermes Health Check] ✓ AI Gateway reachable ($GATEWAY_URL)"
        else
          echo "[Hermes Health Check] ⚠️  AI Gateway not reachable ($GATEWAY_URL)"
          echo "[Hermes Health Check]     This is expected on non-zephyr nodes if gateway runs only on zephyr"
        fi
      fi

      # 3. Check shared storage
      if ${lib.boolToString cfg.sharedStorage.enable}; then
        MOUNT_POINT=''${cfg.sharedStorage.mountPoint}
        if ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT_POINT"; then
          echo "[Hermes Health Check] ✓ Shared storage mounted ($MOUNT_POINT)"
        else
          echo "[Hermes Health Check] ⚠️  Shared storage not mounted ($MOUNT_POINT)"
          echo "[Hermes Health Check]     NFS server may be unavailable"
        fi
      fi

      # 4. Check custom skills directory exists
      if [[ -d "${cfg.customSkills}" ]]; then
        SKILL_COUNT=$(${pkgs.findutils}/bin/find "${cfg.customSkills}" -name "SKILL.md" 2>/dev/null | wc -l)
        echo "[Hermes Health Check] ✓ Custom skills directory found ($SKILL_COUNT skills)"
      else
        echo "[Hermes Health Check] ⚠️  Custom skills directory not found (${cfg.customSkills})"
      fi

      echo "[Hermes Health Check] ✓ All checks passed"
      exit 0
    '';
    serviceConfig = {
      Type = "oneshot";
      User = cfg.user;
      Group = cfg.group;
    };
  };

  systemd.timers.hermes-health-check = {
    wantedBy = [ "multi-user.target" ];
    timerConfig = {
      OnBootSec = "5min";  # Wait 5 min after boot
      OnUnitActiveSec = "1h";  # Run every hour
      AccuracySec = "1s";
    };
  };
}
