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

    ageKeyFile = mkOption {
      type = types.str;
      default = "/etc/nixos/.age/key.txt";
      description = ''
        Path to the SOPS-compatible age keyfile used to decrypt every
        entry in <option>secrets</option>. On zephyr this is the
        operator's YubiKey-derived age key; remote hosts must receive a
        copy of the same keyfile via one of:

         * Nix-managed etc (`environment.etc."nixos/age/key.txt".source`),
           preferred because no plaintext lands on disk outside /nix/store;
         * sops-nix decrypted file (`sops.secrets."cluster-age-key".path =
           cfg.ageKeyFile;`) using a per-host identity;
         * Manual `scp` from zephyr for one-off lab deployments.

        Override per-host in <option>services.secretspec-validator.ageKeyFile</option>
        if the validator should resolve from a different identity.
      '';
    };

    secrets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          path = mkOption { type = types.str; };
          file = mkOption { type = types.str; description = "Relative path under /etc/nixos/secrets/"; };
          mode = mkOption { type = types.str; default = "0444"; };
          owner = mkOption { type = types.str; default = "root"; };
          group = mkOption { type = types.str; default = "root"; };
          key = mkOption { type = types.str; default = "data"; description = "Key to extract from sops file (e.g. data for JSON, exa_api_key for YAML)"; };
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
        Environment = [ "SOPS_AGE_KEY_FILE=${cfg.ageKeyFile}" ];
        # A transient failure (e.g. mid-pull network blip when re-evaluating
        # /etc/nixos/secrets/, or a YubiKey unplug-replug mid-boot) should
        # retry — the validator service (newly Wants+d this unit) would
        # otherwise run against an empty /run/secrets/* and produce noise.
        # StartLimitBurst keeps sustained failures visible in the journal
        # rather than letting the unit silently fail forever.
        Restart = "on-failure";
        RestartSec = "30s";
        StartLimitBurst = 3;
        StartLimitIntervalSec = "5min";
        StandardOutput = "journal";
        StandardError = "journal";
        TimeoutStartSec = "5min";
      };
    };
  };
}