# Desktop Modules - Agent Context

**Parent:** `../../AGENTS.md` | **Domain:** Wayland compositors and desktop (14 .nix files)

## Overview
Wayland desktop environment with 2 compositors managed via UWSM.
Only enabled on Zephyr (workstation) and optionally Nexus/Forge.

## Compositor Setup (UWSM)

| TTY | Compositor | Config |
|-----|-----------|--------|
| tty1 | KDE Plasma 6 | `plasma6.nix` |
| tty2 | Niri (scrollable tiling) | `niri.nix`, `home-manager/niri-config.nix` |

Session registration: `uwsm-sessions.nix` handles all 3.
Portal routing: `desktop.nix` routes per-compositor (KDE→kde, Niri→gnome+gtk).

## Where To Look

| Task | Location |
|------|----------|
| Plasma 6 config | `plasma6.nix` (841 lines — largest desktop file) |
| Niri config | `niri.nix`, `home-manager/niri-config.nix` (392 lines) |
| Wayland common settings | `wayland-common.nix` |
| Shared compositor packages | `wayland-compositor-common.nix` |
| Flatpak support | `flatpak.nix` |
| Theming (Stylix) | `stylix.nix` |
| Spotify mods | `spotify-spotx.nix`, `lib/spotify-common.nix` |
| Gamescope | `gamescope-tty.nix` |
| Brightness control | `noctalia-sdr-brightness.nix` |

## Large Files
- `plasma6.nix` (841 lines) — dense, modify carefully
- `home-manager/zen-browser.nix` (841 lines) — browser config
- `home-manager/niri-config.nix` (392 lines)

## Conventions
- `programs.*` namespace for GUI apps
- Portal files auto-routed per active compositor
- Wayland-only (no X11/XWayland fallback)
