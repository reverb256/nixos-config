# Home Manager Centralization Design

**Date:** 2026-03-12
**Author:** Claude Code
**Status:** Approved

## Problem Statement

Home Manager configurations are inconsistent across cluster nodes:
- **Zephyr** uses an inline `home-manager` block in `configuration.nix` with zen-browser, nixcord, and fish shell
- **Forge, Nexus, Sentry** import `modules/system/home-manager.nix` which provides fish + starship
- The shared module exists but zephyr doesn't use it

This creates drift and makes it harder to maintain consistent user environments across the cluster.

## Solution

Centralize Home Manager configuration with a modular approach that all nodes import, providing a consistent base while allowing for future node-specific extensions.

## Architecture

```
modules/home-manager/
├── default.nix          # Main entry point, imports all modules
├── fish.nix             # Shell configuration (existing, updated)
├── starship.nix         # Prompt configuration (existing, no change)
├── gui-apps.nix         # GUI applications (NEW: zen-browser, nixcord)
└── wayland-tools.nix    # Wayland utilities (NEW: wl-clipboard, grim, slurp)
```

## Module Contents

### Shared Base Configuration (All Nodes)

**fish.nix:**
- Fish shell with aliases, functions, abbreviations
- CLI tools: eza, bat, btop, dust, dufs, fastfetch, zoxide, ripgrep, fd, fzf, lazygit
- NixOS management aliases
- Git shortcuts
- Navigation aliases
- **Removed:** Audio profile aliases (zephyr-specific, deleted)

**starship.nix:**
- Cluster-optimized prompt format
- Shows hostname, git branch, nix shell status
- Username disabled (cleaner prompt)

**gui-apps.nix (NEW):**
- zen-browser home module
- nixcord home module

**wayland-tools.nix (NEW):**
- wl-clipboard (wayland copy/paste)
- grim (screenshots)
- slurp (region selection)
- Aliases: wclip, wpaste, swl, swlr, killhypr, restartwaybar

**systemd user environment:**
- HF_TOKEN path for Hugging Face

## Node Changes

### Zephyr
- **Remove:** Inline `home-manager` block (lines ~899-910 in configuration.nix)
- **Add:** Import of `../../modules/system/home-manager.nix` (already in modules/default.nix)

### Forge, Nexus, Sentry
- **No changes needed** - already import shared module
- **Benefit:** Automatically gain zen-browser, nixcord, and wayland tools

### modules/system/home-manager.nix
- **Update:** Import from `../../home-manager/default.nix`
- Acts as system-level integration point

## Implementation Steps

1. Create `modules/home-manager/gui-apps.nix`
2. Create `modules/home-manager/wayland-tools.nix`
3. Create `modules/home-manager/default.nix` (entry point)
4. Update `modules/home-manager/fish.nix` (remove audio aliases)
5. Update `modules/system/home-manager.nix` (use new default.nix)
6. Update `hosts/zephyr/configuration.nix` (remove inline home-manager)
7. Delete `/etc/nixos/docs/audio-profiles.sh`

## Benefits

1. **Consistency:** All nodes have identical user environments
2. **Maintainability:** Single source of truth for shell and app configuration
3. **Flexibility:** Modular structure allows future node-specific additions
4. **Simplicity:** New nodes get full config automatically via shared module

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| GUI apps on headless nodes | Packages are installed but not started; harmless |
| Wayland tools on non-graphical nodes | Aliases fail gracefully; tools only used when needed |
| Breaking zephyr's working config | Test on zephyr first before deploying to other nodes |
