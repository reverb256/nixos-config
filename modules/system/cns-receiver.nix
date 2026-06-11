{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.cns-receiver;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.cns-receiver = {
    enable = mkEnableOption "CNS secret receiver (remote nodes only)";
    allowedSenders = mkOption {
      type = types.listOf types.str;
      default = ["zephyr"];
      description = "Hostnames allowed to send secrets";
    };
    ageIdentity = mkOption {
      type = types.path;
      default = "/etc/ssh/ssh_host_ed25519_key";
      description = "Age identity for decrypting secrets";
    };
    sshPublicKey = mkOption {
      type = types.str;
      description = "SSH public key to install for CNS sender authentication";
    };
  };

  config = mkIf cfg.enable {
    # Install SSH public key for CNS sender
    users.users.root.openssh.authorizedKeys.keys = [cfg.sshPublicKey];

    # Create systemd socket-activated receiver
    systemd.sockets."cns-receive@" = {
      description = "CNS receiver socket for incoming secret packages";
      wantedBy = ["sockets.target"];
      socketConfig = {
        ListenStream = ["/run/cns/receive.sock"];
        Accept = true;
        Service = "cns-receive@%i.service";
      };
    };

    systemd.services."cns-receive@" = {
      description = "CNS: Process incoming secret package from %i";
      serviceConfig = {
        ExecStart = pkgs.writeShellScript "cns-receive" ''
          set -euo pipefail

          SENDER="$1"
          PACKAGE="/tmp/cns-package.tar.gz"
          EXPECTED_CHECKSUM="/tmp/cns-checksum.txt"
          ACK_FILE="/tmp/cns-ack.txt"
          AGENIX="${pkgs.agenix}/bin/agenix"
          LOG_FILE="/var/log/cns/receiver.log"

          mkdir -p "$(dirname "$LOG_FILE")"

          log() {
            echo "[$(date -Iseconds)] [$SENDER] $*" | tee -a "$LOG_FILE"
          }

          # Verify sender
          local allowed=false
          for allowed_sender in ${lib.concatStringsSep " " cfg.allowedSenders}; do
            if [ "$SENDER" = "$allowed_sender" ]; then
              allowed=true
              break
            fi
          done

          if [ "$allowed" != "true" ]; then
            log "Unauthorized sender: $SENDER"
            exit 1
          fi

          # Verify package exists
          [ -f "$PACKAGE" ] || {
            log "Package not found: $PACKAGE"
            exit 1
          }

          # Verify checksum
          local expected=$(cat "$EXPECTED_CHECKSUM" 2>/dev/null || echo "")
          local actual=$(sha256sum "$PACKAGE" | cut -d' ' -f1)

          if [ "$expected" != "$actual" ]; then
            log "Checksum mismatch (expected: $expected, got: $actual)"
            exit 1
          fi

          log "Processing secret package..."

          # Extract to staging
          local staging="/tmp/cns-staging-$$"
          mkdir -p "$staging"
          tar xzf "$PACKAGE" -C "$staging" || {
            log "Failed to extract package"
            rm -rf "$staging"
            exit 1
          }

          # Decrypt each secret
          local decrypt_ok=true
          for secret in "$staging"/*.age; do
            [ -f "$secret" ] || continue

            local secret_name=$(basename "$secret" .age)
            local output="/run/agenix/$secret_name"

            log "Decrypting: $secret_name"

            $AGENIX --decrypt --identity "${cfg.ageIdentity}" \
              "$secret" > "$output" 2>/dev/null || {
              log "Failed to decrypt: $secret_name"
              decrypt_ok=false
              continue
            }

            # Set permissions based on registry
            case "$secret_name" in
              k3s-cluster-token|kagent-postgres)
                chmod 440 "$output"
                ;;
              *)
                chmod 600 "$output"
                ;;
            esac

            log "Decrypted: $secret_name → $output"
          done

          # Cleanup staging
          rm -rf "$staging"
          rm -f "$PACKAGE" "$EXPECTED_CHECKSUM"

          # Write checksum file for health checks
          echo "$actual" > /run/cns/current-checksum.txt

          # Send ACK
          echo "$actual" > "$ACK_FILE"

          if [ "$decrypt_ok" = "true" ]; then
            log "Secret package processed successfully"
          else
            log "Secret package processed with errors"
          fi
        '';
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
    };

    # Ensure /run/agenix exists (tmpfs)
    systemd.tmpfiles.rules = [
      "d /run/agenix 0750 root root -"
      "d /run/cns 0750 root root -"
      "d /var/log/cns 0750 root root -"
    ];

    # Install dependencies
    environment.systemPackages = with pkgs; [
      agenix
    ];
  };
}
