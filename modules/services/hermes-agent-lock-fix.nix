{ config, lib, pkgs, ... }:
{
  systemd.services.hermes-agent.serviceConfig.ExecStartPre = [
    "${pkgs.writeShellScript "hermes-lock-cleanup" ''
      LOCKFILE="/var/lib/hermes/.hermes/gateway.lock"
      if [ -f "$LOCKFILE" ]; then
        PID=$(${pkgs.jq}/bin/jq -r .pid "$LOCKFILE" 2>/dev/null || echo 0)
        if [ "$PID" != "0" ] && ! kill -0 "$PID" 2>/dev/null; then
          echo "Removing stale lock file for PID $PID"
          rm -f "$LOCKFILE"
        fi
      fi
    ''}"
  ];
}
