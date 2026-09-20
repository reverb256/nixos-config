# niri-shim/ — Hyprland → Niri adaptation (Phases 2-3)

Placeholder for the Niri re-implementation surface from epic #655:

- **Phase 2 (#657)** — swap the 5 `Quickshell.Hyprland` QML imports to
  `Quickshell.Niri`, plus `Style.qml` rounding/gaps via `niri msg`.
- **Phase 3 (#658)** — re-target ~75 `hyprctl` commands + 25
  `omarchy-hyprland-*` commands to `niri msg`, and replace
  hyprlock/hyprpicker/hyprsunset with Niri-native equivalents.

Nothing lives here yet. Files land under this directory when Phase 2 starts.
