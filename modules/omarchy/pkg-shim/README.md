# pkg-shim/ — nix-backed package commands (Phase 4)

Placeholder for the package-management adaptation from epic #655 (#659):

- `omarchy-pkg-add` / `omarchy-pkg-drop` → nix-backed (flake inputs,
  `nix profile`), same CLI shape
- `omarchy-update` → flake update + rebuild path
- AUR helper commands → nix equivalents (or clear errors)

Nothing lives here yet. Files land under this directory when Phase 4 starts.
