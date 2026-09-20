# pkg-shim/ — nix-backed package commands (Phase 4)

The package-management adaptation from epic #655 (#659). Under the
runtime-vs-declarative boundary (see the design plan), Omarchy's package/update
commands are *runtime UX* and stay imperative — re-targeted to work against
Nix, not clear-errored.

Each file in `bin/` is a shim that keeps the same `# omarchy:*` metadata as
upstream, so the router's command table and `omarchy --help` are unchanged;
only the body swaps `pacman`/`yay` for `nix profile`. `pkgs/omarchy.nix`
overlays these over the verbatim `bin/` tree in its installPhase.

## Implemented

| command | Nix-backed behavior |
|---------|---------------------|
| `omarchy-pkg-add` | `nix profile install nixpkgs#<attr>` for missing packages |
| `omarchy-pkg-drop` | `nix profile remove <name>` (ignores missing; system pkgs stay) |
| `omarchy-pkg-install` | fzf over `nix search nixpkgs` → `nix profile install` |
| `omarchy-pkg-remove` | fzf over `nix profile list` names → `nix profile remove` |
| `omarchy-pkg-missing` | true if any executable is absent from PATH/profile |
| `omarchy-pkg-present` | true if all executables are on PATH (or a profile name matches) |
| `omarchy-pkg-aur-add` / `-install` / `-accessible` | clear-error → pointer to `omarchy pkg add/install` |
| `omarchy-version-pkgs` | system profile mtime (last switch, ≈ last upgrade) |
| `omarchy-refresh-pacman` | clear-error → pointer to `just deploy` |

## Known caveats (verify at build/smoke time)

- `nix profile install nixpkgs#<attr>` resolves `nixpkgs` via the user's flake
  registry. Pin it there to enforce the cluster's nixpkgs age gate.
- `pkg-present` checks the executable on PATH, so a package whose binary name
  differs from its attribute name (`ripgrep` → `rg`) should be checked by its
  binary name.
- The fzf TUIs are first-pass: `nix search` is slow for broad queries and needs
  `jq` + `fzf` on PATH. Polish after a build.

## Not yet implemented (next batch)

- `omarchy-update` + its pipeline (`-system-pkgs`, `-keyring`, `-pacman-guard`,
  `-aur-pkgs`, `-orphan-pkgs`, `-pkg-prune`) → `nix profile upgrade` + GC,
  reporting the system step as `just deploy`.
- `omarchy-reinstall-pkgs`, `omarchy-install-preinstalls`, `-remove-preinstalls`.
- `omarchy-update-mise` / `omarchy-mise-install` — keep verbatim (mise is a
  user-level runtime tool; it already works on NixOS).
