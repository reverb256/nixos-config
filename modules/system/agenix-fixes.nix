# Agenix Secrets Decryption - Fixes boot-time secret availability
# Resolves critical issue where encrypted secrets aren't decrypted during boot
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types mkIf;
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
        # Agenix automatic rekey service - Verify secrets are decrypted

        set -euo pipefail

        # Try multiple identity file locations (home may not be mounted yet)
        IDENTITY_FILE="''${1:-/home/j_kro/.age/key.txt}"
        FALLBACK_IDENTITY="/etc/age/key.txt"
        SECRETS_DIR="/etc/nixos/secrets"
        # Agenix creates random subdirectories (e.g., /run/agenix.d/5/)
        # We'll detect the actual directory instead of hardcoding "/1"
        AGENTX_BASE="/run/agenix.d"

        echo "[agenix-rekey] Verifying secret decryption..."

        # Check if identity file exists, try fallback if not
        if [ ! -f "$IDENTITY_FILE" ]; then
          echo "[agenix-rekey] Primary identity file not found: $IDENTITY_FILE"
          if [ -f "$FALLBACK_IDENTITY" ]; then
            echo "[agenix-rekey] Using fallback identity file: $FALLBACK_IDENTITY"
            IDENTITY_FILE="$FALLBACK_IDENTITY"
          else
            echo "[agenix-rekey] ERROR: No identity file found"
            echo "[agenix-rekey] Tried: $IDENTITY_FILE and $FALLBACK_IDENTITY"
            exit 1
          fi
        fi

        # Check if secrets directory exists
        if [ ! -d "$SECRETS_DIR" ]; then
          echo "[agenix-rekey] ERROR: Secrets directory not found: $SECRETS_DIR"
          exit 1
        fi

        # Determine the correct target directory for secrets
        # The agenix module creates /run/agenix -> /run/agenix.d/1/ symlink
        # Services access secrets via /run/agenix/<name>
        # We need to write to the symlink target for services to find them
        if [ -L "/run/agenix" ]; then
          # Use the symlink target (readlink gives us /run/agenix.d/1)
          AGENTX_DIR="$(readlink -f /run/agenix)"
          # Ensure the target directory exists
          if [ ! -d "$AGENTX_DIR" ]; then
            mkdir -p "$AGENTX_DIR"
          fi
        else
          # Fallback: find the actual agenix mount subdirectory
          AGENTX_DIR=''$(find "$AGENTX_BASE" -maxdepth 1 -type d ! -name "$AGENTX_BASE" -print0 2>/dev/null | head -z -n 1 | xargs -0 2>/dev/null || echo "")
          if [ -z "$AGENTX_DIR" ]; then
            # Last resort: use the numbered subdirectory that agenix creates
            AGENTX_DIR="$AGENTX_BASE/1"
            mkdir -p "$AGENTX_DIR"
          fi
        fi

        echo "[agenix-rekey] Using agenix mount: $AGENTX_DIR"

        # MIGRATION: Move secrets from wrong location to correct location
        # If secrets exist in /run/agenix.d/ but not in /run/agenix.d/1/, move them
        if [ -d "$AGENTX_BASE" ] && [ "$AGENTX_DIR" != "$AGENTX_BASE" ]; then
          for secret_file in "$AGENTX_BASE"/*; do
            if [ -f "$secret_file" ]; then
              secret_name=$(basename "$secret_file")
              if [ ! -f "$AGENTX_DIR/$secret_name" ]; then
                echo "[agenix-rekey] Migrating secret from old location: $secret_name"
                mv "$secret_file" "$AGENTX_DIR/$secret_name"
              fi
            fi
          done
        fi

        # Check if secrets are already decrypted (by agenix module)
        # If yes, we're done. If no, decrypt them.
        ALREADY_DECRYPTED=true
        for secret_file in "$SECRETS_DIR"/*.age; do
          if [ -f "$secret_file" ]; then
            secret_name=''$(basename "$secret_file" .age)

            if [ ! -f "$AGENTX_DIR/$secret_name" ]; then
              echo "[agenix-rekey] Secret not decrypted: $secret_name"
              ALREADY_DECRYPTED=false
              break
            fi
          fi
        done

        if [ "$ALREADY_DECRYPTED" = true ]; then
          echo "[agenix-rekey] ✓ All secrets already decrypted by agenix module"
          echo "[agenix-rekey] No additional decryption needed"
          exit 0
        fi

        # Decrypt any missing secrets to the mount point
        echo "[agenix-rekey] Decrypting missing secrets..."
        for secret_file in "$SECRETS_DIR"/*.age; do
          if [ -f "$secret_file" ]; then
            secret_name=''$(basename "$secret_file" .age)
            output_file="$AGENTX_DIR/$secret_name"

            # Skip if already exists
            if [ -f "$output_file" ]; then
              echo "[agenix-rekey] ✓ Already exists: $secret_name"
              continue
            fi

            echo "[agenix-rekey] Decrypting: $secret_name"

            /run/current-system/sw/bin/age --decrypt \
              -i "$IDENTITY_FILE" \
              -o "$output_file" \
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

        echo "[agenix-rekey] Secret verification complete"
      '';
    };

    # Create systemd service for secret verification
    systemd.services.agenix-rekey = {
      description = "Agenix secret verification and decryption";
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
        Path = [pkgs.coreutils]; # Ensure cmp command is available
        ExecStart = "/etc/agenix-rekey-wrapper.sh ${config.services.agenix-fixes.identityFile}";

        # Security - removed PrivateTmp to allow access to /run/agenix.d
        ProtectSystem = "strict";
        ProtectHome = true;
        # Allow read/write access to the entire /run/agenix.d hierarchy
        ReadWritePaths = "/run/agenix.d";
        # Don't create new mount namespace that isolates us from /run/agenix.d
        PrivateTmp = false;

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

    # ============================================================================
    # ACTIVATION SCRIPT: Copy identity file to system location
    # ============================================================================
    # This ensures the identity file is available early in the boot process
    # before the home directory is mounted
    system.activationScripts.copy-age-key = lib.stringAfter ["users"] ''
      # Create /etc/age directory
      mkdir -p /etc/age

      # Copy identity file from home directory if it exists
      # and the system copy doesn't exist or is different
      HOME_KEY="/home/j_kro/.age/key.txt"
      SYSTEM_KEY="/etc/age/key.txt"

      if [ -f "$HOME_KEY" ]; then
        if [ ! -f "$SYSTEM_KEY" ] || ! cmp -s "$HOME_KEY" "$SYSTEM_KEY"; then
          echo "[agenix] Copying age identity key to system location..."
          cp "$HOME_KEY" "$SYSTEM_KEY"
          chmod 600 "$SYSTEM_KEY"
          chown root:root "$SYSTEM_KEY"
          echo "[agenix] Identity key copied to $SYSTEM_KEY"
        fi
      else
        echo "[agenix] Warning: Home identity key not found at $HOME_KEY"
      fi
    '';
  };
}
