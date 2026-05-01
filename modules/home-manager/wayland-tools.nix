{
  pkgs,
  lib,
  config,
  ...
}: let
  dagEntryAfter =
    if config.lib ? hm && config.lib.hm ? dag
    then config.lib.hm.dag.entryAfter
    else (_names: script: script);
  brightness-all = pkgs.writeShellScriptBin "brightness-all" ''
    SAMSUNG_OUTPUT="HDMI-A-2"
    SDR_MIN=0.1
    SDR_MAX=1.0
    SDR_STEP=0.05

    get_current() {
      echo "''${NIRI_SAMSUNG_BRIGHTNESS:-1.0}"
    }

    case "$1" in
      up)
        noctalia-shell ipc call brightness increase 2>/dev/null || true
        current=$(get_current)
        new=$(echo "$current + $SDR_STEP" | bc 2>/dev/null)
        [ -z "$new" ] && new="1.0"
        if [ "$(echo "$new > $SDR_MAX" | bc)" = "1" ]; then new="$SDR_MAX"; fi
        export NIRI_SAMSUNG_BRIGHTNESS="$new"
        niri msg output "$SAMSUNG_OUTPUT" sdr-brightness "$new" 2>/dev/null || true
        ;;
      down)
        noctalia-shell ipc call brightness decrease 2>/dev/null || true
        current=$(get_current)
        new=$(echo "$current - $SDR_STEP" | bc 2>/dev/null)
        [ -z "$new" ] && new="0.95"
        if [ "$(echo "$new < $SDR_MIN" | bc)" = "1" ]; then new="$SDR_MIN"; fi
        export NIRI_SAMSUNG_BRIGHTNESS="$new"
        niri msg output "$SAMSUNG_OUTPUT" sdr-brightness "$new" 2>/dev/null || true
        ;;
    esac
  '';

  scratchpad-toggle = pkgs.writeShellScriptBin "scratchpad-toggle" ''
    set -euo pipefail

    SCRATCH_WS="scratch"
    STATE_FILE="''${XDG_RUNTIME_DIR:-/tmp}/niri-scratchpad-prev-ws"

    current_ws=$(niri msg workspaces 2>/dev/null | awk '/\*/ {print $2}' | head -1)
    if [ -z "$current_ws" ]; then
      current_ws=$(niri msg focused-output 2>/dev/null | awk '/Active workspace:/ {print $NF}')
    fi

    if [ "$current_ws" = "$SCRATCH_WS" ]; then
      prev=$(cat "$STATE_FILE" 2>/dev/null || echo "1")
      niri msg action focus-workspace "$prev" 2>/dev/null || true
    else
      scratch_has_windows=false
      json_out=$(niri msg windows --json 2>/dev/null) || true
      if [ -n "$json_out" ] && echo "$json_out" | ${lib.getExe pkgs.jq} -e '.[0].id' >/dev/null 2>&1; then
        count=$(echo "$json_out" | ${lib.getExe pkgs.jq} "[.[] | select(.workspace == \"$SCRATCH_WS\" or (.workspace // 0) == 99)] | length")
        [ "''${count:-0}" -gt 0 ] && scratch_has_windows=true
      fi

      echo "$current_ws" > "$STATE_FILE"

      if $scratch_has_windows; then
        niri msg action focus-workspace "$SCRATCH_WS" 2>/dev/null || true
        sleep 0.1
        niri msg action move-column-to-workspace "$current_ws" 2>/dev/null || true
        niri msg action focus-workspace "$current_ws" 2>/dev/null || true
      else
        niri msg action move-column-to-workspace "$SCRATCH_WS" 2>/dev/null || true
      fi
    fi
  '';

  launch-or-focus = pkgs.writeShellScriptBin "launch-or-focus" ''
    set -euo pipefail

    if [ ''$# -lt 1 ]; then
      echo "Usage: launch-or-focus <window-pattern> [launch-command] [args...]" >&2
      echo "  If a window matching the pattern exists, focus it." >&2
      echo "  Otherwise, launch the command (defaults to the pattern)." >&2
      exit 1
    fi

    PATTERN="$1"
    shift || true
    LAUNCH_CMD="''${@:-$PATTERN}"

    find_window_id() {
      local pat_lower
      pat_lower=$(echo "$PATTERN" | tr '[:upper:]' '[:lower:]')

      local json_out
      json_out=$(niri msg windows --json 2>/dev/null) || true
      if [ -n "$json_out" ] && echo "$json_out" | ${lib.getExe pkgs.jq} -e '.[0].id' >/dev/null 2>&1; then
        echo "$json_out" | ${lib.getExe pkgs.jq} -r ".[] | select(
          (.title // \"\") | test(\"$PATTERN\"; \"i\")
          or (.\"app-id\" // \"\") | test(\"$PATTERN\"; \"i\")
        ) | .id" | head -1
        return
      fi

      niri msg windows 2>/dev/null | awk -v pat="$pat_lower" '
        /^Window ID/ { current_id = \$3; gsub(/:/, "", current_id); title=""; appid="" }
        /^\s+Title:/ {
          val = \$0; sub(/^\s+Title:\s*"/, "", val); sub(/"$/, "", val); title = val
        }
        /^\s+App ID:/ {
          val = \$0; sub(/^\s+App ID:\s*"/, "", val); sub(/"$/, "", val); appid = val
          if (tolower(title) ~ pat || tolower(appid) ~ pat) {
            print current_id; exit
          }
        }
      '
    }

    WINDOW_ID=$(find_window_id) || true

    if [ -n "$WINDOW_ID" ]; then
      niri msg action focus-window --id "$WINDOW_ID" 2>/dev/null || true
    else
      exec $LAUNCH_CMD
    fi
  '';
in {
  home.packages = with pkgs; [
    wl-clipboard
    grim
    slurp
    ddcutil
    brightness-all
    launch-or-focus
    satty
    scratchpad-toggle
  ];

  home.activation.noctalia-ddc = dagEntryAfter ["writeBoundary"] ''
        $VERBOSE_ECHO "Ensuring noctalia DDC support is enabled"
        NOCTALIA_CFG="$HOME/.config/noctalia/settings.json"
        if [ -f "$NOCTALIA_CFG" ]; then
          ${pkgs.python3}/bin/python3 -c "
    import json, sys
    path = '$NOCTALIA_CFG'
    with open(path) as f:
        d = json.load(f)
    changed = False
    if 'brightness' not in d:
        d['brightness'] = {}
        changed = True
    if not d['brightness'].get('enableDdcSupport', False):
        d['brightness']['enableDdcSupport'] = True
        changed = True
    if changed:
        with open(path, 'w') as f:
            json.dump(d, f, indent=2)
        print('Updated noctalia settings: DDC support enabled')
    else:
        print('DDC support already enabled')
    "
        else
          $DRY_RUN_CMD ${pkgs.python3}/bin/python3 -c "
    import json
    path = '$NOCTALIA_CFG'
    d = {'brightness': {'enableDdcSupport': True, 'brightnessStep': 5, 'enforceMinimum': True, 'backlightDeviceMappings': []}}
    with open(path, 'w') as f:
        json.dump(d, f, indent=2)
    print('Created noctalia settings with DDC support enabled')
    "
        fi
  '';

  home.activation.noctalia-version-check = dagEntryAfter ["writeBoundary"] ''
    RUNNING=$(pgrep -a quickshell 2>/dev/null | grep noctalia-shell || true)
    if [ -n "''${RUNNING:-}" ]; then
      RUNNING_PATH=$(echo "$RUNNING" | grep -oP '/nix/store/[^/]+-noctalia-shell-[^/]*/' || true)
      CURRENT_PATH=$(readlink -f "$(which noctalia-shell 2>/dev/null)" 2>/dev/null | grep -oP '/nix/store/[^/]+-noctalia-shell-[^/]*/' || true)
      if [ -n "''${RUNNING_PATH:-}" ] && [ -n "''${CURRENT_PATH:-}" ] && [ "$RUNNING_PATH" != "$CURRENT_PATH" ]; then
        echo "⚠ noctalia-shell needs restart: $RUNNING_PATH → $CURRENT_PATH"
        echo "  Run: pkill -f quickshell && uwsm app -- noctalia-shell"
      fi
    fi
    true
  '';
}
