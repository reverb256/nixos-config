{
  config,
  lib,
  pkgs,
  ...
}:
# memlawb durability health check (runs on ZEPHYR, where the memlawb client
# and the zero-knowledge passphrase live — NOT on sentry, because only the
# CLIENT needs the passphrase; the server is zero-knowledge and never sees it).
#
# What it verifies (per run):
#   1. memlawb server is reachable (push a probe entry to user:j_kro)
#   2. the passphrase actually decrypts a round-trip (pull it back, compare)
#   3. cleanup (delete the probe via MemlawbClient.delete)
# Exits non-zero on any failure so the systemd timer failure is visible in
# `systemctl status` / journalctl.
#
# Enable on zephyr, e.g. in hosts/zephyr/configuration.nix:
#   services.memlawb-healthcheck.enable = true;
let
  cfg = config.services.memlawb-healthcheck;

  healthcheckScript = pkgs.writeShellScriptBin "memlawb-healthcheck" ''
    #!/usr/bin/env bash
    set -euo pipefail

    MEMLAWB_URL="''${MEMLAWB_URL:-http://10.1.1.140:8080}"
    MEMLAWB_NAMESPACE="''${MEMLAWB_NAMESPACE:-user:j_kro}"
    BUN="''${BUN_BIN:-/run/current-system/sw/bin/bun}"
    MEMLAWB_BIN="''${MEMLAWB_BIN:-/home/j_kro/.local/share/memlawb/bin/memlawb.ts}"
    CLIENT_LIB="''${MEMLAWB_CLIENT:-/home/j_kro/.local/share/memlawb/client/index.ts}"
    PASSPHRASE_FILE="''${MEMLAWB_PASSPHRASE_FILE:-/home/j_kro/.memlawb-passphrase.txt}"

    export MEMLAWB_URL
    export MEMLAWB_NAMESPACE
    # warn (not block): a healthcheck probe must never be refused by the
    # secret scanner, but we also do not want it silently dropping a real
    # finding in normal operation.
    export MEMLAWB_SCAN="''${MEMLAWB_SCAN:-warn}"
    export PATH="/run/current-system/sw/bin:$PATH"
    export HOME="''${HOME:-/home/j_kro}"

    if [ ! -x "$BUN" ]; then
      echo "memlawb-healthcheck: bun not found at $BUN" >&2
      exit 1
    fi
    if [ ! -f "$MEMLAWB_BIN" ]; then
      echo "memlawb-healthcheck: memlawb CLI not found at $MEMLAWB_BIN" >&2
      exit 1
    fi
    if [ ! -r "$PASSPHRASE_FILE" ]; then
      echo "memlawb-healthcheck: passphrase file not readable: $PASSPHRASE_FILE" >&2
      exit 1
    fi
    export MEMLAWB_PASSPHRASE="$(cat "$PASSPHRASE_FILE")"

    PROBE_DIR="$(mktemp -d)"
    PULL_DIR="$(mktemp -d)"
    trap 'rm -rf "$PROBE_DIR" "$PULL_DIR"' EXIT

    PROBE_KEY="_memlawb_healthcheck_probe.md"
    PROBE_TEXT="memlawb healthcheck round-trip $(date -Iseconds) nonce=$RANDOM"

    echo "$PROBE_TEXT" > "$PROBE_DIR/$PROBE_KEY"

    echo "[healthcheck] pushing probe -> $MEMLAWB_URL ns=$MEMLAWB_NAMESPACE"
    "$BUN" "$MEMLAWB_BIN" push "$PROBE_DIR" "$MEMLAWB_NAMESPACE"

    echo "[healthcheck] pulling back"
    "$BUN" "$MEMLAWB_BIN" pull "$PULL_DIR" "$MEMLAWB_NAMESPACE"

    if [ ! -f "$PULL_DIR/$PROBE_KEY" ]; then
      echo "[healthcheck] FAIL: probe entry not returned by pull (server/namespace unreachable or decrypt failed)" >&2
      exit 1
    fi
    PULLED="$(cat "$PULL_DIR/$PROBE_KEY")"
    if [ "$PULLED" != "$PROBE_TEXT" ]; then
      echo "[healthcheck] FAIL: decrypted content mismatch (passphrase decrypt round-trip broken)" >&2
      echo "  expected: $PROBE_TEXT" >&2
      echo "  got:      $PULLED" >&2
      exit 1
    fi

    echo "[healthcheck] deleting probe"
    "$BUN" -e "import { MemlawbClient } from '$CLIENT_LIB'; const c = new MemlawbClient({ url: process.env.MEMLAWB_URL, passphrase: process.env.MEMLAWB_PASSPHRASE, scanMode: 'block' }); await c.delete(process.env.MEMLAWB_NAMESPACE, '$PROBE_KEY'); console.log('probe deleted');"

    echo "[healthcheck] OK: server reachable, passphrase decrypts round-trip, probe cleaned up"
  '';
in {
  options.services.memlawb-healthcheck = {
    enable = lib.mkEnableOption "Periodic memlawb health check (reachability + passphrase decrypt round-trip)";

    url = lib.mkOption {
      type = lib.types.str;
      default = "http://10.1.1.140:8080";
      description = "memlawb server URL (sentry).";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "user:j_kro";
      description = "Namespace used for the probe round-trip.";
    };

    passphraseFile = lib.mkOption {
      type = lib.types.str;
      default = "/home/j_kro/.memlawb-passphrase.txt";
      description = "File with the zero-knowledge passphrase (chmod 600, j_kro).";
    };

    binPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/j_kro/.local/share/memlawb/bin/memlawb.ts";
      description = "Path to the memlawb CLI (bun script).";
    };

    clientLib = lib.mkOption {
      type = lib.types.str;
      default = "/home/j_kro/.local/share/memlawb/client/index.ts";
      description = "Path to the MemlawbClient module (used for the delete step).";
    };

    bunBin = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.bun}/bin/bun";
      description = "Path to the bun executable (declarative store path).";
    };

    startAt = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 00/6:00:00";
      description = "systemd timer OnCalendar (every 6 hours).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to run as (must read the passphrase file).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.bun];

    systemd.services.memlawb-healthcheck = {
      description = "memlawb reachability + passphrase decrypt round-trip health check";
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.user;
        Environment = [
          "MEMLAWB_URL=${cfg.url}"
          "MEMLAWB_NAMESPACE=${cfg.namespace}"
          "MEMLAWB_PASSPHRASE_FILE=${cfg.passphraseFile}"
          "MEMLAWB_BIN=${cfg.binPath}"
          "MEMLAWB_CLIENT=${cfg.clientLib}"
          "BUN_BIN=${cfg.bunBin}"
          "PATH=/run/current-system/sw/bin"
          "HOME=/home/j_kro"
        ];
        ExecStart = "${healthcheckScript}/bin/memlawb-healthcheck";
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };

    systemd.timers.memlawb-healthcheck = {
      description = "Periodic memlawb health check timer (every 6h)";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.startAt;
        Persistent = true;
        Unit = "memlawb-healthcheck.service";
      };
    };
  };
}
