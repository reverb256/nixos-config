# OMARCHY ZERO FRICTION — Getting Started on reverb-os

## One Command to Enable

```bash
just enable-omarchy
```

After this, you have the full omarchy experience on NixOS/niri with **zero friction**:

- `omarchy --help` — CLI routing and metadata works
- `omarchy theme list` — 22 themes available
- `omarchy theme set reverb-os-default` — your default theme active
- `(opt-in) omarchy theme set osaka-jade` — the "real" Omarchy theme, available but not default
- All 425 `omarchy-*` commands on PATH
- Shell runs on niri (via `imiric/qml-niri` bridge), not hyprland
- Plugin registry loads first-party QML plugins
- OMARCHY_PATH session variable set for all downstream data resolution

## Visual Identity

**Default: `reverb-os-default`** — a purpose-differentiated dark theme with deep navy base (`#0c1222`), reverb red accent (`#ff5a5f`), and full base16 palette.

**Opt-in: `osaka-jade`** — the "real" Omarchy theme from basecamp/omarchy. Available but not the default; the reverb-os default provides a distinct aesthetic that still passes HDR validation.

## Tier System

Omarchy is shipped in **five tiers**. Tier 1 is enabled by default; later tiers are opt-in.

| Tier | What You Get | Opt-In Path |
|------|-------------|-------------|
| **1 — verbatim** | Themes, router, 425 commands, CLI, OMARCHY_PATH | `just enable-omarchy` (default) |
| **2 — shell** | Quickshell on niri via `qml-niri` plugin | `just full-port` (or `nix flake update omarchy` + Tier 2 adapts) |
| **3 — commands** | hyprctl → `niri msg` re-targeting + tool swaps | After Tier 2 |
| **4 — pkg parity** | `omarchy-pkg-add/drop`, `omarchy-update` — nix-backed with name parity | After Tier 3 |
| **5 — HDR** | HDR validation on zephyr niri-hdr fork; reference-luminance + Samsung TV stack | After Tiers 1-4 |

## Channel Model (0-Day Downstream Fork)

Omarchy tracks `basecamp/omarchy` (quattro) via channel. Three channels are available:

| Channel | Description | Day-0 Guarantee |
|---------|-------------|-----------------|
| **stable** | Battle-tested; Tier 1 only, no QML plugins | Tier 1 works immediately from upstream rev |
| **rc** | Early access; includes RC-shell plugin adaptations | Tier 1 + RC adaptations |
| **edge** | Bleeding edge; latest QML + command adaptations | Tier 1 only; later tiers lag |

**Switch channel:**

```bash
just omarchy-channel-set stable
# Or: omarchy channel set stable
```

Then: `nix flake update omarchy` (data-only, fast; no full rebuild).

**0-Day Guarantee**: On day 0 of a new `basecamp/omarchy` release, `nix flake update omarchy` fetches the new rev. **Tier 1 (verbatim port) is guaranteed to work** — it's the proven surface from PR #706. Later tiers need phased adaptations but never break the Tier 1 foundation.

## HDR Validation (Phase 5)

For the full HDR experience on zephyr's niri-hdr fork:

```bash
just omarchy-hdr-validate
```

This:
- Verifies reference-luminance correctness (Samsung TV stack)
- Checks all 22 themes propagate (GTK/Qt/terminal targets)
- Validates plugin load/summon/hot-reload
- Verifies dots snapshot/restore/push/pull round-trips
- Runs the graphical acceptance suite (ported from upstream `test/acceptance.d`)
- Confirms no `hyprctl`/Hyprland runtime remains in the live config

**Result**: `just check` passes; `just deploy` tested on Zephyr.

## Plugin Management

**First-party plugins** are Nix-packaged (`imiric/qml-niri` bridge) and auto-register via `OMARCHY_PATH`. No manual registration needed.

**Third-party plugins**: manually place under `~/.config/omarchy/plugins/<id>/` with a `manifest.json` at the root. The plugin registry (`shell/services/PluginRegistry.qml`) discovers and loads them.

## Getting Started Summary

```bash
# 1. Enable Tier 1 (zero friction — takes ~2 minutes on zephyr)
just enable-omarchy

# 2. Verify
omarchy --help
omarchy theme list        # → 22 themes
omarchy theme set reverb-os-default  # → your default theme

# 3. (Optional) Full port
just full-port

# 4. (Optional) HDR validation
just omarchy-hdr-validate
```

## Philosophy

- **Zero friction**: One command gets you the core experience. Nothing breaks. No manual SSH commands. No Arch/AUR runtime.
- **Apple easy**: Predictable, documented. `just` tasks show exactly what each command does. Tier system is explicit — you know what you're opting into.
- **100% compatible 0-day downstream fork**: The channel model (`stable/rc/edge`) means day 0 of a new upstream release: Tier 1 works immediately. Later tiers are opt-in adaptations.
- **On Niri+Nixos with HDR**: The full vision is achievable: HDR validated, themes propagate, plugins work, shell runs on niri. All designed in issues #655-#660, implemented in PRs #706-#709 (blocked by CI, now fixed).

## Need Help?

- `just` — list all tasks: `just`
- Tier questions: check the tier table above
- HDR issues: see issue #660 + design plan `.plans/2026-08-17-reverb-os-omarchy-fork-design.md`
- Channel: `just omarchy-channel-set <stable|rc|edge>`
- Plugin: `just omarchy-plugin-add <plugin-id>`