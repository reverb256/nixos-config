# ─────────────────────────────────────────────────────────────────
# secretspec-creds — Phase 4 SecretSpec credential provisioning.
#
# At activation, decrypts each sops file via `sops -d` and writes
# the resolved value to the declared /run/secrets/ path.
#
# Handles both binary-format sops files ({"data":"..."}) and
# YAML-format sops files (key: value) automatically.
# -----------------------------------------------------------------
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.secretspec-creds;

  writeScript = if cfg.enable then pkgs.writeShellScript "secretspec-write-creds" ''
    set -euo pipefail
    LOG="/var/log/secretspec-creds.log"
    log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

    SOPS="${pkgs.sops}/bin/sops"
    fail=0
    CONFIG="/etc/nixos/.sops.yaml"
    SECRETS_DIR="/etc/nixos/secrets"

    write_secret() {
      log "Decrypting $3 -> $2 ..."
      local _v
      # Decrypt without --extract to handle both binary and YAML formats
      _v=$("$SOPS" -d --config "$CONFIG" "$SECRETS_DIR/$3" 2>>"$LOG") || {
        log "FAILED: sops -d $3 (exit $?)"
        fail=1; return
      }
      # Auto-detect YAML-format sops (key: value) vs binary (raw data)
      if echo "$_v" | grep -q '^[a-zA-Z_][a-zA-Z0-9_]*:'; then
        # YAML format — strip the key prefix
        _v=$(echo "$_v" | sed 's/^[^:]*:[[:space:]]*//')
      fi
      if [ -z "$_v" ] || [ "$_v" = "null" ]; then
        log "FAILED: $3 resolved to empty/null"
        fail=1; return
      fi
      install -D -m "$4" -o "$5" -g "$6" \
        <(printf '%s' "$_v") "$2" 2>>"$LOG" || {
        log "FAILED: install $2"; fail=1; return
      }
      log "Wrote $2 ($(wc -c < "$2") bytes)"
    }

    ${concatStringsSep "\n" (mapAttrsToList (name: entry:
      "write_secret ${name} ${entry.path} ${entry.file} ${toString entry.mode} ${entry.owner} ${entry.group}"
    ) cfg.secrets)}

    if [ "$fail" = 1 ]; then
      log "One or more secrets failed -- see journalctl -u secretspec-creds"
      exit 1
    fi
    log "All ${builtins.toString (builtins.length (builtins.attrNames cfg.secrets))} secrets written."
  '' else pkgs.writeShellScript "secretspec-write-creds-dummy" "exit 0";
in {
  options.services.secretspec-creds = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable SecretSpec credential provisioning at activation.";
    };

    secrets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          path = mkOption { type = types.str; };
          file = mkOption { type = types.str; description = "Relative path under /etc/nixos/secrets/"; };
          mode = mkOption { type = types.str; default = "0444"; };
          owner = mkOption { type = types.str; default = "root"; };
          group = mkOption { type = types.str; default = "root"; };
        };
      });
      default = {};
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ sops ];

    systemd.services.secretspec-creds = {
      description = "SecretSpec credential provisioning -- sops-d + write /run/secrets/*";
      documentation = [ "https://secretspec.dev" ];
      wantedBy = ["multi-user.target"];
      before = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = writeScript;
        Environment = [ "SOPS_AGE_KEY_FILE=/etc/nixos/.age/key.txt" ];
        StandardOutput = "journal";
        StandardError = "journal";
        TimeoutStartSec = "5min";
      };
    };
  };
}