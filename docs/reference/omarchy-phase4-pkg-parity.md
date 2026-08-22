# Omarchy Phase 4 — nix-backed package commands (name parity)

> Static analysis of upstream `bin/`. Feeds #659. No build-dependent work.

## Goal

Keep every `omarchy pkg` / `omarchy update` command name and user-facing shape
identical, but back them with Nix instead of pacman/AUR. No pacman/AUR runtime.

## 1. Command surface (33 pacman/AUR-touching scripts, 16 mise-touching)

### Package group — direct parity

| upstream command | Arch behavior | Nix-backed behavior |
|------------------|---------------|---------------------|
| `omarchy-pkg-add` | `pacman -S --needed` + verify `pacman -Q` | `nix profile install` (or flake-input + rebuild); verify via `nix profile list` |
| `omarchy-pkg-drop` | `pacman -Rns` (exact-name only) | `nix profile remove` |
| `omarchy-pkg-install` | pacman install | same as add |
| `omarchy-pkg-remove` | pacman remove | `nix profile remove` |
| `omarchy-pkg-missing` / `-present` | `pacman -Q` query | `nix profile list` / `command -v` / `nix eval` presence |
| `omarchy-pkg-aur-add` / `-install` / `-accessible` | AUR (yay/paru) | **no AUR** — map to nixpkgs search or clear-error |
| `omarchy-reinstall-pkgs` | reinstall base package list | `nix profile` re-sync or `just build`/`switch` |
| `omarchy-install-preinstalls` / `-remove-preinstalls` | pacman bootstrap | `nix profile install` list / remove list |

### Update group — pipeline re-target

`omarchy-update` is a pipeline (lock → free-space → prune → snapshot → keyring →
`pacman -Syu` → migrate → hook → AUR → mise → orphans → logs → status). The Nix
equivalent collapses most stages:

| upstream stage | Nix equivalent |
|----------------|----------------|
| `omarchy-update-lock` | `flock` on a lockfile (keep as-is) |
| `omarchy-update-requires-free-space` | keep (df check) |
| `omarchy-update-pkg-prune` | `nix-collect-garbage -d` |
| `omarchy-snapshot create` | NixOS generation rollback (already built-in) |
| `omarchy-update-keyring` | **drop** (no pacman keyring) |
| `omarchy-update-system-pkgs` (`pacman -Syu`) | `nix flake update` + `nixos-rebuild`/`just deploy` |
| `omarchy-migrate` | NixOS config migrations (declarative) |
| `omarchy-hook post-update` | keep (user hooks) |
| `omarchy-update-aur-pkgs` | **drop** (no AUR) |
| `omarchy-update-mise` | **mise is a runtime tool** — keep `mise`/`mise upgrade` or map to `nix profile` |
| `omarchy-update-orphan-pkgs` | `nix profile list` stale + `nix-collect-garbage` |
| `omarchy-update-pacman-guard` | **drop** (no direct-pacman guard needed; NixOS is declarative) |
| `omarchy-update-available` / `-status` / `-analyze-logs` / `-time` / `-user-notify` / `-restart` / `-confirm` / `-stay-awake` | keep as-is (package-manager-agnostic) |
| `omarchy-version-pkgs` | `nix eval --raw .#nixosConfigurations.<host>.config.system.nixos.release` or lockfile rev |

### Mise group (16 scripts)

`omarchy-update-mise`, `install/user/mise.sh`, `install/user/mise-work.sh` —
mise is a user-level toolchain manager, not Arch. It already works on NixOS
(pure runtime). **Keep these verbatim** — they don't touch pacman.

## 2. The `GROUP_DESCRIPTIONS[pkg]` contract

The router's `pkg` group metadata (`omarchy pkg add|drop|install|remove|aur|…`)
must keep its exact names so the shell menu + CLI help don't change. Only the
*implementations* under `modules/omarchy/pkg-shim/` swap.

## 3. Design decision: `nix profile` vs flake-input

Two candidate backings for `omarchy-pkg-add`:

1. **`nix profile install nixpkgs#foo`** — closest to pacman's "install a binary
   now", matches the Layer-3 profile model (AGENTS.md: high-churn binaries live
   in `nix profile`). Fast, no rebuild.
2. **flake input + rebuild** — declarative, but slow and requires a `just deploy`.

Recommendation (softened 2026-08-18): **`nix profile` for
`pkg-add/drop/install/remove`** (Layer 3) and **`nix profile upgrade` +
`nix-collect-garbage` for `omarchy-update`** (runtime layer). The system-wide
flake update + rebuild is *reported* as `just deploy`, not run implicitly —
that keeps Omarchy's update friction-free without making the shell mutate NixOS
system state. This mirrors the existing 3-layer model and needs no new
machinery.

## 4. What must be clear-errors (no safe Nix equivalent)

Only AUR + pacman-keyring surfaces, which have no safe NixOS equivalent:
`omarchy-pkg-aur-add`, `-aur-install`, `-aur-accessible`, `omarchy-update-keyring`,
`omarchy-update-pacman-guard`, `omarchy-refresh-pacman`. Each: non-zero exit +
pointer ("AUR is not available on NixOS; use `omarchy pkg add` for nixpkgs
packages"). Everything else is re-targeted to work (see the boundary in the
design doc), not clear-errored. No silent no-op (per #658's rule).

## 5. Smoke-test checklist (implementation time)

- `omarchy pkg add <pkg>` → `nix profile install`, `omarchy-pkg-present` true
- `omarchy pkg drop <pkg>` → `nix profile remove`
- `omarchy update` → flake update + rebuild path (with lock/snapshot semantics)
- `omarchy pkg aur add` → clear-error
- `omarchy version pkgs` → nixpkgs rev
- `GROUP_DESCRIPTIONS[pkg]` unchanged (shell menu parity)
