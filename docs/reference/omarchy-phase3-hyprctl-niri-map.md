# Omarchy Phase 3 — hyprctl → `niri msg` mapping table

> Source: `basecamp/omarchy` @ `7be59e1` vs niri-26.04 (store path
> `niri-26.04/bin/niri msg --help`). Feeds #658. Static inventory — no builds.

This is the complete inventory of Hyprland coupling in Omarchy's `bin/`, with
the Niri replacement for each. Niri's `niri msg` is the drop-in IPC for
`hyprctl`; where no direct equivalent exists, the table names the Niri-native
tool or marks the command as a clear-error (per #658: "no silent no-op").

## 1. `hyprctl` subcommand frequency (53 scripts)

| hyprctl call | count | Niri replacement |
|--------------|-------|------------------|
| `hyprctl dispatch …` | 40 | `niri msg action …` |
| `hyprctl monitors -j` | 24 | `niri msg --json outputs` |
| `hyprctl reload` | 13 | `niri msg action load-config-file` |
| `hyprctl clients -j` | 13 | `niri msg --json windows` |
| `hyprctl eval …` (Lua) | 10 | **no Lua** — re-implement in shell/QML |
| `hyprctl activewindow -j` | 6 | `niri msg --json focused-window` |
| `hyprctl binds` | 5 | `niri` has no bind-query — parse config KDL |
| `hyprctl keyword …` | 4 | `niri msg output <o> …` (per-output) |
| `hyprctl devices -j` | 3 | `libinput list-devices` / `niri` has none |
| `hyprctl activeworkspace -j` | 2 | `niri msg --json workspaces` (filter focused) |
| `hyprctl hyprsunset …` | 2 | `wl-gammactl` / `gammastep` |
| `hyprctl cursorpos` | 2 | `niri` has none (Wayland cursor is compositor-private) |
| `hyprctl switchxkblayout …` | 1 | `niri msg action switch-layout` |
| `hyprctl print` | 1 | `niri msg version` (or drop) |
| `hyprctl getoption …` | 1 | `niri msg output` has no option query — parse config |
| `hyprctl binary …` | 1 | identity check — drop (always niri) |

## 2. `hyprctl dispatch` → `niri msg action` (the real work)

| hyprctl dispatch | niri msg action |
|------------------|-----------------|
| `focuswindow address:$addr` | `focus-window --id $id` (map addr→id via `windows` JSON) |
| `focusmonitor $name` | `focus-monitor` (niri output names differ) |
| `workspace $n` | `focus-workspace $n` |
| `fullscreenstate 0 0` | `fullscreen-window` (or `toggle-windowed-fullscreen`) |
| `setprop … opaque toggle` | `toggle-window-rule-opacity` |
| `exec …` | `spawn` / `spawn-sh` |
| `sendshortcut …` | **no equivalent** — clear-error (niri lacks inject) |

## 3. `hyprctl eval` Lua blocks (10 scripts) — no Lua on Niri

These call Hyprland's Lua API (`hl.dsp.dpms`, `hl.monitor`, `hl.config`,
`hl.device`, `hl.dsp.window.close`, `hl.dsp.window.fullscreen_state`,
`hl.workspace_rule`, `hl.dsp.exec_cmd`). Each becomes either a `niri msg`
call or a shell re-implementation:

| hl.* API | Niri replacement |
|----------|------------------|
| `hl.dsp.dpms({ action = … })` | `niri msg output <o> off` / `on` (or `action power-off-monitors`) |
| `hl.monitor({ … })` | `niri msg output <o> mode/scale/position` |
| `hl.config({ cursor = … })` | **drop** (niri has no hide-cursor toggle) — mark no-op/clear-error |
| `hl.device({ enabled = … })` | **no per-device toggle** — use `libinput` or clear-error |
| `hl.dsp.window.close/fullscreen_state/set_prop` | `close-window` / `fullscreen-window` / `toggle-window-rule-opacity` |
| `hl.workspace_rule({ layout = … })` | `niri` has no runtime layout rule — clear-error |
| `hl.dsp.exec_cmd` | `spawn` |

## 4. `omarchy-hyprland-*` (24 commands) — the named surface

| command | Niri approach |
|---------|---------------|
| `monitor-*` (clamshell, external-active, focused, focused-apple, internal, internal-mirror, laptop, modeless, scaling, watch) | `niri msg --json outputs` + `niri msg output <o> mode/scale/position/off/on`; `internal`/`external` detection becomes a `libinput`/EDID probe |
| `session-locked` | `niri` has no session-lock IPC — check `loginctl show-session` or `swaylock` pidfile |
| `reload-guard` | re-target `hyprctl reload` → `niri msg action load-config-file` |
| `toggle`, `toggle-disabled`, `toggle-enabled` | re-point at the new `niri msg` commands |
| `window-close-all` | `niri msg --json windows` + `close-window` per id |
| `window-pop` | `focus-window-previous` (niri has no float-pop; Niri is scroll-tiling) |
| `window-gaps-toggle`, `window-single-square-aspect-toggle`, `window-width`, `window-tiled-fullscreen-toggle`, `window-transparency-toggle` | `set-window-width` / `fullscreen-window` / `toggle-window-rule-opacity`; gaps/aspect are **niri-absent** → clear-error |
| `workspace-layout-toggle` | `niri` has no tiled-layout toggle (always columnar) → clear-error |
| `focus-app` | `focus-window --id` via `windows` JSON match |

## 5. hyprlock / hyprpicker / hyprsunset (7 scripts)

| tool | Niri-native replacement |
|------|-------------------------|
| `hyprlock` (lock) | `swaylock` (niri's own config default) or `niri` session-lock via a helper |
| `hyprpicker -r -z` (region color-pick + freeze) | `niri msg pick-color` (native) — freeze is Wayland-private, so the `--keep-freeze` capture flow needs rework (`grim` without freeze) |
| `hyprsunset` (night light) | `wl-gammactl` (per-output gamma) — niri has no built-in night light |

## 6. Commands that must become clear-errors (no Niri equivalent)

`omarchy-hyprland-window-gaps-toggle`, `-single-square-aspect-toggle`,
`-workspace-layout-toggle`, `sendshortcut`, cursor hide, per-device toggle,
runtime workspace-layout rule, `hyprctl cursorpos`. Each prints a non-zero
error + pointer to the niri-native alternative — never a silent no-op (per #658).
