# Plan: Reverb-OS adopts Omarchy on NixOS + HDR Niri

> Supersedes #580 (iNiR). Epic: #655. Phases: #656–#660.

This is the canonical design doc for the Omarchy UX port. The issue bodies
(#655–#660) are the task checklists; this file holds the verified architecture
facts and the decisions that shape every phase.

## Goal

Reverb-OS runs the full `basecamp/omarchy` UX — themes, `omarchy` CLI router,
Quickshell shell, plugins, dots — on NixOS with HDR Niri, at 100%
feature/theme/plugin parity. Upstream is consumed as a pinned flake input; all
adaptation lives in `modules/omarchy/`. **iNiR is not used** (retired 2026-08-16,
commit edb9d9a; PR #620 work superseded).

## Verified upstream facts (source: `~/Projects/omarchy` @ `7be59e1`, origin/quattro)

- **Install root** is `/usr/share/omarchy`, referenced as `$OMARCHY_PATH` by
  ~36 `default/`, 20 `install/`, 18 `bin/`, 9 `shell/`, 7 `config/`, 6
  `themes/`, 2 `applications/`, 2 `migrations/` references plus `logo.txt` /
  `icon.txt` branding assets. The router resolves sibling commands via
  `OMARCHY_BIN_DIR=$(dirname "$BASH_SOURCE[0]")`.
- **Router**: `bin/omarchy` scans `$OMARCHY_BIN_DIR/omarchy-*` for `# omarchy:*`
  metadata (group/name/summary/args/examples/aliases), builds a route table
  (`GROUP_DESCRIPTIONS`), and dispatches. ~425 `omarchy-*` commands.
- **Two Arch packages** in upstream (`omarchy` + `omarchy-settings`) map to one
  Nix package here: runtime `bin/` + `themes/` + `shell/` + `install/` +
  `migrations/` + `config/` + `default/` + `applications/` + `manual/` are all
  data files; no compiled binary, no daemon, no pacman runtime.
- **Themes**: 22 themes, each `themes/<name>/colors.toml` (+ `neovim.lua`,
  `vscode.json`, `icons.theme`, backgrounds). `omarchy-theme-list`/`-set`/
  `-current` resolve `$OMARCHY_PATH/themes/` and write user state to
  `~/.local/state/omarchy/current/`.
- **Shell**: `shell/` is a Quickshell QML tree. Only 5 files import
  `Quickshell.Hyprland`: `plugins/bar/widgets/Workspaces.qml`,
  `plugins/bar/widgets/KeyboardLayout.qml`, `plugins/bar/Bar.qml`,
  `plugins/services/idle/Service.qml`, `Ui/PopupCard.qml`. Everything else is
  compositor-agnostic (menu, clipboard, emojis, osd, polkit, reminders,
  background, agents, dev-gallery, image-picker).
- **Hyprland coupling in `bin/`**: 53 scripts touch `hyprctl`, 24 are
  `omarchy-hyprland-*`, 7 touch `hyprlock`/`hyprpicker`/`hyprsunset`. Full
  mapping in `docs/reference/omarchy-phase3-hyprctl-niri-map.md`.
- **`dots`**: upstream is a *plan only* (`plans/dots.md`, rev 3). No
  `bin/omarchy-dots` exists. Phase 1 ships the plan + existing
  `omarchy-reinstall-configs` / `omarchy-refresh-config`; the dots CLI lands
  when upstream ships it or we build it in Phase 4.
- **herdr**: Omarchy's bar/menu route through `herdr` (not rofi/waybar). The
  cluster already packages `herdr` (`packages/herdr.nix`) — Phase 2 reuses it.

## Architecture

```
inputs.omarchy = { url = "git+https://github.com/basecamp/omarchy?rev=…"; flake = false; }
                              │
                              ▼
pkgs/omarchy.nix  ──►  $out/share/omarchy/{bin,themes,shell,config,default,
                                            applications,manual,install,migrations}
                       + $out/bin/omarchy*  (symlink farm → 425 commands on PATH)
                              │
                              ▼
modules/omarchy/default.nix  ──►  programs.omarchy.enable
                                  OMARCHY_PATH = $out/share/omarchy (session-wide)
```

- **No fork, no vendored copy, no divergence to rebase.** Upstream sync = bump
  the `omarchy` rev + `nix flake update omarchy`.
- **Adaptation layers** under `modules/omarchy/`:
  - `niri-shim/` — Phases 2-3: `Quickshell.Hyprland` → Niri QML swap +
    `hyprctl` → `niri msg` re-targeting.
  - `pkg-shim/` — Phase 4: nix-backed `omarchy-pkg-add/drop`, `omarchy-update`.

## Runtime vs declarative boundary (decision 2026-08-18)

The AGENTS.md "declarative only" rule governs **NixOS system state** — services,
networking, hardware, secrets, the cluster's source of truth. It does **not**
bind Omarchy's user-session UX layer, which is definitionally runtime state.
The port keeps the two separate:

- **Declarative (unchanged):** Omarchy's *installation* — the `omarchy` flake
  input, `pkgs/omarchy.nix` source tree + shell patch, the `bin/omarchy*`
  symlink farm, `OMARCHY_PATH`, the shell wired into niri, and any system
  services Omarchy depends on. This ships via `just deploy`.
- **Imperative (allowed, Omarchy-native):** the *runtime UX* — `omarchy theme
  set` (writes `~/.config/omarchy/` + `~/.local/state/omarchy/`), shell.json
  editing, `omarchy toggle` flag files, keyboard/workspace switching, hardware
  toggles (`nmcli` / `rfkill` / `bluetoothctl`), `omarchy pkg add/drop`
  (→ `nix profile`), `omarchy update` (→ `nix profile upgrade` + garbage
  collect, with the system step reported as `just deploy`, not run implicitly).

Consequence for Phases 3-4: runtime commands are **re-targeted to work**, not
clear-errored. Only commands with no safe NixOS equivalent (AUR, pacman
keyring) clear-error with a pointer to the Nix equivalent. The "no silent
no-op" rule stays: every command either acts or errors with a pointer.

## ⚠️ Correction to #657's assumption (verified 2026-08-18)

Issue #657 states "Quickshell ships the Niri plugin natively." **That is wrong.**
Verified against the pinned nixpkgs quickshell 0.3.0 in the store: its
`Quickshell/` QML tree ships `Hyprland`, `I3`, `X11`, `WindowManager`, `Wayland`,
`Io`, `Widgets` — **no `Niri` module**. The Niri integration is a third-party
plugin (`imiric/qml-niri`, QML import `Niri`, tested against niri v26.04).

Consequences for Phase 2 (#657):

- The QML import target is `import Niri`, **not** `import Quickshell.Niri`.
- The plugin must be packaged separately and added to `QML_IMPORT_PATH` (or a
  quickshell-with-plugin build used). It is a new flake input, not a
  `Quickshell.Niri` binding swap.
- Its API is a single `Niri` type with `windows` / `workspaces` models and
  `focusWindow(id)` / `focusWorkspaceById(id)` methods — semantically close to
  `Hyprland.workspaces.values` / `focusedWorkspace`, but a rewrite, not a
  find-replace. `Hyprland.onRawEvent`, `HyprlandFocusGrab` (outside-click), and
  `Hyprland.focusedMonitor` have no direct `Niri`-plugin equivalent.

## Compatibility tiers

| Tier | Surface | Treatment |
|------|---------|-----------|
| 1 | 22 themes, plugin registry/manifest, Hyprland-free plugins, `omarchy` router, `dots` plan, `applications/*.desktop`, manual | verbatim port (#656) |
| 2 | 5 QML files (`Quickshell.Hyprland` → `Niri` third-party plugin) + `Style.qml` hyprctl rounding/gaps, ~53 `hyprctl` scripts + 24 `omarchy-hyprland-*`, hyprlock/hyprpicker/hyprsunset | Niri re-implementation (#657, #658) |
| 3 | `omarchy-pkg-add/drop`, `omarchy-update`, AUR helpers | Nix-backed name parity (#659) |

## Phases (one PR each)

- [x] #656 — Foundation: flake input + Tier 1 verbatim + drop iNiR (PR #706)
- [ ] #657 — Shell port: Omarchy shell on `Quickshell.Niri`
- [ ] #658 — Command re-target: hyprctl → `niri msg`, lock/picker/sunset
- [ ] #659 — Package parity: nix-backed pkg/update commands
- [ ] #660 — HDR validation: HDR + themes + plugins on niri-hdr fork, acceptance on Zephyr

## Non-goals

- No Arch/pacman/AUR runtime, no Hyprland runtime.
- No `Quickshell.Hyprland` shim (Niri-native only, not dual-compositor).
- iNiR and PR #620's iNiR work are retired.
- No changes to upstream `basecamp/omarchy`.

## Niri IPC baseline (verified against niri-26.04 in the store)

`niri msg` subcommands: `outputs`, `workspaces`, `windows`, `layers`,
`keyboard-layouts`, `focused-output`, `focused-window`, `pick-window`,
`pick-color`, `action`, `output`, `event-stream`, `version`, `overview-state`,
`casts`.

`niri msg action` exposes the full binding vocabulary (`focus-*`, `move-*`,
`switch-*`, `fullscreen-window`, `close-window`, `power-off-monitors`,
`spawn`/`spawn-sh`, `screenshot-*`, `toggle-*`). The hyprctl→niri mapping table
lives in `docs/reference/omarchy-phase3-hyprctl-niri-map.md`.

## Phase prep docs

- `docs/reference/omarchy-phase2-quickshell-niri.md` — the Quickshell.Niri
  shell port (corrects #657's "native Niri plugin" assumption).
- `docs/reference/omarchy-phase3-hyprctl-niri-map.md` — the hyprctl→niri map.
- `docs/reference/omarchy-phase4-pkg-parity.md` — nix-backed package commands.
