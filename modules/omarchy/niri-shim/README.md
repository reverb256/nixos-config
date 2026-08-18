# niri-shim/ — Hyprland → Niri adaptation (Phases 2-3)

The Niri re-implementation surface from epic #655. Files here are deltas over
the verbatim upstream shell tree, applied by `pkgs/omarchy.nix` as a patch —
not vendored copies.

## Phase 2 (#657) — shell port to Niri

- **`quickshell-niri.patch`** — rewrites the shell's `Quickshell.Hyprland`
  bindings to the third-party qml-niri `import Niri` plugin. Applied over
  `shell/` in `pkgs/omarchy.nix` (`patches = [ ../modules/omarchy/niri-shim/quickshell-niri.patch ]`).

  Files touched (all in the patch):

  | File | Hyprland surface | Niri replacement |
  |------|------------------|------------------|
  | `plugins/bar/widgets/Workspaces.qml` | `Hyprland.workspaces.values`, `focusedWorkspace`, `hyprctl dispatch` | `Niri.workspaces` model + `Niri.focusWorkspace(index)` |
  | `plugins/bar/widgets/KeyboardLayout.qml` | `hyprctl -j devices` + `switchxkblayout` + `onRawEvent` | `Niri.keyboardLayouts` (names/currentIndex) + `Niri.switchKeyboardLayoutNext()` |
  | `plugins/bar/Bar.qml` | `Hyprland.focusedMonitor` | focused workspace's `output` (connector name) |
  | `plugins/services/idle/Service.qml` | `onRawEvent` `openwindow`/`closewindow` | `onRawEventReceived` + `WindowOpenedOrChanged`/`WindowClosed` |
  | `Ui/PopupCard.qml` | `HyprlandFocusGrab` | `Niri.focusedWindowChanged` (no focus-grab IPC on niri) |
  | `Commons/Style.qml` | `hyprctl getoption` rounding/gaps | removed — niri has no `getoption`; theme defaults |

  The plugin + the quickshell build that carries it live in the overlay as
  `pkgs.qml-niri` and `pkgs.quickshell-niri` (`inputs.qml-niri` in the flake).

## Phase 3 (#658) — command retargeting

Not started here. Re-targeting of ~75 `hyprctl` commands + 25
`omarchy-hyprland-*` commands lives in `docs/reference/omarchy-phase3-hyprctl-niri-map.md`.

## Known gaps to verify at build time (Phase 2)

- `Niri.workspaces` exposes a workspace's `activeWindowId` but no per-workspace
  window count, so Workspaces.qml's `occupied` pill is an approximation.
- PopupCard outside-click dismissal relies on `Niri.focusedWindowChanged`;
  clicking empty desktop (no toplevel) may not close the popup.
- The screensaver window is detected via `app_id`; verify the
  `omarchy-launch-screensaver` surface reports as a toplevel, not a layer.
- niri keyboard layout names are xkb codes (`us`), not full descriptions.
