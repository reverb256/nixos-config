# modules/omarchy — Omarchy UX layer on NixOS (epic #655)

Tier-1 verbatim port of `basecamp/omarchy` (flake input `omarchy`, flake=false),
installed to the store by `pkgs/omarchy.nix` and exposed via `pkgs.omarchy`.

Layout (matches the upstream `/usr/share/omarchy` runtime root):

| Path | Purpose |
|------|---------|
| `default.nix` | NixOS module: installs `pkgs.omarchy`, sets `OMARCHY_PATH`, links apps/manual |
| `niri-shim/` | Phases 2-3: Hyprland → Niri re-targeting (QML `Quickshell.Niri`, `niri msg`, lock/picker/sunset) |
| `pkg-shim/` | Phase 4: nix-backed `omarchy-pkg-add/drop`, `omarchy-update` |

Upstream sync = bump the `omarchy` rev in `flake.nix` + `nix flake update omarchy`.
No fork, no vendored copy.
