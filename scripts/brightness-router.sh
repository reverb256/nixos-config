#!/usr/bin/env bash
#
# brightness-router.sh — restore noctalia-shell **v4** brightness IPC surface
# (`brightness-up` / `-down` / `-get` / `-set <pct>`) on top of the v5 binary.
#
# noctalia v5 deliberately removed the built-in brightness control handler
# (the v4 plugin relied on a system-wide dbus signal that no longer exists).
# This shim recreates the IPC verb set, routing each verb to ddcutil.
#
# Profile format (one entry per line, `#` comments OK):
#   DDC=<bus>:<drm-name>   → ddcutil --bus <bus> setvcp 0x10
#                           (use the drm-name as a state-cache key only;
#                            ddcutil is told the bus number, not the name)
#
# The bus-number form is the only one that survives `ddcutil detect`'s
# recent changes — DRM connector names (`DP-4`, `HDMI-A-2`, …) are
# rejected by `ddcutil --display` on newer ddcutil releases because the
# `--display` flag was deprecated in favor of `--bus`. The drm-name half
# of the tuple is kept as a human-readable cache key.
#
# Why no niri SDR fallback:
#   niri upstream does NOT expose an `sdr-brightness` subcommand.
#   The Zephyr host ships a local patch (see `patches/openrazer-hid-...`
#   directory) that adds it, but the patch is host-local: forge and
#   sentry run unpatched niri and would fail the verb. Routing through
#   ddcutil only keeps the wrapper portable across the cluster.
#
# State persistence:
#   Each output's last-known % is cached in
#   $XDG_STATE_HOME/brightness-router/<drm-name>. ddcutil `getvcp` is
#   intentionally NOT used as the read source — it can take 200-800ms
#   per call and would block key latency.
#
# Profile location:  $BRIGHTNESS_ROUTER_PROFILE  (override for tests/hosts)
#                    $XDG_CONFIG_HOME/brightness-router/outputs.env  (default)
#                    Auto-seeded with the zephyr 4-monitor layout on first run.

set -euo pipefail

PROFILE="${BRIGHTNESS_ROUTER_PROFILE:-${XDG_CONFIG_HOME:-$HOME/.config}/brightness-router/outputs.env}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/brightness-router"
mkdir -p "$STATE_DIR" "$(dirname "$PROFILE")"

# ── Profile auto-seed ─────────────────────────────────────────────────
# Per-host config can drop a custom file at $PROFILE. If none exists,
# fall back to the zephyr 4-monitor layout — the only host currently
# exercising this router, so seeding defaults is safe and saves a step.
# Run `ddcutil detect` to find your bus numbers — they're stable across
# reboots but vary per machine.
if [ ! -s "$PROFILE" ]; then
  cat >"$PROFILE" <<'EOF'
# Auto-seeded default profile (zephyr 4-monitor layout).
# Override at $XDG_CONFIG_HOME/brightness-router/outputs.env.
# Format: DDC=<bus>:<drm-name>
DDC=8:DP-4
DDC=9:DP-5
DDC=10:DP-6
# HDMI-A-2 (Samsung HDTV): I2C is locked, no DDC/CI possible.
# niri SDR patch path is host-local (zephyr only) so intentionally not
# exposed here; control via the TV remote or a CEC adapter.
EOF
fi

# Pull `DDC=<bus>:<name>` rows. The awk guard skips malformed lines so
# commented-out entries or typos in the profile don't blow up the script.
mapfile -t DDC_ENTRIES < <(awk -F= '$1=="DDC" && $2 ~ /:/ {print $2}' "$PROFILE")

# ── One-shot migration from v1 format (DDC=DP-4) to v2 (DDC=8:DP-4) ──
# 2026-07-07: ddcutil deprecated --display in favor of --bus, so the
# bus-numbered form is the only one that survives a modern ddcutil.
# The auto-seed only fires when the profile is missing/empty, so an
# existing v1 profile is invisible to the new logic and would silently
# no-op.
#
# Host-gated: the ZEPHYR_BUS table is specific to zephyr's physical
# layout. If forge or sentry ever has a v1 profile (e.g., copy-pasted
# from zephyr), blindly rewriting with zephyr's bus numbers would
# silently corrupt them. On non-zephyr hosts we emit a warning and
# leave the profile alone — unmigrated v1 lines turn into no-ops
# (the awk filter requires `:` so they're skipped) rather than
# triggering destructive ddcutil calls against the wrong bus. The
# user can `ddcutil detect` to find their bus numbers and edit the
# profile by hand.
if grep -qE '^[[:space:]]*DDC=[^:]+([[:space:]]*$|#)' "$PROFILE" 2>/dev/null; then
  if [[ "$(uname -n 2>/dev/null)" != "zephyr" ]]; then
    # Rate-limit the warning to once per profile via a sentinel file.
    # Without this, every brightness keypress on a non-zephyr host
    # would log the same migration message to stderr.
    if [[ ! -f "${PROFILE}.warned" ]]; then
      echo "brightness-router: v1 profile format detected on non-zephyr host. Manual migration to v2 (bus:DRM-name) required." >&2
      : >"${PROFILE}.warned"
    fi
  else
    echo "brightness-router: migrating v1 profile to v2 (bus:DRM-name) format" >&2
    declare -A ZEPHYR_BUS=(
      ["DP-1"]="3" ["DP-2"]="4" ["DP-3"]="5" ["DP-4"]="8"
      ["DP-5"]="9" ["DP-6"]="10" ["HDMI-A-1"]="6" ["HDMI-A-2"]="7"
    )
    tmp="${PROFILE}.migrate.$$"
    {
      while IFS= read -r line; do
        case "$line" in
          ''|'#'*) printf '%s\n' "$line" ;;
          DDC=*)
            name="${line#DDC=}"
            name="${name%%[[:space:]]*}"
            bus="${ZEPHYR_BUS[$name]:-}"
            if [ -n "$bus" ]; then
              printf 'DDC=%s:%s\n' "$bus" "$name"
            else
              echo "brightness-router: no bus mapping for '$name', leaving line untouched: $line" >&2
              printf '%s\n' "$line"
            fi
            ;;
          *) printf '%s\n' "$line" ;;
        esac
      done <"$PROFILE"
    } >"$tmp" && mv "$tmp" "$PROFILE"
    # Re-parse with the migrated file
    mapfile -t DDC_ENTRIES < <(awk -F= '$1=="DDC" && $2 ~ /:/ {print $2}' "$PROFILE")
  fi
fi

# ── Helpers ───────────────────────────────────────────────────────────
cache_get() { cat "$STATE_DIR/$1" 2>/dev/null || echo 100; }
cache_set() { echo "$2" >"$STATE_DIR/$1"; }

ddc_apply() {  # ddc_apply <bus>:<name> <delta_pct>
  local entry="$1" delta="$2" bus name cur new
  bus="${entry%%:*}"
  name="${entry##*:}"
  cur=$(cache_get "$name")
  new=$(( cur + delta ))
  (( new < 0 ))   && new=0
  (( new > 100 )) && new=100
  ddcutil --bus "$bus" setvcp 0x10 "$new" --noverify 2>/dev/null \
    && cache_set "$name" "$new"
}

ddc_set_pct() {  # ddc_set_pct <bus>:<name> <pct>
  local entry="$1" pct="$2" bus name
  bus="${entry%%:*}"
  name="${entry##*:}"
  (( pct < 0 ))   && pct=0
  (( pct > 100 )) && pct=100
  ddcutil --bus "$bus" setvcp 0x10 "$pct" --noverify 2>/dev/null \
    && cache_set "$name" "$pct"
}

usage() {
  cat >&2 <<USAGE
usage: brightness-router {brightness-up|brightness-down|brightness-get|brightness-set <pct>}
  env BRIGHTNESS_ROUTER_PROFILE=<path>      override profile file
  env XDG_STATE_HOME=<path>                state dir (default ~/.local/state)
  env XDG_CONFIG_HOME=<path>               config dir (default ~/.config)
USAGE
  exit 64
}

[ $# -ge 1 ] || usage
case "$1" in
  brightness-up|brightness-down|brightness-get|brightness-set) ;;
  *) usage ;;
esac

# ── Dispatch ──────────────────────────────────────────────────────────
case "$1" in
  brightness-up)
    for e in "${DDC_ENTRIES[@]}"; do ddc_apply "$e" 5 & done
    wait 2>/dev/null || true
    ;;
  brightness-down)
    for e in "${DDC_ENTRIES[@]}"; do ddc_apply "$e" -5 & done
    wait 2>/dev/null || true
    ;;
  brightness-get)
    sum=0; n=0
    for e in "${DDC_ENTRIES[@]}"; do
      name="${e##*:}"
      v=$(cache_get "$name")
      sum=$((sum+v))
      n=$((n+1))
    done
    (( n > 0 )) && echo $(( sum / n )) || echo 100
    ;;
  brightness-set)
    [ $# -ge 2 ] || usage
    pct="$2"
    for e in "${DDC_ENTRIES[@]}"; do ddc_set_pct "$e" "$pct" & done
    wait 2>/dev/null || true
    echo "$pct"
    ;;
esac
