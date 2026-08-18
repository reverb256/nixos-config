# Omarchy Phase 2 — Quickshell shell on Niri

> Static analysis + upstream verification. Feeds #657. No build-dependent work.

## ⚠️ The #657 assumption is wrong — verify this first

Issue #657 says *"Quickshell ships the Niri plugin natively, so this is a
binding swap."* **Verified false.** The pinned nixpkgs quickshell 0.3.0 store
tree ships these `Quickshell/` QML modules and no others:

```
Bluetooth  DBusMenu  Hyprland  I3  Io  Networking  Services  Wayland
Widgets  _Window  WindowManager  X11
```

There is **no `Quickshell.Niri`**. Niri integration is a third-party plugin:
`imiric/qml-niri` (QML import `Niri`, C++/Qt6, tested against niri v26.04). It
also ships a quickshell-with-plugin build (`qml-niri.packages.<system>.quickshell`).

**So Phase 2 is: add `qml-niri` as a flake input, package the plugin, and port
the QML from `import Quickshell.Hyprland` → `import Niri`.** Not a find-replace —
the APIs differ (see §3).

## 1. The 5 Hyprland-coupled QML files (verified line-level)

| file | what it uses | Niri plugin equivalent |
|------|-------------|------------------------|
| `plugins/bar/Bar.qml` | `Hyprland.focusedMonitor` (bar on focused output) | `Niri` has no focused-monitor concept → use `niri msg --json outputs` + focused workspace, or keep bar per-output via Quickshell `ScreenInfo` |
| `plugins/bar/widgets/Workspaces.qml` | `Hyprland.workspaces.values`, `Hyprland.focusedWorkspace.id` | `Niri.workspaces` model (roles `index`, `id`, `name`, `isFocused`, `isActive`, `isUrgent`) |
| `plugins/bar/widgets/KeyboardLayout.qml` | `import Quickshell.Hyprland` (layout list/switch) | `Niri.keyboardLayouts` (configured + active layout) |
| `plugins/services/idle/Service.qml` | `Hyprland.onRawEvent` (openwindow/closewindow → screensaver detection) | `Niri` has no raw-event signal → watch `windows` model count or `niri msg event-stream` |
| `Ui/PopupCard.qml` | `HyprlandFocusGrab` (outside-click dismissal) | no direct equivalent → re-implement dismissal via `Niri.focusedWindow` polling or a layer-surface grab |

Note: idle detection itself is `IdleMonitor` (Quickshell core, compositor-agnostic) —
only the screensaver window open/close *detection* is Hyprland-coupled.

## 2. `Style.qml` / `Border.qml` coupling

- `Commons/Style.qml` — `hyprctl getoption decoration:rounding` and
  `general:gaps_out` (corner radius + screen-edge gaps). Niri has no such
  options (border-radius is per-window-rule; gaps are layout-level). Replace
  with hardcoded style tokens or `niri msg` where a matching option exists;
  otherwise fall back to the existing defaults (the code already treats
  `hyprctl missing → leave previous value` as valid).
- `Commons/Border.qml` — `[hyprland] active-border` / `active-border-alpha` /
  `active-border-width` theme keys are **carried verbatim** per #657; only the
  *source* of those values (hyprctl → niri) changes.

## 3. API mapping (Hyprland → Niri plugin)

| Hyprland API | Niri plugin (`import Niri`) |
|--------------|-----------------------------|
| `Hyprland.workspaces.values[i].id` | `niri.workspaces` model role `id` / `index` |
| `Hyprland.focusedWorkspace.id` | `niri.workspaces` row with `isFocused` |
| `Hyprland.focusedMonitor` | **none** — derive from focused workspace / output |
| `Hyprland.onRawEvent` | **none** — `niri msg event-stream` (or poll `windows`) |
| `HyprlandFocusGrab` | **none** — re-implement dismissal |
| `hyprctl dispatch focus/workspace/fullscreen/...` | `niri.focusWindow(id)` / `focusWorkspaceById(id)` / `sendRawAction(...)` |
| keyboard layout switch | `niri.keyboardLayouts` (read) + `niri msg action switch-layout` |

## 4. Packaging shape (what Phase 2 must produce)

1. `inputs.qml-niri` flake input (its `inputs.quickshell.follows` a quickshell input).
2. A `pkgs/qml-niri.nix` (or consume `qml-niri.packages.x86_64-linux.default`) installed so `import Niri` resolves via `QML_IMPORT_PATH`.
3. `modules/omarchy/niri-shim/` hosts the 5 ported QML files (or patches) + the `Style.qml` rework.
4. `NIRI_SOCKET` must be set for the plugin to connect (niri exports it in the session env).

## 5. Open questions to resolve at implementation time

- Use `qml-niri`'s `quickshell` package (bundled) vs. nixpkgs `quickshell` + separate plugin — the bundled build pins quickshell to the plugin's expectations; the nixpkgs route keeps quickshell 0.3.0. Decide by whether nixpkgs quickshell 0.3.0's QML API matches what qml-niri was tested against.
- `HyprlandFocusGrab` outside-click dismissal: acceptable UX regression to drop in Phase 2 (defer to a follow-up) vs. re-implement now.
- `focusedMonitor` bar routing: niri's multi-output model means the bar likely becomes a per-output Quickshell layer, not a focused-monitor singleton.
