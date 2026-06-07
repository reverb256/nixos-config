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

  # Detect running compositor: "niri" (only option now)
  compositorDetect = ''
    echo "niri"
  '';

  screenshot = pkgs.writeShellScriptBin "screenshot" ''
    #!/usr/bin/env bash
    set -euo pipefail

    MODE="''${1:-region}"
    SCREENSHOT_DIR="''${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}"
    mkdir -p "$SCREENSHOT_DIR"

    COMPOSITOR=$(eval "$compositorDetect")

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    FILENAME="$SCREENSHOT_DIR/screenshot_$TIMESTAMP.png"

    case "$COMPOSITOR" in
      niri)
        if [ "$MODE" = "region" ]; then
          grim -g "$(slurp)" "$FILENAME"
        else
          grim "$FILENAME"
        fi
        ;;
    esac

    wl-copy < "$FILENAME"
    notify-send "Screenshot saved" "$FILENAME"
  '';

  screenrecord = pkgs.writeShellScriptBin "screenrecord" ''
    #!/usr/bin/env bash
    set -euo pipefail

    MODE="''${1:-region}"
    SCREENSHOT_DIR="''${SCREENSHOT_DIR:-$HOME/Pictures/Recordings}"
    mkdir -p "$SCREENSHOT_DIR"

    COMPOSITOR=$(eval "$compositorDetect")

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    FILENAME="$SCREENSHOT_DIR/recording_$TIMESTAMP.mp4"

    case "$COMPOSITOR" in
      niri)
        if [ "$MODE" = "region" ]; then
          wf-recorder -g "$(slurp)" -f "$FILENAME"
        else
          wf-recorder -f "$FILENAME"
        fi
        ;;
    esac
  '';

  colorPicker = pkgs.writeShellScriptBin "color-picker" ''
    #!/usr/bin/env bash
    set -euo pipefail

    COMPOSITOR=$(eval "$compositorDetect")

    case "$COMPOSITOR" in
      niri)
        COLOR=$(niri color-picker)
        ;;
    esac

    if [ -n "$COLOR" ]; then
      wl-copy "$COLOR"
      notify-send "Color picked" "$COLOR"
    fi
  '';
in {
  config = lib.mkIf config.desktop.wayland-tools.enable {
    home.packages = [
      screenshot
      screenrecord
      colorPicker

      pkgs.slurp
      pkgs.grim
      pkgs.wl-clipboard
      pkgs.libnotify
      pkgs.niri
    ];

    wayland.windowManager.niri.config = {
      binds = {
        "Mod+Shift+S".action.spawn = ["screenshot" "region"];
        "Mod+Print".action.spawn = ["screenshot" "screen"];
        "Mod+Shift+R".action.spawn = ["screenrecord" "region"];
        "Mod+C".action.spawn = ["color-picker"];
      };
    };
  };
}
