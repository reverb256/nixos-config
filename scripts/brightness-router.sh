#!/usr/bin/env bash
#
# brightness-router.sh — restore noctalia-shell **v4** brightness IPC surface
# (`brightness-up` / `-down` / `-get` / `-set <pct>`) on top of the v5 binary.
#
# noctalia v5 deliberately removed the built-in brightness control handler
# (the v4 plugin relied on a system-wide dbus signal that no longer exists).
# This shim recreates the IPC verb set, routing each verb to one of two
# backends, picked per output from a profile file:
#
#   DDC=connector   → ddcutil setvcp 0x10 (VCP brightness, true hardware)
#   NIRI=connector  → niri msg output <connector> sdr-brightness <0.10..1.00>
#                     (custom NV_PLANE_DEGAMMA_MULTIPLIER patch on NVIDIA outputs)
#
# DDC is preferred whenever a monitor supports it. The patch is the only
# option for outputs that lock I2C 0x37 (Samsung HDTVs over HDMI are the
# canonical example). Per-output routing is profile-driven so a single
# workstation with 4 monitors (DDC×3, NIRI×1) just works.
#
# State persistence:
#   niri has no `get` verb for sdr_brightness, so each output's last-known
#   % is cached in $XDG_STATE_HOME/brightness-router/<output>. ddcutil
#   `getvcp` is intentionally NOT used as the read source — it can take
#   200-800ms per call and would block key latency.
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
if [ ! -s "$PROFILE" ]; then
  cat >"$PROFILE" <<'EOF'
# Auto-seeded default profile (zephyr 4-monitor layout).
# Override at $XDG_CONFIG_HOME/brightness-router/outputs.env.
DDC=DP-4
DDC=DP-5
DDC=DP-6
NIRI=HDMI-A-2
EOF
fi

mapfile -t DDC_OUTS  < <(awk -F= '$1=="DDC"{print $2}'  "$PROFILE")
mapfile -t NIRI_OUTS < <(awk -F= '$1=="NIRI"{print $2}' "$PROFILE")

# ── Helpers ───────────────────────────────────────────────────────────
cache_get() { cat "$STATE_DIR/$1" 2>/dev/null || echo 100; }
cache_set() { echo "$2" >"$STATE_DIR/$1"; }

ddc_apply() {  # ddc_apply <output> <delta_pct>
  local o="$1" delta="$2" cur new
  cur=$(cache_get "$o")
  new=$(( cur + delta ))
  (( new < 0 ))   && new=0
  (( new > 100 )) && new=100
  ddcutil --display "$o" setvcp 0x10 "$new" --noverify 2>/dev/null \
    && cache_set "$o" "$new"
}

niri_apply() { # niri_apply <output> <delta_pct>
  local o="$1" delta="$2" cur new decimal
  cur=$(cache_get "$o")
  new=$(( cur + delta ))
  # sdr_brightness 0.10 = patch's documented floor (anything lower
  # clips to near-black on the NV_PLANE_DEGAMMA_MULTIPLIER range).
  (( new < 10 ))  && new=10
  (( new > 100 )) && new=100
  decimal=$(awk -v p="$new" 'BEGIN { printf "%.2f", p/100 }')
  niri msg output "$o" sdr-brightness "$decimal" >/dev/null 2>&1 \
    && cache_set "$o" "$new"
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
    for o in "${DDC_OUTS[@]}";  do ddc_apply  "$o"  5 & done
    for o in "${NIRI_OUTS[@]}"; do niri_apply "$o"  5;  done
    wait 2>/dev/null || true
    ;;
  brightness-down)
    for o in "${DDC_OUTS[@]}";  do ddc_apply  "$o" -5 & done
    for o in "${NIRI_OUTS[@]}"; do niri_apply "$o" -5;  done
    wait 2>/dev/null || true
    ;;
  brightness-get)
    sum=0; n=0
    for o in "${DDC_OUTS[@]}";  do v=$(cache_get "$o"); sum=$((sum+v)); n=$((n+1)); done
    for o in "${NIRI_OUTS[@]}"; do v=$(cache_get "$o"); sum=$((sum+v)); n=$((n+1)); done
    (( n > 0 )) && echo $(( sum / n )) || echo 100
    ;;
  brightness-set)
    [ $# -ge 2 ] || usage
    pct="$2"
    (( pct < 10 ))  && pct=10
    (( pct > 100 )) && pct=100
    decimal=$(awk -v p="$pct" 'BEGIN { printf "%.2f", p/100 }')
    for o in "${DDC_OUTS[@]}"; do
      ddcutil --display "$o" setvcp 0x10 "$pct" --noverify 2>/dev/null \
        && cache_set "$o" "$pct" &
    done
    for o in "${NIRI_OUTS[@]}"; do
      niri msg output "$o" sdr-brightness "$decimal" >/dev/null 2>&1 \
        && cache_set "$o" "$pct"
    done
    wait 2>/dev/null || true
    echo "$pct"
    ;;
esac
