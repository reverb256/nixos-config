# Desktop Modules

Desktop modules manage Wayland compositor selection, display configuration,
HDR support, and application integration across the cluster.

## Module Inventory

| Module | Purpose | Used By |
|--------|---------|---------|
| `desktop.nix` | Desktop integration: XWayland, monitor auto-setup, dbus/polkit | All desktop hosts |
| `plasma6.nix` | KDE Plasma 6 module (currently disabled cluster-wide; `desktopManager.plasma6.enable = false`) | None (disabled) |
| `wayland-common.nix` | Shared PipeWire, Bluetooth, libinput, dbus-broker | All desktop hosts |
| `wayland-compositor-common.nix` | Shared compositor packages (noctalia, cliphist) | Niri hosts |
| `uwsm-sessions.nix` | UWSM session wrapper for SDDM compositor selection | Niri hosts |
| `niri.nix` | Niri scroll-tiling compositor config, NVIDIA support | All Niri hosts (zephyr/forge/nexus/sentry) |
| `niri-settings.nix` | **REMOVED** — niri settings now live in `home-manager-config/modules/niri-config.nix` (+ niri-spawn/outputs/keybinds sub-modules) | — |
| `gamescope-tty.nix` | Steam Gamescope session on tty3 for dedicated gaming | Nexus |
| `flatpak.nix` | Flatpak with Discover integration and Flathub | Zephyr |
| `spotify-spotx.nix` | Spotify Flatpak with SpotX ad-removal patch | Zephyr, Forge, Sentry |
| `systems-intelligence-plasmoid.nix` | Cluster monitoring Plasma widget | Zephyr |

## Compositor Selection

Compositors are selected at login via SDDM's session picker. Each host
configures a default session via `services.displayManager.defaultSession`:

| Host | Default Session | Available Sessions |
|------|----------------|-------------------|
| Zephyr | Niri (`niri-uwsm`) | Niri |
| Nexus | Niri (`niri-uwsm`) | Niri, Gamescope (tty3) |
| Forge | Niri (`niri-uwsm`) | Niri |

### Session Architecture

```
SDDM (display manager)
├── Niri (scroll-tiling, via UWSM) — default on all desktop hosts
│   └── noctalia (bar, notifications, launcher)
└── Gamescope (tty3, dedicated gaming) — nexus
```

### Enabling a New Compositor

1. Set `programs.<compositor>.enable = true` in the host config
2. Set `desktop.uwsm-sessions.enable = true` (for Niri)
3. Configure `services.displayManager.defaultSession` for auto-login
4. Session appears in SDDM picker automatically

## HDR Support

HDR is driven by the niri HDR fork on Zephyr (connected to the 4K HDR TV via
HDMI-A-2); `desktop.niri-hdr-samsung.enable = true` sets `outputs."HDMI-A-2".hdr`
and the NVIDIA tuning flags. Requires:
- Niri HDR fork (`programs.niri.package = niri-unstable`)
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
