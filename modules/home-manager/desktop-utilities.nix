{ pkgs, lib, config, ... }:

let
  # ═══════════════════════════════════════════════════════════════
  # SMART SCREENSHOT
  # Modes: region (default), window, fullscreen, color
  # Smart mode: if selection < 20x20, snaps to containing window
  # Auto-opens satty editor, copies to clipboard
  # Noctilia has no built-in screenshot tool, this fills that gap.
  # ═══════════════════════════════════════════════════════════════
  screenshot = pkgs.writeShellScriptBin "screenshot" ''
    #!/usr/bin/env bash
    set -euo pipefail

    MODE="''${1:-region}"
    SCREENSHOT_DIR="''${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}"
    mkdir -p "$SCREENSHOT_DIR"

    FILE="$SCREENSHOT_DIR/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"

    case "$MODE" in
      region)
        # Smart region: select area, snap to window if tiny selection
        GEOM="$(${pkgs.slurp}/bin/slurp -b 00000066 -c 8fbcbb -s 00000000 -w 2 2>/dev/null)" || exit 0

        # Parse geometry: X,Y WxH
        read -r X Y W H <<< "$(echo "$GEOM" | sed 's/,/ /g; s/x/ /')"
        AREA=$((W * H))

        if [ "$AREA" -lt 400 ]; then
          # Tiny selection (< 20x20) -- snap to focused window
          GEOM=$(${pkgs.niri}/bin/niri msg --json focused-window 2>/dev/null | \
            ${pkgs.jq}/bin/jq -r '"\(.output_x),\(.output_y) \(.width)x\(.height)"' 2>/dev/null) || true
        fi

        [ -n "$GEOM" ] && ${pkgs.grim}/bin/grim -g "$GEOM" "$FILE" || ${pkgs.grim}/bin/grim "$FILE"
        ;;
      window)
        GEOM=$(${pkgs.niri}/bin/niri msg --json focused-window 2>/dev/null | \
          ${pkgs.jq}/bin/jq -r '"\(.output_x),\(.output_y) \(.width)x\(.height)"' 2>/dev/null) || true

        [ -n "$GEOM" ] && ${pkgs.grim}/bin/grim -g "$GEOM" "$FILE" || ${pkgs.grim}/bin/grim "$FILE"
        ;;
      fullscreen)
        ${pkgs.grim}/bin/grim "$FILE"
        ;;
      color)
        COLOR=$(${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp -p)" -t png - | \
          ${pkgs.imagemagick}/bin/convert png:- -resize 1x1\! -format '%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]' info:- 2>/dev/null)
        if [ -n "$COLOR" ]; then
          HEX=$(${pkgs.imagemagick}/bin/convert "rgb($COLOR)" -format '%[hex:s]' info:- 2>/dev/null)
          echo "#$HEX" | ${pkgs.wl-clipboard}/bin/wl-copy
          notify-send "Color Picker" "#$HEX ($COLOR)" -i color-picker 2>/dev/null || true
        fi
        exit 0
        ;;
      *)
        echo "Usage: screenshot [region|window|fullscreen|color]" >&2
        exit 1
        ;;
    esac

    # Copy to clipboard
    ${pkgs.wl-clipboard}/bin/wl-copy < "$FILE"

    # Open in satty editor in background
    ${pkgs.satty}/bin/satty --filename "$FILE" --output-filename "$FILE" \
      --actions-on-enter save-to-clipboard --save-after-copy --copy-command 'wl-copy' &

    notify-send "Screenshot saved" "$(basename "$FILE")" -i camera-photo -t 3000 2>/dev/null || true
  '';

  # ═══════════════════════════════════════════════════════════════
  # SCREEN RECORDING
  # Toggle-based: run once to start, run again to stop.
  # Audio modes: none (default), desktop, mic, both
  # State file for recording indicator integration with Noctilia hooks.
  # ═══════════════════════════════════════════════════════════════
  screenrecord = pkgs.writeShellScriptBin "screenrecord" ''
    #!/usr/bin/env bash
    set -euo pipefail

    STATE_FILE="/tmp/screenrecord-active"
    RECORDING_DIR="''${RECORDING_DIR:-$HOME/Videos/Recordings}"
    mkdir -p "$RECORDING_DIR"

    # Toggle: if already recording, stop
    if [ -f "$STATE_FILE" ]; then
      PID=$(cat "$STATE_FILE")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        wait "$PID" 2>/dev/null || true
        notify-send "Recording stopped" -i media-playback-stop 2>/dev/null || true
      fi
      rm -f "$STATE_FILE"
      exit 0
    fi

    # Start recording
    AUDIO="''${1:-none}"
    FILE="$RECORDING_DIR/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4"

    AUDIO_ARGS=()
    case "$AUDIO" in
      desktop)
        SINK=$(pactl get-default-sink 2>/dev/null || echo "")
        [ -n "$SINK" ] && AUDIO_ARGS=("-a" "''${SINK}.monitor")
        ;;
      mic)
        SOURCE=$(pactl get-default-source 2>/dev/null || echo "")
        [ -n "$SOURCE" ] && AUDIO_ARGS=("-a" "$SOURCE")
        ;;
      both)
        SINK=$(pactl get-default-sink 2>/dev/null || echo "")
        SOURCE=$(pactl get-default-source 2>/dev/null || echo "")
        [ -n "$SINK" ] && [ -n "$SOURCE" ] && AUDIO_ARGS=("-a" "''${SINK}.monitor" "-a" "$SOURCE")
        ;;
    esac

    notify-send "Recording started" "Audio: $AUDIO" -i media-record -t 2000 2>/dev/null || true

    # Use gpu-screen-recorder via portal, fall back to wf-recorder
    if command -v gpu-screen-recorder &>/dev/null; then
      gpu-screen-recorder "''${AUDIO_ARGS[@]}" -w portal -f 60 -o "$FILE" &
    else
      ${pkgs.wf-recorder}/bin/wf-recorder "''${AUDIO_ARGS[@]}" -f "$FILE" &
    fi

    echo $! > "$STATE_FILE"
  '';

  # ═══════════════════════════════════════════════════════════════
  # FILE-BASED TOGGLES
  # Complements Noctilia's in-memory IPC toggles with persistent state
  # that survives shell restarts. Useful for niri config sourcing.
  # Usage: toggle <name> / toggle-enabled <name> / toggle-get <name>
  # ═══════════════════════════════════════════════════════════════
  toggle = pkgs.writeShellScriptBin "toggle" ''
    #!/usr/bin/env bash
    set -euo pipefail
    STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/toggles"
    mkdir -p "$STATE_DIR"
    NAME="''${1:?Usage: toggle <name>}"
    FLAG="$STATE_DIR/$NAME"
    if [ -f "$FLAG" ]; then rm "$FLAG"; echo "off"; else touch "$FLAG"; echo "on"; fi
  '';

  toggle-enabled = pkgs.writeShellScriptBin "toggle-enabled" ''
    #!/usr/bin/env bash
    [ -f "''${XDG_STATE_HOME:-$HOME/.local/state}/toggles/''${1:?Usage: toggle-enabled <name>}" ]
  '';

  toggle-get = pkgs.writeShellScriptBin "toggle-get" ''
    #!/usr/bin/env bash
    if [ -f "''${XDG_STATE_HOME:-$HOME/.local/state}/toggles/''${1:?Usage: toggle-get <name>}" ]; then echo "on"; else echo "off"; fi
  '';

in
{
  home.packages = [
    screenshot
    screenrecord
    toggle
    toggle-enabled
    toggle-get
  ];
}
