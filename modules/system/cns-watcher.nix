{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.services.cns-watcher;
  inherit (lib) mkEnableOption mkOption types mkIf getExe concatStringsSep;
in {
  options.services.cns-watcher = {
    enable = mkEnableOption "CNS automatic secret distribution (Zephyr only)";
    watchPath = mkOption {
      type = types.path;
      default = "/etc/nixos/secrets";
      description = "Path to watch for .age secret files";
    };
    remoteNodes = mkOption {
      type = types.listOf types.str;
      default = ["nexus" "forge" "sentry"];
      description = "Remote hostnames to sync secrets to";
    };
    # SSH key path (now owned by cluster-mesh via cluster-mesh module)
    sshKeyFile = mkOption {
      type = types.path;
      default = "/var/lib/cluster-mesh/.ssh/id_ed25519";
      description = "SSH private key for mTLS authentication to remote nodes (cluster-mesh)";
    };
    healthCheckInterval = mkOption {
      type = types.int;
      default = 3600;
      description = "Health check interval in seconds (default: 1 hour)";
    };
  };

  config = mkIf cfg.enable {
    # CNS SSH key — provided by sops-secrets-registry as /run/secrets/cns-ssh-key
    systemd.services.cns-watcher = {
      description = "CNS: Watch and distribute secrets to cluster nodes";
      wantedBy = ["multi-user.target"];
      after = ["cns-setup.service"];
      serviceConfig = {
        ExecStart = pkgs.writeShellScript "cns-watcher" ''
          set -euo pipefail

          WATCH_DIR="${cfg.watchPath}"
          REMOTE_NODES=(${lib.concatStringsSep " " cfg.remoteNodes})
          SSH_KEY="${cfg.sshKeyFile}"
          STAGING_DIR="/var/lib/cns/staging"
          STATE_DIR="/var/lib/cns/state"
          LOG_FILE="/var/log/cns/watcher.log"

          # Create directories
          mkdir -p "$STAGING_DIR" "$STATE_DIR" "$(dirname "$LOG_FILE")"
          touch "$LOG_FILE"

          log() {
            echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
          }

          # Build package with all secrets
          build_secret_package() {
            local output="$STAGING_DIR/secrets-$(date +%s).tar.gz"
            local checksum_file="$STATE_DIR/last_checksum.txt"

            log "Building secret package..."
            cd "$WATCH_DIR"

            # Create package
            ${pkgs.gnutar}/bin/tar czf "$output" *.age

            # Generate checksum
            local new_checksum=$(sha256sum "$output" | cut -f1)
            echo "$new_checksum" > "$checksum_file"

            log "Package built: $output (checksum: $new_checksum)"
            echo "$output"
          }

          # Sync to remote node
          sync_to_node() {
            local node="$1"
            local package="$2"
            local checksum="$3"

            log "Syncing to $node..."

            # Copy package
            ${pkgs.openssh}/bin/scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
              "$package" "cluster-mesh@$node:/tmp/cns-package.tar.gz" 2>/dev/null || {
              log "Failed to copy package to $node"
              return 1
            }

            # Trigger receiver and wait for ACK
            ${pkgs.openssh}/bin/ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no \
              "cluster-mesh@$node" "echo '$checksum' > /tmp/cns-checksum.txt && \
                systemctl start cns-receive@$node.socket" 2>/dev/null || {
              log "Failed to trigger receiver on $node"
              return 1
            }

            # Wait for ACK (max 30s)
            local timeout=30
            local elapsed=0
            while [ $elapsed -lt $timeout ]; do
              if ${pkgs.openssh}/bin/ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no \
                 "cluster-mesh@$node" "cat /tmp/cns-ack.txt 2>/dev/null | grep -q '$checksum'"; then
                log "Successfully synced to $node"
                return 0
              fi
              sleep 2
              elapsed=$((elapsed + 2))
            done

            log "Timeout waiting for ACK from $node"
            return 1
          }

          # Main sync loop
          sync_all_nodes() {
            local package
            local checksum

            log "=== Starting sync cycle ==="

            # Build package
            package=$(build_secret_package) || {
              log "Failed to build package"
              return 1
            }

            checksum=$(cat "$STATE_DIR/last_checksum.txt")

            # Sync to all nodes
            local failures=0
            for node in "''${REMOTE_NODES[@]}"; do
              if ! sync_to_node "$node" "$package" "$checksum"; then
                log "Failed to sync to $node"
                failures=$((failures + 1))
              fi
            done

            if [ $failures -eq 0 ]; then
              log "=== Sync cycle complete: All nodes OK ==="
              # Cleanup old packages
              find "$STAGING_DIR" -name "secrets-*.tar.gz" -mtime +1 -delete
            else
              log "=== Sync cycle complete: $failures failures ==="
            fi
          }

          # Initial sync on startup
          log "CNS watcher starting..."
          sync_all_nodes

          # Watch for changes
          log "Watching for changes in $WATCH_DIR..."
          ${pkgs.inotify-tools}/bin/inotifywait -m -e create,delete,modify "$WATCH_DIR" --format '%w%f %e' 2>/dev/null | while read -r file event; do
            # Only react to .age files
            [[ "$file" == *.age ]] || continue

            log "Change detected: $file ($event)"
            sleep 2  # Debounce
            sync_all_nodes
          done
        '';
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 10;
        User = "root";
        Group = "root";
      };
    };

    # Health check timer
    systemd.timers.cns-health = {
      description = "CNS: Verify secret distribution health";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*:0/1";
        Persistent = true;
      };
    };

    systemd.services.cns-health = {
      description = "CNS: Check secret distribution health";
      serviceConfig = {
        ExecStart = pkgs.writeShellScript "cns-health" ''
          set -euo pipefail

          LOG_FILE="/var/log/cns/health.log"
          STATE_DIR="/var/lib/cns/state"
          EXPECTED_CHECKSUM="$STATE_DIR/last_checksum.txt"

          mkdir -p "$(dirname "$LOG_FILE")"

          log() {
            echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
          }

          # Read expected checksum
          [ -f "$EXPECTED_CHECKSUM" ] || {
            log "No checksum file found"
            exit 1
          }

          expected=$(cat "$EXPECTED_CHECKSUM")
          failures=0

          # Check each node
          for node in "''${REMOTE_NODES[@]}"; do
            node_checksum=$(${pkgs.openssh}/bin/ssh -i "${cfg.sshKeyFile}" -o StrictHostKeyChecking=no \
              "cluster-mesh@$node" "cat /run/cns/current-checksum.txt 2>/dev/null || echo")

            if [ "$node_checksum" = "$expected" ]; then
              log "$node: OK"
            else
              log "$node: MISMATCH (expected: $expected, got: $node_checksum)"
              failures=$((failures + 1))
            fi
          done

          if [ $failures -gt 0 ]; then
            log "Health check failed: $failures nodes out of sync"
            exit 1
          fi

          log "All nodes in sync"
        '';
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
    };

    # Create directories
    systemd.tmpfiles.rules = [
      "d /var/lib/cns 0750 root root -"
      "d /var/lib/cns/staging 0750 root root -"
      "d /var/lib/cns/state 0750 root root -"
      "d /var/log/cns 0750 root root -"
    ];

    # Install dependencies
    environment.systemPackages = with pkgs; [
      inotify-tools
      openssh
    ];
  };
}
