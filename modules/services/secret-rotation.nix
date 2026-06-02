{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.secret-rotation;
  inherit (lib) mkEnableOption mkOption types mkIf;

  rotationScript = pkgs.writeShellScript "secret-rotation" ''
        set -euo pipefail

        SECRETS_DIR="/etc/nixos/secrets"
        AGE_KEY="/etc/age/key.txt"
        ROTATION_LOG="/var/log/secret-rotation.log"
        ROTATION_STATE="/var/lib/secret-rotation/state.json"
        KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

        log() {
          local level="$1"; shift
          echo "[$(date -Iseconds)] [$level] $*" | tee -a "$ROTATION_LOG"
        }

        generate_secret() {
          head -c "$(($1 * 2))" /dev/urandom | base64 | tr -d '\n=' | head -c "$1"
        }

        # Find age identity key
        find_identity() {
          for path in /etc/age/key.txt /etc/nixos/.age/key.txt /home/j_kro/.age/key.txt /persistent/etc/age/key.txt; do
            if [ -f "$path" ]; then
              echo "$path"
              return 0
            fi
          done
          return 1
        }

        # Get public key from private key
        get_pubkey() {
          local identity="$1"
          ${pkgs.age}/bin/age keygen -y < "$identity" 2>/dev/null || echo ""
        }

        rotate_secret() {
          local name="$1"
          local chars="$2"
          local desc="$3"

          log INFO "Rotating: $name ($desc)"

          local new_value
          new_value=$(generate_secret "$chars")
          [ -z "$new_value" ] && { log ERROR "Failed to generate value for $name"; return 1; }

          local identity
          identity=$(find_identity) || { log ERROR "No age identity key found"; return 1; }
          local pubkey
          pubkey=$(get_pubkey "$identity")
          [ -z "$pubkey" ] && { log ERROR "Cannot derive public key from identity"; return 1; }

          local age_file="$SECRETS_DIR/$name.age"
          if [ ! -f "$age_file" ]; then
            log WARN "Age file not found: $age_file — skipping"
            return 0
          fi

          # Try agenix CLI first (respects secrets.nix multi-recipient)
          if command -v agenix &>/dev/null; then
            local tmpfile
            tmpfile=$(mktemp)
            echo -n "$new_value" > "$tmpfile"
            if EDITOR="cp $tmpfile" agenix -e "$age_file" -i "$identity" 2>/dev/null; then
              rm -f "$tmpfile"
              log INFO "Re-encrypted via agenix: $name"
              return 0
            fi
            rm -f "$tmpfile"
          fi

          # Fallback: single-recipient age encryption
          echo -n "$new_value" | ${pkgs.age}/bin/age -r "$pubkey" -o "$age_file" 2>/dev/null && {
            log INFO "Re-encrypted via age: $name"
            return 0
          }

          log ERROR "Failed to re-encrypt: $name"
          return 1
        }

        restart_workload() {
          local ns="$1"
          local deploy="$2"
          log INFO "Restarting $ns/$deploy"
          ${pkgs.kubectl}/bin/kubectl rollout restart deployment/"$deploy" -n "$ns" 2>/dev/null || \
            log WARN "Failed to restart $ns/$deploy"
        }

        # ─── Main Rotation ───

        log INFO "=== Automated Tier 1 Secret Rotation ==="

        # Tier 1 secrets (name:chars:description)
        declare -A TIER1
        TIER1[central-auth-cookie-secret]="64:OAuth2 proxy cookie secret"
        TIER1[searxng-secret-key]="32:SearXNG internal secret"
        TIER1[garage-rpc-secret]="64:Garage S3 RPC shared secret"
        TIER1[garage-metrics-token]="32:Garage metrics bearer token"
        TIER1[grafana-admin-password]="24:Grafana admin UI password"
        TIER1[n8n-admin-password]="24:n8n admin password"
        TIER1[mission-control-auth-pass]="32:Mission Control auth password"
        TIER1[mission-control-api-key]="32:Mission Control API key"
        TIER1[vaultwarden-admin-token]="32:Vaultwarden admin panel token"
        # hermes-webui-password -- archived (2026-05-16)
        TIER1[hermes-api-server-key]="64:Hermes API server signing key"
        TIER1[garnix-password]="24:Garnix CI password"
        TIER1[switch-admin]="24:TP-Link switch admin password"
        TIER1[activepieces-jwt-secret]="64:Activepieces JWT signing secret"
        TIER1[xmrig-api-token]="32:XMRig API token"
        TIER1[xmrig-always-api-token]="32:XMRig always-on API token"
        TIER1[xmrig-flexible-api-token]="32:XMRig flexible API token"
        TIER1[xmrig-proxy-api-token]="32:XMRig proxy API token"

        # K8s workloads to restart per secret
        declare -A K8S_RESTART
        K8S_RESTART[central-auth-cookie-secret]="auth/oauth2-proxy"
        K8S_RESTART[searxng-secret-key]="search/searxng"
        K8S_RESTART[grafana-admin-password]="monitoring/grafana"
        K8S_RESTART[n8n-admin-password]="automation/n8n"
        K8S_RESTART[mission-control-auth-pass]="orchestration/mission-control"
        K8S_RESTART[mission-control-api-key]="orchestration/mission-control"
        K8S_RESTART[xmrig-api-token]="mining/gpu-miner-zephyr"
        K8S_RESTART[xmrig-always-api-token]="mining/gpu-miner-nexus"
        K8S_RESTART[xmrig-flexible-api-token]="mining/gpu-miner-forge"
        K8S_RESTART[xmrig-proxy-api-token]="mining/xmrig-proxy"

        rotated=0
        failed=0
        skipped=0
        rotated_names=""

        for name in "''${!TIER1[@]}"; do
          entry="''${TIER1[$name]}"
          chars="''${entry%%:*}"
          desc="''${entry#*:}"

          age_file="$SECRETS_DIR/$name.age"
          if [ ! -f "$age_file" ]; then
            log WARN "Not found: $age_file"
            skipped=$((skipped + 1))
            continue
          fi

          if rotate_secret "$name" "$chars" "$desc"; then
            rotated=$((rotated + 1))
            rotated_names="$rotated_names $name"
          else
            failed=$((failed + 1))
          fi
        done

        log INFO "Rotation results: $rotated rotated, $failed failed, $skipped skipped"

        # Git commit all rotated secrets
        if [ "$rotated" -gt 0 ]; then
          log INFO "Committing rotated secrets to git..."
          cd /etc/nixos
          ${pkgs.git}/bin/git add secrets/*.age 2>/dev/null || true
          ${pkgs.git}/bin/git commit -m "security: quarterly secret rotation ($(date +%Y-%m-%d))" 2>/dev/null || \
            log WARN "Git commit failed or nothing to commit"

          # Deploy to all nodes
          log INFO "Deploying rotated secrets..."
          if ${pkgs.just}/bin/just deploy 2>&1; then
            log INFO "Deploy successful"

            # Restart affected K8s workloads
            log INFO "Restarting K8s workloads..."
            for name in $rotated_names; do
              if [ -n "''${K8S_RESTART[$name]:-}" ]; then
                dep="''${K8S_RESTART[$name]}"
                ns="''${dep%%/*}"
                dname="''${dep#*/}"
                restart_workload "$ns" "$dname"
              fi
            done
          else
            log ERROR "Deploy failed — rotated secrets not applied"
            exit 1
          fi
        fi

        # Update rotation state
        mkdir -p "$(dirname $ROTATION_STATE)"
        ${pkgs.python3}/bin/python3 -c "
    import json, datetime, os
    state = {}
    try:
        with open('$ROTATION_STATE') as f: state = json.load(f)
    except: pass
    state.setdefault('tier1', {})['last_run'] = datetime.datetime.now().isoformat()
    state['tier1']['rotated'] = $rotated
    state['tier1']['failed'] = $failed
    with open('$ROTATION_STATE', 'w') as f:
        json.dump(state, f, indent=2)
    " 2>/dev/null || true

        log INFO "=== Rotation complete ==="
  '';
in {
  options.services.secret-rotation = {
    enable = mkEnableOption "Automated secret rotation service";

    schedule = mkOption {
      type = types.str;
      default = "quarterly";
      description = "Rotation schedule: monthly, quarterly, or a systemd timer OnCalendar expression";
    };

    onCalendar = mkOption {
      type = types.str;
      default = "*-01,04,07,10-15 03:00:00"; # Quarterly on the 15th of Jan/Apr/Jul/Oct at 3am
      description = "systemd timer OnCalendar expression for rotation schedule";
    };

    rotateTier1 = mkOption {
      type = types.bool;
      default = true;
      description = "Auto-rotate Tier 1 secrets (self-generated random values)";
    };

    notifyOnRotation = mkOption {
      type = types.bool;
      default = true;
      description = "Send notification after rotation completes";
    };
  };

  config = mkIf cfg.enable {
    # Rotation state directory
    systemd.tmpfiles.rules = [
      "d /var/lib/secret-rotation 0700 root root -"
      "d /var/log 0755 root root -"
    ];

    # Systemd service
    systemd.services.secret-rotation = {
      description = "Automated Tier 1 Secret Rotation";
      path = with pkgs; [age git just kubectl python3 coreutils gnused];
      environment = {
        KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
        HOME = "/root";
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = rotationScript;
        ProtectSystem = "strict";
        ReadWritePaths = "/etc/nixos/secrets /var/lib/secret-rotation /var/log /root/.gitconfig";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = false; # Need git + just capabilities
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "secret-rotation";
      };
    };

    # Systemd timer
    systemd.timers.secret-rotation = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true; # Run on boot if schedule was missed
        RandomizedDelaySec = "10m"; # Spread across cluster nodes
        AccuracySec = "1h";
      };
    };

    # Notification hook (log to journal, could extend to send_message)
    systemd.services.secret-rotation-notify = {
      description = "Post-rotation notification";
      after = ["secret-rotation.service"];
      requires = ["secret-rotation.service"];
      wantedBy = ["secret-rotation.service"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "rotation-notify" ''
                    set -euo pipefail
                    STATE="/var/lib/secret-rotation/state.json"
                    if [ -f "$STATE" ]; then
                      echo "Secret rotation completed. Check journal for details."
                      ${pkgs.python3}/bin/python3 -c "
          import json
          with open('$STATE') as f: s = json.load(f)
          t1 = s.get('tier1', {})
          print(f\"Last run: {t1.get('last_run', 'unknown')}\")
          print(f\"Rotated: {t1.get('rotated', 0)}\")
          print(f\"Failed: {t1.get('failed', 0)}\")
          " 2>/dev/null || echo "State file unreadable"
                    else
                      echo "No rotation state file found"
                    fi
        '';
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "secret-rotation-notify";
      };
    };

    # Expose the manual script too
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "secret-rotation" ''
        exec /etc/nixos/scripts/secret-rotation.sh "$@"
      '')
    ];
  };
}
