{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.k8s-secret-bootstrap;
in {
  options.services.k8s-secret-bootstrap = {
    enable = lib.mkEnableOption "Auto-generate K8s secrets on first deploy";

    secrets = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          namespace = lib.mkOption {type = lib.types.str;};
          name = lib.mkOption {type = lib.types.str;};
          keys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Keys to generate (each gets a 32-char random base64 value)";
          };
        };
      });
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.k8s-secret-bootstrap = {
      description = "Bootstrap K8s secrets (create if missing)";
      after = ["k3s.service"];
      requires = ["k3s.service"];
      before = ["k8s-nix-deploy.service"];
      wantedBy = [];
      serviceConfig = {
        Type = "oneshot";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
        RemainAfterExit = true;
      };
      path = [pkgs.kubectl pkgs.openssl pkgs.coreutils];
      script = ''
        set -euo pipefail

        echo "[k8s-secret-bootstrap] Waiting for K8s API..."
        elapsed=0
        until kubectl get nodes &>/dev/null; do
          sleep 5
          elapsed=$((elapsed + 5))
          if [ $elapsed -ge 120 ]; then
            echo "[k8s-secret-bootstrap] Timed out waiting for K8s API"
            exit 1
          fi
        done

        ${lib.concatMapStrings (secret: ''
            if kubectl get secret ${secret.name} -n ${secret.namespace} &>/dev/null; then
              echo "[k8s-secret-bootstrap] Secret ${secret.name} already exists"
            else
              echo "[k8s-secret-bootstrap] Generating secret ${secret.name}..."
              # Generate all key-values inline — avoids bash variable naming issues with hyphens
              kubectl create secret generic ${secret.name} -n ${secret.namespace} \
                ${lib.concatMapStrings (key: ''
                --from-literal=${key}="$(openssl rand -base64 32 | head -c 32)" \
              '')
              secret.keys}
              echo "[k8s-secret-bootstrap] Created ${secret.name}"
            fi
          '')
          cfg.secrets}

        echo "[k8s-secret-bootstrap] Done."
      '';
    };

    # Post-deploy: sync generated client-secret into Casdoor application
    systemd.services.casdoor-app-sync = {
      description = "Sync oauth2-proxy client-secret to Casdoor application";
      after = ["k8s-nix-deploy.service" "k3s.service"];
      requires = ["k3s.service"];
      wants = ["k8s-nix-deploy.service"];
      wantedBy = [];
      before = []; # Don't block multi-user.target for other services
      serviceConfig = {
        Type = "oneshot";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
        RemainAfterExit = true;
        TimeoutStartSec = "180s";
        Restart = "on-failure";
        RestartSec = "30s";
      };
      path = [pkgs.kubectl pkgs.curl pkgs.coreutils pkgs.jq];
      script = ''
        set -euo pipefail

        # First wait for K8s API to be available (k3s might still be starting).
        echo "[casdoor-app-sync] Waiting for K8s API..."
        elapsed=0
        until kubectl get nodes &>/dev/null; do
          sleep 5
          elapsed=$((elapsed + 5))
          if [ $elapsed -ge 120 ]; then
            echo "[casdoor-app-sync] Timed out waiting for K8s API"
            exit 1
          fi
        done

        echo "[casdoor-app-sync] Waiting for Casdoor to be ready..."
        elapsed=0
        until kubectl get pods -n auth -l app=casdoor -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; do
          sleep 5
          elapsed=$((elapsed + 5))
          if [ $elapsed -ge 120 ]; then
            echo "[casdoor-app-sync] Timed out waiting for Casdoor"
            exit 1
          fi
        done

        # Get the client-secret from K8s
        CLIENT_SECRET=$(kubectl get secret oauth2-proxy-secrets -n auth -o jsonpath='{.data.client-secret}' | base64 -d)
        CASDOOR_PORT=$(kubectl get svc casdoor -n auth -o jsonpath='{.spec.ports[0].nodePort}')

        if [ -z "$CASDOOR_PORT" ]; then
          echo "[casdoor-app-sync] No Casdoor NodePort found"
          exit 0
        fi

        AUTH_URL="https://auth.lan"

        # Get a session token as admin
        TOKEN=$(curl -sk "$AUTH_URL/api/login" \
          -H 'Content-Type: application/json' \
          -d '{"username":"admin","password":"admin","type":"code"}' | jq -r '.data // empty' 2>/dev/null || true)

        # If default admin doesn't work, try j_kro (already set up)
        if [ -z "$TOKEN" ]; then
          echo "[casdoor-app-sync] Default admin not available, skipping app sync (already configured)"
          exit 0
        fi

        # Check if oauth2-proxy application exists
        APP=$(curl -sk "$AUTH_URL/api/get-application/oauth2-proxy" \
          -H "Authorization: Bearer $TOKEN" 2>/dev/null | jq -r '.data.name // empty')

        if [ -n "$APP" ]; then
          # Update client-secret to match K8s secret
          EXISTING_SECRET=$(curl -sk "$AUTH_URL/api/get-application/oauth2-proxy" \
            -H "Authorization: Bearer $TOKEN" | jq -r '.data.clientSecret')

          if [ "$EXISTING_SECRET" = "$CLIENT_SECRET" ]; then
            echo "[casdoor-app-sync] Client secret already matches"
            exit 0
          fi

          curl -sk "$AUTH_URL/api/update-application" \
            -H "Authorization: Bearer $TOKEN" \
            -H 'Content-Type: application/json' \
            -d "$(curl -sk "$AUTH_URL/api/get-application/oauth2-proxy" \
              -H "Authorization: Bearer $TOKEN" | jq --arg cs "$CLIENT_SECRET" '.data.clientSecret = $cs')" \
            >/dev/null 2>&1

          echo "[casdoor-app-sync] Updated client-secret"
        else
          # Create the oauth2-proxy application
          curl -sk "$AUTH_URL/api/add-application" \
            -H "Authorization: Bearer $TOKEN" \
            -H 'Content-Type: application/json' \
            -d '{
              "owner": "admin",
              "name": "oauth2-proxy",
              "createdTime": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
              "displayName": "OAuth2 Proxy",
              "enablePassword": true,
              "enableCodeSignin": false,
              "clientId": "5bf72a094f75c6f5729e",
              "clientSecret": "'"$CLIENT_SECRET"'",
              "redirectUris": [
                "https://auth.lan/oauth2/callback",
                "http://auth.lan/oauth2/callback",
                "https://mission-control.lan/oauth2/callback",
                "https://grafana.lan/oauth2/callback",
                "https://llama.zephyr.lan/oauth2/callback",
                "https://llama.sentry.lan/oauth2/callback"
              ],
              "tokenFormat": "JWT",
              "expireInHours": 24,
              "refreshExpireInHours": 168,
              "grantTypes": ["authorization_code","refresh_token","password"],
              "organization": "built-in",
              "isEnabled": true
            }' >/dev/null 2>&1

          echo "[casdoor-app-sync] Created oauth2-proxy application"
        fi

        # Ensure j_kro admin user exists (idempotent)
        EXISTING_USER=$(curl -sk "$AUTH_URL/api/get-user/j_kro" \
          -H "Authorization: Bearer $TOKEN" 2>/dev/null | jq -r '.data.name // empty')

        if [ -z "$EXISTING_USER" ]; then
          curl -sk "$AUTH_URL/api/add-user" \
            -H "Authorization: Bearer $TOKEN" \
            -H 'Content-Type: application/json' \
            -d '{
              "owner": "built-in",
              "name": "j_kro",
              "displayName": "j_kro",
              "type": "normal-user",
              "password": "changeme",
              "email": "j_kro@lan",
              "emailVerified": true,
              "isAdmin": true,
              "isForbidden": false,
              "signupApplication": "app-built-in"
            }' >/dev/null 2>&1
          echo "[casdoor-app-sync] Created j_kro admin user"
        else
          echo "[casdoor-app-sync] j_kro user exists"
        fi

        echo "[casdoor-app-sync] Done."
      '';
    };
  };
}
