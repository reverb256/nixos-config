# Agenix Secrets Decryption - Fixes boot-time secret availability
# Resolves critical issue where encrypted secrets aren't decrypted during boot
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types mkIf mkDefault;
in {
  options.services.agenix-fixes = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic agenix secret decryption at boot";
    };

    identityFile = mkOption {
      type = types.path;
      default = "/home/j_kro/.age/key.txt";
      description = "Path to age identity key for decryption";
    };
  };

  config = mkIf config.services.agenix-fixes.enable {
    # ============================================================================
    # CRITICAL FIX: Automatic Secret Decryption Service
    # ============================================================================
    # The agenix module creates mount points but doesn't decrypt secrets
    # This service decrypts all configured age.secrets at boot time
    #
    # Root Cause: agenix.nixosModules.default sets up infrastructure but
    # requires manual 'agenix-rekey' or initrd integration to actually decrypt
    #
    # Solution: Create a systemd service that runs 'agenix-rekey' at boot
    # ============================================================================

    # Create agenix-rekey wrapper script
    environment.etc."agenix-rekey-wrapper.sh" = {
      mode = "0755";
      text = ''
        #!/run/current-system/sw/bin/bash
        # Agenix automatic rekey service - Decrypts secrets at boot

        set -euo pipefail

        IDENTITY_FILE="${1:-/home/j_kro/.age/key.txt}"
        SECRETS_DIR="/etc/nixos/secrets"
        MOUNT_POINT="/run/agenix.d/1"

        echo "[agenix-rekey] Starting secret decryption..."

        # Check if identity file exists
        if [ ! -f "$IDENTITY_FILE" ]; then
          echo "[agenix-rekey] ERROR: Identity file not found: $IDENTITY_FILE"
          exit 1
        fi

        # Check if secrets directory exists
        if [ ! -d "$SECRETS_DIR" ]; then
          echo "[agenix-rekey] ERROR: Secrets directory not found: $SECRETS_DIR"
          exit 1
        fi

        # Decrypt each secret to the mount point
        for secret_file in "$SECRETS_DIR"/*.age; do
          if [ -f "$secret_file" ]; then
            secret_name=$(basename "$secret_file" .age)
            output_file="$MOUNT_POINT/$secret_name"

            echo "[agenix-rekey] Decrypting: $secret_name"

            /run/current-system/sw/bin/age --decrypt \
              --identity-file "$IDENTITY_FILE" \
              --output "$output_file" \
              "$secret_file" || {
              echo "[agenix-rekey] ERROR: Failed to decrypt $secret_name"
              continue
            }

            # Set correct permissions based on secret name
            case "$secret_name" in
              *-db-password)
                chmod 0440 "$output_file"
                chown root:root "$output_file"
                ;;
              *-api-key)
                chmod 0440 "$output_file"
                chown root:ai-inference "$output_file" 2>/dev/null || true
                ;;
              *-token)
                chmod 0440 "$output_file"
                chown j_kro:users "$output_file" 2>/dev/null || true
                ;;
              *)
                chmod 0600 "$output_file"
                ;;
            esac

            echo "[agenix-rekey] ✓ Decrypted: $secret_name"
          fi
        done

        echo "[agenix-rekey] Secret decryption complete"
      '';
    };

    # Create systemd service for automatic decryption
    systemd.services.agenix-rekey = {
      description = "Agenix automatic secret decryption";
      wantedBy = ["multi-user.target"];
      after = ["run-agenix.d.mount" "local-fs.target"];
      requires = ["run-agenix.d.mount"];
      before = [
        "glitchtip-postgres.service"
        "glitchtip-web.service"
        "glitchtip-redis.service"
        "ai-inference-gateway.service"
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/etc/agenix-rekey-wrapper.sh ${config.services.agenix-fixes.identityFile}";

        # Security
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = "/run/agenix.d/1";

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "agenix-rekey";
      };
    };

    # ============================================================================
    # FIX: Add age CLI to system packages
    # ============================================================================
    environment.systemPackages = with pkgs; [age];
  };
}
