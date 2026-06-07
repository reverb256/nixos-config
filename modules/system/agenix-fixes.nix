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
      default = "/etc/age/key.txt";
      description = "Path to age identity key for decryption";
    };
  };

  config = mkIf config.services.agenix-fixes.enable {
    # Fix: initrd creates /run/agenix/ as a real directory for initrd-ssh-host-key.
    # This blocks agenix from symlinking /run/agenix -> /run/agenix.d/<gen>.
    # Move the initrd key aside, remove the directory, so agenix can create the symlink.
    system.activationScripts.agenix-dir-fix = lib.mkBefore ''
      if [ -d /run/agenix ] && [ ! -L /run/agenix ]; then
        mkdir -p /run/agenix.d/0
        mv /run/agenix/* /run/agenix.d/0/ 2>/dev/null || true
        rmdir /run/agenix 2>/dev/null || true
      fi
    '';

    environment.etc."agenix-rekey-wrapper.sh" = {
      mode = "0755";
      text = ''
        #!/run/current-system/sw/bin/bash

        set -euo pipefail

        IDENTITY_FILE="''${1:-/etc/age/key.txt}"
        FALLBACK_IDENTITY="/etc/age/key.txt"
        HOME_IDENTITY="/home/j_kro/.age/key.txt"
        SECRETS_DIR="''${NIXOS_SHARED_PATH:-/etc/nixos}/secrets"
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
          echo "[agenix-rekey] WARNING: Secrets directory not found: $SECRETS_DIR"
          exit 0
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

      environment.NIXOS_SHARED_PATH = lib.mkIf config.services.nixos-share.client.enable config.services.nixos-share.client.mountPoint;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/etc/agenix-rekey-wrapper.sh ${config.services.agenix-fixes.identityFile}";

        ProtectSystem = "strict";
        ReadWritePaths = "/run/agenix.d /etc/age";
        ProtectHome = "read-only";
        PrivateTmp = false;

        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "agenix-rekey";
      };
    };

    # Apply agenix-decrypted secrets as K8s secrets
    # Runs ONLY on K3s server nodes (control plane) — agents have no local API server
    systemd.services.kubectl-apply-k8s-secrets = lib.mkIf (config.services.k3s-cluster.enable && config.services.k3s-cluster.role == "server") {
      description = "Apply agenix secrets as Kubernetes secrets";
      after = ["agenix.service" "k3s.service" "k8s-nix-deploy.service" "network-online.target"];
      wants = ["agenix.service" "k8s-nix-deploy.service" "network-online.target"];
      requires = ["k3s.service"];
      wantedBy = ["multi-user.target"];
      # Don't block graphical.target -- K8s secrets don't gate desktop login
      before = lib.mkForce [];

      path = with pkgs; [kubectl coreutils gnugrep];
      environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "kubectl-apply-k8s-secrets" ''
          set -euo pipefail

          # Wait for K8s API to be ready
          for i in $(seq 1 60); do
            if kubectl get nodes >/dev/null 2>&1; then
              break
            fi
            echo "[k8s-secrets] Waiting for K8s API... ($i/60)"
            sleep 2
          done

          if ! kubectl get nodes >/dev/null 2>&1; then
            echo "[k8s-secrets] ERROR: K8s API not available after 120s"
            exit 1
          fi

          apply_secret() {
            local namespace="$1"
            local secret_name="$2"
            local key="$3"
            local file="$4"

            if [ ! -f "$file" ] || [ ! -s "$file" ]; then
              echo "[k8s-secrets] SKIP: $namespace/$secret_name ($key) — file not ready: $file"
              return 0
            fi

            local value
            value=$(cat "$file")

            # Create or update the secret
            if kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
              kubectl patch secret "$secret_name" -n "$namespace" -p "{\"stringData\":{\"$key\":\"$value\"}}" 2>/dev/null && \
                echo "[k8s-secrets] ✓ Updated $namespace/$secret_name ($key)" || \
                echo "[k8s-secrets] ✗ Failed to update $namespace/$secret_name ($key)"
            else
              kubectl create secret generic "$secret_name" -n "$namespace" --from-literal="$key=$value" --dry-run=client -o yaml | kubectl apply -f - && \
                echo "[k8s-secrets] ✓ Created $namespace/$secret_name ($key)" || \
                echo "[k8s-secrets] ✗ Failed to create $namespace/$secret_name ($key)"
            fi
          }

          echo "[k8s-secrets] Applying agenix secrets to Kubernetes..."

          # AI Inference namespace
          apply_secret ai-inference zai-api-key ZAI_API_KEY /run/agenix/ai-gateway-zai-api-key
          apply_secret ai-inference hf-token token /run/agenix/huggingface-token
          apply_secret ai-inference nvidia-api-key NVIDIA_API_KEY /run/agenix/nvidia-api-key
          # openrouter-api-key removed — no longer used
          apply_secret ai-inference kilo-api-key KILO_API_KEY /run/agenix/kilo-api-key
          apply_secret ai-inference opencode-api-key OPENCODE_API_KEY /run/agenix/opencode-api-key

          # Kelos namespace
          apply_secret kelos-system opencode-credentials OPENCODE_API_KEY /run/agenix/opencode-api-key
          apply_secret kelos-system opencode-credentials NVIDIA_API_KEY /run/agenix/nvidia-api-key

          # Search namespace
          apply_secret search searxng-secret secret-key /run/agenix/searxng-secret-key

          # Orchestration namespace
          apply_secret orchestration mission-control-secrets auth-pass /run/agenix/mission-control-auth-pass
          apply_secret orchestration mission-control-secrets api-key /run/agenix/mission-control-api-key

          # Mining namespace
          apply_secret mining xmrig-proxy-secret api-token /run/agenix/xmrig-proxy-api-token

          # Monitoring namespace
          apply_secret monitoring grafana-admin-secret admin-password /run/agenix/grafana-admin-password
          apply_secret monitoring grafana-oidc-secret client-secret /run/agenix/grafana-oidc-client-secret
          apply_secret ai-inference openwebui-oidc-secret client-secret /run/agenix/openwebui-oidc-client-secret

          # Automation namespace (n8n)
          apply_secret automation n8n-secrets admin-password /run/agenix/n8n-admin-password
          apply_secret automation n8n-secrets encryption-key /run/agenix/n8n-encryption-key
          apply_secret automation hermes-automation-keys n8n-api-key /run/agenix/n8n-api-key

          echo "[k8s-secrets] Done"
        '';
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "kubectl-apply-k8s-secrets";
      };
    };

    environment.systemPackages = with pkgs; [age];

    system.activationScripts.copy-age-key = lib.stringAfter ["users"] ''
      mkdir -p /etc/age
      mkdir -p /etc/nixos/.age 2>/dev/null || true

      PERSISTENT_KEY="/persistent/etc/age/key.txt"
      NIXOS_KEY="/etc/nixos/.age/key.txt"
      SYSTEM_KEY="/etc/age/key.txt"
      HOME_KEY="/home/j_kro/.age/key.txt"

      SOURCE_KEY=""
      for key in "$PERSISTENT_KEY" "$NIXOS_KEY" "$HOME_KEY" "$SYSTEM_KEY"; do
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
          cp "$SOURCE_KEY" "$NIXOS_KEY" 2>/dev/null || {
            echo "[agenix] Warning: Cannot write to $NIXOS_KEY (read-only NFS mount?)"
          }
          chmod 400 "$NIXOS_KEY" 2>/dev/null || true
          chown root:root "$NIXOS_KEY" 2>/dev/null || true
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
