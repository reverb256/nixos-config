{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.podman-auto-update;
in {
  options.services.podman-auto-update = {
    enable = lib.mkEnableOption "Podman container auto-update service";
  };

  config = lib.mkIf cfg.enable {
    systemd.services.podman-auto-update = {
      description = "Podman Container Auto-Update";
      after = ["network-online.target" "podman.service"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "oneshot";

        ExecStartPre = pkgs.writeShellScript "podman-validate-image-age" ''
          set -euo pipefail
          AGE_THRESHOLD_DAYS=7
          NOW=$(${pkgs.coreutils}/bin/date +%s)

          echo "[supply-chain] Checking container image ages (threshold: $AGE_THRESHOLD_DAYS days)..."

          containers=$(${pkgs.podman}/bin/podman ps --format {{.Names}} --filter status=running 2>/dev/null || true)
          if [ -z "$containers" ]; then
            echo "[supply-chain] No running containers to validate"
            exit 0
          fi

          for container in $containers; do
            current_image=$(${pkgs.podman}/bin/podman inspect "$container" --format {{.Image}} 2>/dev/null || true)
            created=$(${pkgs.podman}/bin/podman inspect "$current_image" --format '{{.Created}}' 2>/dev/null || true)
            if [ -n "$created" ]; then
              created_epoch=$(${pkgs.coreutils}/bin/date -d "$created" +%s 2>/dev/null || echo 0)
              if [ "$created_epoch" -gt 0 ]; then
                age_days=$(( (NOW - created_epoch) / 86400 ))
                if [ "$age_days" -lt "$AGE_THRESHOLD_DAYS" ]; then
                  echo "[supply-chain] WARNING: Image for $container is only $age_days days old"
                else
                  echo "[supply-chain] OK: Image for $container is $age_days days old"
                fi
              fi
            fi
          done
        '';

        ExecStart = pkgs.writeShellScript "podman-auto-update" ''
          set -euo pipefail

          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "  Podman Auto-Update"
          echo "  $(date)"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

          containers=$(${pkgs.podman}/bin/podman ps --format {{.Names}} --filter status=running)

          if [ -z "$containers" ]; then
            echo "No running containers found"
            exit 0
          fi

          echo "Found $(echo "$containers" | wc -l) running container(s)"

          for container in $containers; do
            echo ""
            echo "────────────────────────────────────────────────────────────────────"
            echo "Updating container: $container"
            echo "────────────────────────────────────────────────────────────────────"

            current_image=$(${pkgs.podman}/bin/podman inspect $container --format {{.Image}})

            echo "Current image: $current_image"

            echo "Pulling latest image..."
            if ${pkgs.podman}/bin/podman pull $current_image 2>&1 | tee /tmp/podman-pull-$container.log; then
              echo "✓ Image pulled successfully"

              if grep -q "Image is up to date" /tmp/podman-pull-$container.log; then
                echo "Container already up to date"
                continue
              fi

              echo "Recreating container with new image..."

              ${pkgs.podman}/bin/podman inspect $container --format '{{join .Config.Cmd " "}}' > /tmp/$container-cmd.txt

              echo "Stopping container..."
              ${pkgs.podman}/bin/podman stop $container

              echo "Removing container..."
              ${pkgs.podman}/bin/podman rm $container

              echo "✓ Container stopped and removed (systemd will recreate it)"
              echo "Note: systemd-managed containers will be auto-restarted"

            else
              echo "✗ Failed to pull image"
            fi
          done

          echo ""
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "  Update Complete"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        '';

        User = "root";
      };
    };

    systemd.timers.podman-auto-update = {
      description = "Podman Container Auto-Update Timer";
      wantedBy = ["timers.target"];
      partOf = ["podman-auto-update.service"];

      timerConfig = {
        OnCalendar = "hourly";
        AccuracySec = "5min";
        Persistent = "true";
      };
    };
  };
}
