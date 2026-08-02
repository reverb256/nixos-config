#!/usr/bin/env bash
#
# sentry-sentinel - liveness watchdog + Wake-on-LAN OOB recovery for Sentry.
#
# Runs on Nexus (the always-up bootstrap/dispatch host, 10.1.1.120). Sentry
# (10.1.1.140) is a bare-metal k8s/monitoring node with NO IPMI/BMC/PDU and
# (as of 2026-08-02) no working remote recovery path. This guard:
#   1. pings sentry every tick;
#   2. once sentry has been down > downForMinutes, logs a CRIT journal entry
#      (queryable on nexus via `journalctl -u sentry-sentinel`) and, if an
#      ntfy URL is configured, posts a push alert;
#   3. sends a Wake-on-LAN magic packet on a cooldown to attempt recovery.
#
# WoL only works if Sentry's BIOS has WoL/PME enabled on the onboard NIC
# (the r8169 Realtek adapter supports it). If WoL is inert AND sentry stays
# down, the only recovery is a physical power-cycle at the rack - see the
# escalation incident note in docs/incidents/.
#
set -u

HOST="${SENTRY_HOST:-10.1.1.140}"
MAC="${SENTRY_MAC:-70:85:c2:d2:87:bf}"
DOWN_FOR="${SENTRY_DOWN_FOR:-15}"          # minutes down before we alert + WoL
WOL_COOLDOWN="${SENTRY_WOL_COOLDOWN:-30}"  # minutes between WoL attempts
NTFY="${SENTRY_NTFY:-}"                    # optional ntfy POST target
STATE_DIR=/var/lib/sentry-sentinel
mkdir -p "$STATE_DIR"
DOWN_SINCE="$STATE_DIR/down-since"
WOL_LAST="$STATE_DIR/wol-last"
NOW="$(date +%s)"

# --- reachability probe -------------------------------------------------------
if ping -c 3 -W 2 "$HOST" >/dev/null 2>&1; then
  if [ -f "$DOWN_SINCE" ]; then
    logger -t sentry-sentinel -p info "Sentry ($HOST) is back up; clearing down state"
  fi
  rm -f "$DOWN_SINCE" "$WOL_LAST"
  exit 0
fi

# --- host is down -------------------------------------------------------------
if [ ! -f "$DOWN_SINCE" ]; then
  echo "$NOW" > "$DOWN_SINCE"
  DOWN_MIN=0
else
  START="$(cat "$DOWN_SINCE")"
  DOWN_MIN=$(( (NOW - START) / 60 ))
fi

alert() {
  logger -t sentry-sentinel -p crit \
    "SENTRY ($HOST) UNREACHABLE for ${DOWN_MIN}m (threshold ${DOWN_FOR}m). OOB: WoL sent; if no response, physical power-cycle required at rack."
  if [ -n "$NTFY" ]; then
    curl -sS -m 5 -X POST \
      -H "Title: Sentry down ${DOWN_MIN}m" \
      -H "Priority: high" \
      -H "Tags: warning,sentry" \
      -d "Sentry $HOST unreachable ${DOWN_MIN}m. WoL magic packet sent. If it does not return within ~10m, a physical power-cycle at the rack is required (no IPMI/PDU present)." \
      "$NTFY" || true
  fi
}

if [ "$DOWN_MIN" -ge "$DOWN_FOR" ]; then
  alert
  LAST=0
  [ -f "$WOL_LAST" ] && LAST="$(cat "$WOL_LAST")"
  ELAPSED_WOL=$(( (NOW - LAST) / 60 ))
  if [ "$ELAPSED_WOL" -ge "$WOL_COOLDOWN" ]; then
    # Broadcast on the 10.1.1.0/24 L2 segment; wakeonlan falls back to
    # 255.255.255.255 if -i is unsupported.
    wakeonlan -i 10.1.1.255 "$MAC" 2>/dev/null || wakeonlan "$MAC" 2>/dev/null || true
    echo "$NOW" > "$WOL_LAST"
    logger -t sentry-sentinel -p info "Sent WoL magic packet to $MAC (broadcast 10.1.1.255)"
  fi
fi

exit 0
