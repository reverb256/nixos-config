# Home Manager Modules - Agent Context

**Parent:** `../../AGENTS.md` | **Domain:** HM user-level modules (12 .nix files)

## Overview
Home Manager modules for user-level application config (browsers, terminals, editors).
Applied per-user via `home-manager.users.<name>` in host configs.

## Where To Look

| Task | Location |
|------|----------|
| Zen Browser config | `zen-browser.nix` (841 lines — largest HM file) |
| Niri compositor config | `niri-config.nix` (392 lines) |
| Ghostty terminal | `ghostty.nix` |
| Fish shell | `fish.nix` |
| Starship prompt | `starship.nix` |
| Nixcord (Discord) | `nixcord-config.nix` |
| Firefox PWA apps | `firefox-pwa-apps.nix` |
| Obsidian | `obsidian.nix` |
| OpenCode | `opencode.nix` |
| Caprine (Messenger) | `caprine.nix` |
| Icon theme | `icon-theme.nix` |
| Wayland tools | `wayland-tools.nix` |

## Conventions
- These are HM modules, not NixOS system modules
- They configure user-level apps, not system services
- Large files: `zen-browser.nix` (841 lines), `niri-config.nix` (392 lines)
- Browser configs tend to be large due to extension/pref settings
