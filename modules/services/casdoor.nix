# ─────────────────────────────────────────────────────────────────
# Casdoor App Registration — declarative app sync via Casdoor API
#
# Registers MapleSpike applications as Casdoor OIDC clients so
# they can authenticate users via Casdoor SSO.
#
# Apps registered:
#   app-maplespike-api   → api.maplespike.ca     (REST API gateway)
#   app-maplespike-portal → quill.maplespike.ca   (Portal frontend)
#   app-maplespike-mcp   → JWKS token validation   (MCP SSE server)
#
# Follows the same pattern as app-gitea, app-openwebui, and the
# oauth2-proxy app in k8s-secret-bootstrap.nix.
# ─────────────────────────────────────────────────────────────────

{ config, lib, pkgs, ... }:
let
  cfg = config.services.casdoor-app-registration;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.casdoor-app-registration = {
    enable = mkEnableOption "Register MapleSpike Casdoor applications";

    casdoorUrl = mkOption {
      type = types.str;
      default = "https://auth.lan";
      description = "Casdoor base URL";
    };

    adminUser = mkOption {
      type = types.str;
      default = "admin";
      description = "Casdoor admin username for API auth";
    };

    adminPassword = mkOption {
      type = types.str;
      default = "admin";
      description = "Casdoor admin password for API auth";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.casdoor-app-registration = {
      description = "Register MapleSpike apps in Casdoor";
      after = [ "k3s.service" "k8s-nix-deploy.service" ];
      wants = [ "k3s.service" "k8s-nix-deploy.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "300s";
        Restart = "on-failure";
        RestartSec = "30s";
      };

      path = with pkgs; [ curl jq coreutils ];

      script = ''
        set -euo pipefail

        AUTH_URL="${cfg.casdoorUrl}"
        ADMIN_USER="${cfg.adminUser}"
        ADMIN_PASS="${cfg.adminPassword}"

        echo "[casdoor-app-registration] Waiting for Casdoor to be ready..."
        elapsed=0
        until curl -skf "$AUTH_URL/api/get-user/admin" >/dev/null 2>&1; do
          sleep 5
          elapsed=$((elapsed + 5))
          if [ $elapsed -ge 120 ]; then
            echo "[casdoor-app-registration] Timed out waiting for Casdoor"
            exit 1
          fi
        done

        # Get admin session token
        TOKEN=$(curl -sk "$AUTH_URL/api/login" \
          -H 'Content-Type: application/json' \
          -d '{"username":"'"$ADMIN_USER"'","password":"'"$ADMIN_PASS"'","type":"code"}' | jq -r '.data // empty' 2>/dev/null || true)

        if [ -z "$TOKEN" ]; then
          echo "[casdoor-app-registration] Could not get admin token — skipping app sync (already configured?)"
          exit 0
        fi

        # ── Helper: upsert a Casdoor application ──────────────────
        # Creates the app if it doesn't exist, updates it if it does.
        upsert_app() {
          local name="$1"
          local displayName="$2"
          local redirectUri="$3"
          shift 3
          local extraFields="$*"

          local existing
          existing=$(curl -sk "$AUTH_URL/api/get-application?owner=admin&name=$name" \
            -H "Authorization: Bearer $TOKEN" 2>/dev/null | jq -r '.data.name // empty')

          if [ -n "$existing" ]; then
            echo "[casdoor-app-registration] App '$name' exists — updating..."
            local appData
            appData=$(curl -sk "$AUTH_URL/api/get-application?owner=admin&name=$name" \
              -H "Authorization: Bearer $TOKEN" 2>/dev/null)
            # Update redirect URIs and enable password
            echo "$appData" | jq \
              --arg uri "$redirectUri" \
              '.data.redirectUris = [$uri] | .data.enablePassword = true | .data.isEnabled = true' \
              > /tmp/casdoor-app-"$name".json
            curl -sk "$AUTH_URL/api/update-application" \
              -H "Authorization: Bearer $TOKEN" \
              -H 'Content-Type: application/json' \
              -d @/tmp/casdoor-app-"$name".json >/dev/null 2>&1
            echo "[casdoor-app-registration] Updated app '$name'"
          else
            echo "[casdoor-app-registration] Creating app '$name'..."
            local body
            body=$(jq -n \
              --arg name "$name" \
              --arg displayName "$displayName" \
              --arg redirectUri "$redirectUri" \
              --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
              '{
                owner: "admin",
                name: $name,
                createdTime: $now,
                displayName: $displayName,
                enablePassword: true,
                enableCodeSignin: false,
                clientId: ("maplespike-" + $name),
                clientSecret: ("auto-" + $name + "-" + (now | tostring)),
                redirectUris: [$redirectUri],
                tokenFormat: "JWT",
                expireInHours: 24,
                refreshExpireInHours: 168,
                grantTypes: ["authorization_code", "refresh_token"],
                organization: "built-in",
                isEnabled: true
              }')
            # Apply extra fields if any
            if [ -n "$extraFields" ]; then
              body=$(echo "$body" | jq "$extraFields")
            fi
            echo "$body" > /tmp/casdoor-app-"$name".json
            curl -sk "$AUTH_URL/api/add-application" \
              -H "Authorization: Bearer $TOKEN" \
              -H 'Content-Type: application/json' \
              -d @/tmp/casdoor-app-"$name".json >/dev/null 2>&1
            echo "[casdoor-app-registration] Created app '$name'"
          fi
        }

        # ── MapleSpike API App ─────────────────────────────────────
        # REST API gateway at api.maplespike.ca — authenticates API
        # callers via Casdoor OIDC access tokens (Bearer JWTs). The
        # api-server validates these with ./auth/oidc.ts (jose/JWKS).
        upsert_app \
          "app-maplespike-api" \
          "MapleSpike API" \
          "https://api.maplespike.ca/v1/auth/casdoor/callback"

        # ── MapleSpike Portal App ──────────────────────────────────
        # Portal frontend at quill.maplespike.ca — users log in via
        # Casdoor SSO redirect flow.
        upsert_app \
          "app-maplespike-portal" \
          "MapleSpike Portal" \
          "https://quill.maplespike.ca/v1/auth/casdoor/callback"

        # ── MapleSpike MCP App ─────────────────────────────────────
        # MCP SSE server — validates session tokens via JWKS (no
        # redirect/callback needed; uses client_credentials for
        # tool-to-tool auth and Bearer token validation).
        upsert_app \
          "app-maplespike-mcp" \
          "MapleSpike MCP" \
          "http://localhost:3001/oauth2/callback"

        echo "[casdoor-app-registration] Done."
      '';
    };
  };
}
