# Desktop Modules

Desktop modules manage Wayland compositor selection, display configuration,
HDR support, and application integration across the cluster.

## Module Inventory

| Module | Purpose | Used By |
|--------|---------|---------|
| `desktop.nix` | Plasma 6 Wayland with XWayland fallback, monitor auto-setup | All desktop hosts |
| `plasma6.nix` | KDE Plasma 6 environment, kscreen monitor setup | All desktop hosts |
| `wayland-common.nix` | Shared PipeWire, Bluetooth, libinput, dbus-broker | All desktop hosts |
| `wayland-compositor-common.nix` | Shared compositor packages (noctalia, cliphist) | Niri/Hyprland hosts |
| `uwsm-sessions.nix` | UWSM session wrapper for SDDM compositor selection | Niri/Hyprland hosts |
| `niri.nix` | Niri scroll-tiling compositor config, NVIDIA support | Zephyr, Forge |
| `niri-settings.nix` | Niri KConfig-based settings (keybinds, layout) | Niri hosts |
| `gamescope-tty.nix` | Steam Gamescope session on tty3 for dedicated gaming | Nexus |
| `flatpak.nix` | Flatpak with Discover integration and Flathub | Zephyr |
| `spotify-spotx.nix` | Spotify Flatpak with SpotX ad-removal patch | Zephyr, Forge, Sentry |
| `systems-intelligence-plasmoid.nix` | Cluster monitoring Plasma widget | Zephyr |

## Compositor Selection

Compositors are selected at login via SDDM's session picker. Each host
configures a default session via `services.displayManager.defaultSession`:

| Host | Default Session | Available Sessions |
|------|----------------|-------------------|
| Zephyr | Plasma | Plasma, Niri, Hyprland |
| Nexus | Niri | Plasma, Niri, Gamescope (tty3) |
| Forge | Niri | Plasma, Niri |

### Session Architecture

```
SDDM (display manager)
├── Plasma 6 (default on Zephyr)
│   └── KWin (Wayland compositor)
├── Niri (scroll-tiling, via UWSM)
│   └── noctalia (bar, notifications, launcher)
├── Hyprland (tiling, via UWSM)
│   └── noctalia (same binary, different backend)
└── Gamescope (tty3, dedicated gaming on Nexus)
```

### Enabling a New Compositor

1. Set `programs.<compositor>.enable = true` in the host config
2. Set `desktop.uwsm-sessions.enable = true` (for Niri/Hyprland)
3. Configure `services.displayManager.defaultSession` for auto-login
4. Session appears in SDDM picker automatically

## HDR Support

HDR is managed via `services.gaming.hdr.enable` and is currently only
enabled on Zephyr (connected to 4K HDR TV). Requires:
- KDE Plasma 6 with Wayland
- `programs.scopebuddy` for auto-detection of HDR/VRR capabilities
- Compatible display connected via HDMI 2.1 or DisplayPort

## Flatpak Integration

`services.flatpak-kde` provides Flatpak with KDE Discover integration:
- Flathub remote auto-configured
- Automatic updates (configurable via `autoUpdate`)
- Used for Spotify (with SpotX patch) and other GUI apps

## Noctalia v5

Noctalia v5 is a native C++ Wayland shell (bar, notifications, launcher,
control center, session lock) that replaces the Qt/QML v4 `noctalia-shell`.
It is installed via the upstream NixOS module (`programs.noctalia.enable`)
and launched via `uwsm app -s s -- noctalia` from niri's spawn-at-startup
list. The binary is added to `environment.systemPackages` by
`wayland-compositor-common.nix`. Configuration uses TOML (not v4 JSON).
