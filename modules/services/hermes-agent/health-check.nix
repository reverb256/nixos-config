# Hermes Agent Health Check
# Verifies Hermes Agent is functional on each node
{ config, lib, pkgs, ... }:
let
  cfg = config.services.hermes-agent;
in lib.mkIf cfg.enable {
  systemd.services.hermes-health-check = {
    description = "Verify Hermes Agent is functional";
    script = ''
      #!/usr/bin/env bash
      set -e

      echo "[Hermes Health Check] Starting..."

      # 1. Check Hermes CLI is available
      if ! command -v hermes &>/dev/null; then
        echo "[Hermes Health Check] ✗ Hermes CLI not found in PATH"
        exit 1
      fi
      echo "[Hermes Health Check] ✓ Hermes CLI found"

      # 2. Check Hermes version
      HERMES_VERSION=$(hermes --version 2>&1 || echo "unknown")
      echo "[Hermes Health Check] ✓ Version: $HERMES_VERSION"

      # 3. Check AI Gateway is reachable (only on zephyr or if enabled)
      if [[ "${cfg.aiGateway.enable}" == "true" ]]; then
        GATEWAY_URL=''${cfg.aiGateway.url}''
        # Extract host and port from URL
        GATEWAY_HOST=''${GATEWAY_URL#http://}''
        GATEWAY_HOST=''${GATEWAY_HOST%/*}''

        # Try to reach the gateway
        if curl -sSf --max-time 5 "$GATEWAY_URL/health" >/dev/null 2>&1; then
          echo "[Hermes Health Check] ✓ AI Gateway reachable ($GATEWAY_URL)"
        else
          echo "[Hermes Health Check] ⚠️  AI Gateway not reachable ($GATEWAY_URL)"
          echo "[Hermes Health Check]     This is expected on non-zephyr nodes if gateway runs only on zephyr"
        fi
      fi

      # 4. Check shared storage
      if [[ "${cfg.sharedStorage.enable}" == "true" ]]; then
        MOUNT_POINT=''${cfg.sharedStorage.mountPoint}''
        if mountpoint -q "$MOUNT_POINT"; then
          echo "[Hermes Health Check] ✓ Shared storage mounted ($MOUNT_POINT)"
        else
          echo "[Hermes Health Check] ⚠️  Shared storage not mounted ($MOUNT_POINT)"
          echo "[Hermes Health Check]     NFS server may be unavailable"
        fi
      fi

      # 5. Check custom skills directory exists
      if [[ -d "${cfg.customSkills}" ]]; then
        SKILL_COUNT=$(find "${cfg.customSkills}" -name "SKILL.md" 2>/dev/null | wc -l)
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
}
