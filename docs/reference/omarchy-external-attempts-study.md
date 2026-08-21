# Omarchy → Niri/Nix: Study of External Attempts

> Epic #655. Companion to `omarchy-phase3-hyprctl-niri-map.md` and
> `omarchy-phase2-quickshell-niri.md`. Surveyed 2026-08-20.

Reviewed every public repo attempting Omarchy on Niri or Nix. None are
maintained against current upstream, none are Nix + Niri, and none port the
Quickshell shell — but three contain durable, tested artifacts worth
adopting (a keybinding map, an IPC translation cookbook, and a module
options design).

## Surveyed repos (with real age — "updated" includes stars, use "pushed")

| Repo | Created | Last code push | Stars | Approach |
|------|---------|---------------|-------|----------|
| [okimarchy](https://github.com/cristian-fleischer/okimarchy) | 2025-09 | **2025-11-13** (~9 mo stale) | 119 | Omarchy fork (3.1.7) with native Niri config system + runtime WM switch |
| [omarchy-nix](https://github.com/henrysipp/omarchy-nix) | 2025-06 | **2025-11-13** (~9 mo stale) | 740 | NixOS flake reimplementation of Omarchy (**Hyprland-only**) |
| [jeremy/omarchy-niri](https://github.com/jeremy/omarchy-niri) | 2026-02 | **2026-03-15** (~5 mo stale) | 0 | PATH-shadow wrapper overlay translating `hyprctl` → `niri msg` |
| [dustinromey/dotfiles](https://github.com/dustinromey/dotfiles) | 2025-11 | 2025-12-11 | 0 | "Omarchy-Niri remix" dotfiles (low signal) |
| [awesome-omarchy](https://github.com/aorumbayev/awesome-omarchy) | 2025-08 | 2026-07-22 | 423 | Community index (how the above were found) |

Upstream `basecamp/omarchy` for reference: created 2025-06, **pushed daily**,
27k stars. Every adaptation above is based on Omarchy ≤ 3.1.7 (Nov 2025);
the shell QML, router, and theme schema have moved well past that. **Their
code is reference material, not mergeable code.**

Notable gap: no public repo combines Nix + Niri + Omarchy, and **no one
ports the Quickshell shell QML** (our Phase 2 qml-niri swap is novel).

## 1. okimarchy — native Niri fork (adopt: keybinding map, theme pattern, config-gen)

### Tested Hyprland→Niri keybinding map (`config/niri/bindings.kdl`)

The single most valuable artifact — a working translation of Omarchy's
Hyprland binds to Niri. Highlights (full file in the repo):

| Omarchy/Hyprland | Niri |
|---|---|
| `Mod+Space` / `Mod+Alt+Space` | `spawn omarchy-launch-walker` / `spawn omarchy-menu` (shell apps unchanged) |
| `Mod+←/→/↑/↓` focus | `focus-column-left/right`, `focus-window-up/down` |
| `Mod+1..9` workspace | `focus-workspace N` |
| `Mod+Shift+1..9` move | `move-column-to-workspace N` |
| `Mod+Tab` / `Mod+Shift+Tab` | `focus-workspace-down` / `focus-workspace-up` |
| `Alt+Tab` (no niri equivalent) | `focus-window-down` / `focus-window-up` |
| `Mod+W` close / `Mod+Shift+Q` quit | `close-window` / `quit` |
| `Mod+T` / `Mod+F` / `Mod+Ctrl+F` / `Mod+R` | `toggle-window-floating` / `fullscreen-window` / `maximize-column` / `switch-preset-column-width` |
| `Mod+Minus/Equal` resize | `set-column-width "-10%"/"+10%"` |
| `Mod+Shift+Minus/Equal` | `set-window-height "-10%"/"+10%"` |
| `Mod+WheelScrollDown/Up` | `focus-workspace-down/up` (cooldown-ms=150) |
| `Mod+BracketLeft/Right` (niri-only) | `consume-or-expel-window-left/right` |
| Media/brightness OSD | `swayosd-client` (replaces omarchy OSD) |
| Color pick (`Print`) | still `hyprpicker` on niri (pkill-hack) — niri lacks an equivalent |

Also notable: `Mod+Shift+P { power-off-monitors; }`, `XF86PowerOff →
omarchy-menu system`, DND via `makoctl mode`.

### Theme integration — per-theme `niri.kdl`, appended last

Each of the 12 themes ships `themes/<name>/niri.kdl` (layout gaps 16,
`preset-column-widths`, focus-ring + border colors, shadow, struts). The
config generator appends the **active theme's niri.kdl last** so theme
colors win. → For us: the Stylix-generated niri theme fragment must be the
final block of the declarative `config.kdl`.

### Runtime config generator (`omarchy-niri-config-gen`)

Concatenates modular KDL sources (`input/monitors/looknfeel/autostart/
bindings/windows/workspaces/envs.kdl` + theme) into `config.kdl`, then
gates on `niri validate`; atomic write (temp + mv) with a "DO NOT EDIT"
warning header. → In Nix this is strictly better done **at build time**:
we generate `config.kdl` declaratively from the module, no runtime tool.

### WM detection / switching

- Session detection: `${HYPRLAND_INSTANCE_SIGNATURE:+}` vs `${NIRI_SOCKET:+}`
- Per-WM package lists: `install/omarchy-hyprland.packages` vs
  `omarchy-niri.packages`
- Creates `/usr/share/wayland-sessions/niri-uwsm.desktop`
  (`Exec=uwsm start -- niri --session`) — **the same uwsm pattern our
  zephyr autologin already uses**; our fork is already aligned.
- `okimarchy-wm-switch` = install pkgs → regen config → swap SDDM autologin
  session → reboot.

### Caveats (why we still go further)

- Runs **waybar on niri** (`omarchy-toggle-waybar`) — the Quickshell bar
  was not ported; our qml-niri shell swap is a superset.
- No QML changes anywhere; Hyprland-coupled widgets are simply absent.
- Stale base (3.1.7) — the KDL map needs re-validation against current
  omarchy's bindings, but the translation *principles* hold.

## 2. jeremy/omarchy-niri — PATH-shadow overlay (adopt: IPC cookbook, wrapper pattern)

### The hyprctl → niri msg cookbook (its AGENTS.md — keep this verbatim)

| Hyprland IPC | Niri IPC | JSON field mapping |
|---|---|---|
| `hyprctl clients -j` | `niri msg -j windows` | `.[].address` → `.[].id` |
| `hyprctl activewindow -j` | `niri msg -j focused-window` | `.pid/.class` → `.pid/.app_id` |
| `hyprctl monitors -j` | `niri msg -j outputs` / `focused-output` | `.name/.scale/.width/.height` → `.name/.scale/.logical.width/.logical.height` |
| `hyprctl dispatch focuswindow address:X` | `niri msg action focus-window --id X` | |
| `hyprctl dispatch closewindow address:X` | `niri msg action close-window --id X` | |
| `hyprctl dispatch workspace N` | `niri msg action focus-workspace N` | |
| `hyprctl dispatch dpms off/on` | `niri msg action power-off-monitors` / `power-on-monitors` | |
| `hyprctl reload` | none (restart swaybg/waybar) | |
| `hyprctl keyword` | none (niri config is static) | |
| hypridle / hyprlock / hyprsunset | swayidle / swaylock-effects / wlsunset | |
| hyprpicker | grim + slurp + imagemagick | |
| hyprpaper | swaybg | |

### The wrapper pattern

`bin/omarchy-*` wrappers shadow the originals via PATH order:
1. `source lib.sh` → `is_niri` guard (`$OMARCHY_WM=niri`)
2. Not niri → `exec ~/.local/share/omarchy/bin/<orig> "$@"` (fall through)
3. Niri → reimplement with `niri msg` + `jq`

Example: `omarchy-hyprland-window-close-all` = `niri msg -j windows | jq -r
'.[].id'` → close each → `focus-workspace 1`. This is exactly the design
doc's additive `bin-niri/` layer; the pattern is proven.

### Drift detection (`check-upgrade.sh`)

Scans omarchy's `bin/` for hyprctl-family tool usage (`hyprctl`, `hypridle`,
`hyprlock`, `hyprsunset`, `hyprpicker`, `hyprpaper`) and reports scripts
lacking wrappers after every upstream sync. → **This is the CI gate our
downstream fork needs** (design doc: "downstream CI gates the sync").

### Principle worth keeping

"Scripts that use Hyprland-only features (window pop, toggle gaps,
scratchpad) don't need wrappers — those features don't exist in Niri."
Don't fake what has no equivalent.

## 3. henrysipp/omarchy-nix — NixOS module shape (adopt: options design only)

- **Shared options file**: one `config.nix` exporting `omarchyOptions`
  (`full_name`, `email_address`, `theme` enum, `theme_overrides.wallpaper_path`)
  imported by **both** `nixosModules` and `homeManagerModules` — single
  source of option definitions. Worth copying for `modules/omarchy/`.
- Uses nix-colors (our analog: Stylix) for theme colors.
- **Critical caveat**: it never consumes the real omarchy — it's an
  "inspired" reimplementation that references `~/.local/share/omarchy/bin/*`
  paths it assumes exist, and it is unmaintained. **Validates our
  decision to consume upstream verbatim (`flake=false` input) and adapt
  additively rather than reimplement.**

## Implications for our port (Phase 2/3 decisions)

1. **Phase 3 keybinding map**: start from okimarchy's `bindings.kdl` and
   re-validate against current omarchy (their base is 3.1.7); use the
   jeremy IPC cookbook for all `niri msg` JSON work.
2. **Phase 3 wrapper layer**: adopt the PATH-shadow + `is_niri` + exec
   fallback pattern, `$OMARCHY_WM` gating, and a `check-upgrade.sh`-style
   CI gate that fails on un-wrapped hyprctl usage.
3. **Niri config**: generate `config.kdl` **at Nix build time** from
   modular fragments (okimarchy's layout, but declarative), with the
   Stylix theme fragment appended last.
4. **Phase 2 (qml-niri QML swap) remains novel** — keep the config-level
   niri adaptation as the fallback for anything the shell QML can't
   express (waybar path, per-widget degradation).
5. **WM switching**: `NIRI_SOCKET`/`HYPRLAND_INSTANCE_SIGNATURE` detection
   + uwsm session entry (already matches zephyr's `niri-uwsm` autologin);
   runtime switching maps to a flake-input channel swap (niri-stable/rc/edge)
   rather than an Arch-style post-install switcher.
