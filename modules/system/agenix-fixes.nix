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
      default = "/etc/nixos/.age/key.txt";
      description = "Path to age identity key for decryption";
    };
  };

  config = mkIf config.services.agenix-fixes.enable {
    environment.etc."agenix-rekey-wrapper.sh" = {
      mode = "0755";
      text = ''
        #!/run/current-system/sw/bin/bash

        set -euo pipefail

        IDENTITY_FILE="''${1:-/etc/nixos/.age/key.txt}"
        FALLBACK_IDENTITY="/etc/age/key.txt"
        HOME_IDENTITY="/home/j_kro/.age/key.txt"
        SECRETS_DIR="/etc/nixos/secrets"
        AGENTX_BASE="/run/agenix.d"

        echo "[agenix-rekey] Verifying secret decryption..."

        if [ ! -f "$IDENTITY_FILE" ]; then
          echo "[agenix-rekey] Primary identity file not found: $IDENTITY_FILE"
          if [ -f "$FALLBACK_IDENTITY" ]; then
            echo "[agenix-rekey] Using fallback identity file: $FALLBACK_IDENTITY"
            IDENTITY_FILE="$FALLBACK_IDENTITY"
          elif [ -f "$HOME_IDENTITY" ]; then
            echo "[agenix-rekey] Using home identity file: $HOME_IDENTITY"
            IDENTITY_FILE="$HOME_IDENTITY"
          else
            echo "[agenix-rekey] ERROR: No identity file found"
            echo "[agenix-rekey] Tried: $IDENTITY_FILE, $FALLBACK_IDENTITY, $HOME_IDENTITY"
            exit 1
          fi
        fi

        if [ ! -d "$SECRETS_DIR" ]; then
          echo "[agenix-rekey] ERROR: Secrets directory not found: $SECRETS_DIR"
          exit 1
        fi

        if [ -L "/run/agenix" ]; then
          AGENTX_DIR="$(readlink -f /run/agenix)"
          if [ ! -d "$AGENTX_DIR" ]; then
            mkdir -p "$AGENTX_DIR"
          fi
        else
          AGENTX_DIR=''$(find "$AGENTX_BASE" -maxdepth 1 -type d ! -name "$AGENTX_BASE" -print0 2>/dev/null | head -z -n 1 | xargs -0 2>/dev/null || echo "")
          if [ -z "$AGENTX_DIR" ]; then
            AGENTX_DIR="$AGENTX_BASE/1"
            mkdir -p "$AGENTX_DIR"
          fi
        fi

        echo "[agenix-rekey] Using agenix mount: $AGENTX_DIR"

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

        echo "[agenix-rekey] Decrypting missing secrets..."
        for secret_file in "$SECRETS_DIR"/*.age; do
          if [ -f "$secret_file" ]; then
            secret_name=''$(basename "$secret_file" .age)
            output_file="$AGENTX_DIR/$secret_name"

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

    systemd.services.agenix-rekey = {
      description = "Agenix secret verification and decryption";
      wantedBy = ["multi-user.target"];
      after = [
        "run-agenix.d.mount"
        "local-fs.target"
      ];
      requires = ["run-agenix.d.mount"];
      before = [
        "garage.service"
      ];
      environment.PATH = lib.mkForce (
        lib.makeBinPath (
          [pkgs.coreutils] ++ lib.optionals config.services.cluster-storage.enable [pkgs.util-linux]
        )
      );

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/etc/agenix-rekey-wrapper.sh ${config.services.agenix-fixes.identityFile}";

        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = "/run/agenix.d";
        PrivateTmp = false;

        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "agenix-rekey";
      };
    };

    environment.systemPackages = with pkgs; [age];

    system.activationScripts.copy-age-key = lib.stringAfter ["users"] ''
      mkdir -p /etc/age /etc/nixos/.age

      NIXOS_KEY="/etc/nixos/.age/key.txt"
      SYSTEM_KEY="/etc/age/key.txt"
      HOME_KEY="/home/j_kro/.age/key.txt"

      SOURCE_KEY=""
      for key in "$NIXOS_KEY" "$HOME_KEY" "$SYSTEM_KEY"; do
        if [ -f "$key" ]; then
          SOURCE_KEY="$key"
          break
        fi
      done

      if [ -z "$SOURCE_KEY" ]; then
        echo "[agenix] Warning: No age identity key found"
        echo "[agenix] Checked: $NIXOS_KEY, $HOME_KEY, $SYSTEM_KEY"
        exit 0
      fi

      echo "[agenix] Using age key from: $SOURCE_KEY"

      if [ "$SOURCE_KEY" != "$NIXOS_KEY" ]; then
        if [ ! -f "$NIXOS_KEY" ] || ! /run/current-system/sw/bin/cmp -s "$SOURCE_KEY" "$NIXOS_KEY"; then
          echo "[agenix] Syncing to /etc/nixos/.age/key.txt (Syncthing)..."
          cp "$SOURCE_KEY" "$NIXOS_KEY"
          chmod 400 "$NIXOS_KEY"
          chown root:root "$NIXOS_KEY"
        fi
      fi

      if [ "$SOURCE_KEY" != "$SYSTEM_KEY" ]; then
        if [ ! -f "$SYSTEM_KEY" ] || ! /run/current-system/sw/bin/cmp -s "$SOURCE_KEY" "$SYSTEM_KEY"; then
          echo "[agenix] Syncing to /etc/age/key.txt (system)..."
          cp "$SOURCE_KEY" "$SYSTEM_KEY"
          chmod 600 "$SYSTEM_KEY"
          chown root:root "$SYSTEM_KEY"
        fi
      fi

      echo "[agenix] Age identity key synced to all locations"
    '';
  };
}
