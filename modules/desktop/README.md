# Desktop Modules

Desktop modules manage the Niri Wayland compositor, display configuration,
HDR support, and application integration across the cluster.

## Module Inventory

| Module | Purpose | Used By |
|--------|---------|---------|
| `desktop.nix` | Desktop integration: XWayland, PipeWire, Bluetooth, and session environment | All desktop hosts |
| `desktop-monitor.nix` | GPU readiness, Niri monitor layout, and TV power daemon | Desktop hosts except Sentry |
| `wayland-common.nix` | Shared PipeWire, Bluetooth, libinput, and dbus-broker | All desktop hosts |
| `wayland-compositor-common.nix` | Shared compositor packages (Noctalia, cliphist) | Niri hosts |
| `uwsm-sessions.nix` | UWSM session wrapper for SDDM compositor selection | Niri hosts |
| `niri.nix` | Niri compositor integration and NVIDIA support | All Niri hosts |
| `alacritty-system.nix` | System-level Alacritty package and launcher integration | Desktop hosts |
| `gamescope-tty.nix` | Steam Gamescope session on tty3 for dedicated gaming | Nexus |
| `flatpak.nix` | Flatpak with Flathub integration | Zephyr |
| `spotify-spotx.nix` | Spotify Flatpak with SpotX customization | Zephyr, Forge, Sentry |

KDE Plasma and Hyprland modules are intentionally absent. User-level Niri
settings and keybindings live in the `home-manager-config` repository.

## Compositor Selection

Niri is selected at login through SDDM's session picker. Each host configures
its default session through `services.displayManager.defaultSession`.

| Host | Default Session | Available Sessions |
|------|----------------|-------------------|
| Zephyr | Niri (`niri-uwsm`) | Niri |
| Nexus | Niri (`niri-uwsm`) | Niri, Gamescope (tty3) |
| Forge | Niri (`niri-uwsm`) | Niri |

### Session Architecture

```
SDDM (display manager)
└── Niri (scroll-tiling, via UWSM)
    └── Noctalia (bar, notifications, launcher)
```

## HDR Support

HDR is driven by the Niri HDR fork on Zephyr, connected to the 4K HDR TV via
HDMI-A-1. `desktop.niri-hdr-samsung.enable = true` configures the Niri HDR
output and NVIDIA tuning flags.

## Noctalia

Noctalia is a native Wayland shell providing the bar, notifications, launcher,
control center, and session lock. It is launched by UWSM from Niri's startup
configuration. User-facing Niri settings and keybindings are managed by
`home-manager-config`.
