# Wayland Tools (Home Manager)
# Clipboard and screenshot utilities for Wayland compositors
{
  pkgs,
  lib,
  config,
  ...
}:
let
  # HM activation DAG helper — guard against missing lib.hm
  dagEntryAfter =
    if config.lib ? hm && config.lib.hm ? dag then
      config.lib.hm.dag.entryAfter
    else
      (_names: script: script);
  # Unified brightness script: DDC (noctalia) + SDR brightness (niri NV_PLANE_DEGAMMA_MULTIPLIER)
  # Uses niri's hardware-accelerated SDR brightness for the Samsung HDMI TV
  # instead of software gamma ramp (wl-gammarelay)
  brightness-all = pkgs.writeShellScriptBin "brightness-all" ''
    SAMSUNG_OUTPUT="HDMI-A-2"
    SDR_MIN=0.1
    SDR_MAX=1.0
    SDR_STEP=0.05

    get_current() {
      # Default to 1.0 if we can't read it
      echo "''${NIRI_SAMSUNG_BRIGHTNESS:-1.0}"
    }

    case "$1" in
      up)
        noctalia-shell ipc call brightness increase 2>/dev/null || true
        current=$(get_current)
        new=$(echo "$current + $SDR_STEP" | bc 2>/dev/null)
        [ -z "$new" ] && new="1.0"
        # Clamp
        if [ "$(echo "$new > $SDR_MAX" | bc)" = "1" ]; then new="$SDR_MAX"; fi
        export NIRI_SAMSUNG_BRIGHTNESS="$new"
        niri msg output "$SAMSUNG_OUTPUT" sdr-brightness "$new" 2>/dev/null || true
        ;;
      down)
        noctalia-shell ipc call brightness decrease 2>/dev/null || true
        current=$(get_current)
        new=$(echo "$current - $SDR_STEP" | bc 2>/dev/null)
        [ -z "$new" ] && new="0.95"
        # Clamp
        if [ "$(echo "$new < $SDR_MIN" | bc)" = "1" ]; then new="$SDR_MIN"; fi
        export NIRI_SAMSUNG_BRIGHTNESS="$new"
        niri msg output "$SAMSUNG_OUTPUT" sdr-brightness "$new" 2>/dev/null || true
        ;;
    esac
  '';
in
{
  home.packages = with pkgs; [
    wl-clipboard # Wayland clipboard utilities (wl-copy, wl-paste)
    grim # Screenshot utility for Wayland
    slurp # Region selection for Wayland
    ddcutil # Monitor brightness control via DDC/CI (I2C)
    brightness-all # Unified brightness (DDC + niri SDR)
    # bitwarden-desktop  # TEMP: Disabled - Electron 39.8.2 patch failure (2026-03-16)
  ];

  # wl-gammarelay-rs REMOVED — replaced by niri SDR brightness (NV_PLANE_DEGAMMA_MULTIPLIER)
  # Samsung HDMI brightness now uses hardware-accelerated DRM plane property
  # No software gamma ramp needed

  # Ensure noctalia-shell DDC brightness support is enabled
  # Merges into existing user settings without overwriting other config
  home.activation.noctalia-ddc = dagEntryAfter [ "writeBoundary" ] ''
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
}
