{ config, lib, pkgs, ... }:
let
  # This module runs INSIDE the home-manager user config (imported by
  # modules/system/home-manager.nix under users.j_kro.imports), so `lib.hm`
  # (home-manager's extended lib) is in scope here — unlike the NixOS-level
  # system module, where lib.hm is NOT available.
  #
  # ROOT CAUSE of the 2026-07-22 home-manager-j_kro.service activation failure:
  # these two cleanup scripts previously lived in modules/system/home-manager.nix
  # as plain-string activation entries (auto-wrapped as `entryAnywhere`, i.e.
  # unconstrained in the DAG). The activation DAG orders `linkGeneration` BEFORE
  # them, so HM's own backup-on-conflict step ran first: when a live dotfile was
  # "in the way" it renamed it to `<file>.v3-fix`. On a SECOND failed run, that
  # stale `.v3-fix` already existed, so linkGeneration aborted the ENTIRE
  # activation ("Existing file '...v3-fix' would be clobbered"). The cleanup that
  # would have removed the stale backup ran too late (or not at all).
  #
  # FIX: pin BOTH scripts to run BEFORE `checkLinkTargets` via lib.hm.dag.entryBefore.
  # checkLinkTargets (HM's early collision guard) ABORTS the whole activation when a
  # plain file shadows an HM-managed target -- and it runs BEFORE linkGeneration.
  # So the cleanup must precede checkLinkTargets, not linkGeneration. The stale
  # backups are gone and the shadowing plain files are un-frozen before the guard
  # runs, breaking the abort cycle permanently.
  inherit (lib) mkIf;
in {
  # Remove stale HM backup files BEFORE linkGeneration to prevent clobber errors.
  home.activation.removeStaleBackups = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    # Old extension (gone on next activation) and new extension (until clean state)
    for ext in hm-backup v3-fix; do
      rm -f "$HOME/.config/alacritty/alacritty.toml.$ext"
      rm -f "$HOME/.config/starship.toml.$ext"
      rm -f "$HOME/.config/fish/config.fish.$ext"
      rm -f "$HOME/.config/gtk-3.0/gtk.css.$ext"
      rm -f "$HOME/.config/gtk-4.0/gtk.css.$ext"
      # Round 2: collision list captured during 2026-07-21 boot diagnosis
      # (HM activation failed because these stale backups blocked the
      # new backup write — list now mirrors the full healHMDrift set).
      rm -f "$HOME/.config/btop/btop.conf.$ext"
      rm -f "$HOME/.config/niri/noctalia.kdl.$ext"
      rm -f "$HOME/.config/lazygit/config.yml.$ext"
      rm -f "$HOME/.config/kitty/kitty.conf.$ext"
    done
  '';

  # ── Self-healing HM-ownership drift guard ──────────────────
  # Root cause of recurring stylix/dotfile drift: HM-owned dotfiles get
  # frozen as plain 0444 files (manual edit, failed activation) and HM
  # can no longer overwrite/relink them on switch — so they shadow the
  # generated stylix version forever. This guard detects any known
  # HM-managed dotfile that is a REGULAR FILE (not a symlink into the
  # store generation), makes it writable, and warns. With write perms,
  # HM's own activation reclaims it (moves to .hm-backup, relinks from
  # store) on the SAME switch. Never deletes — safe by design.
  # List = files HM generates via programs.* / xdg.configFile / stylix.
  # Runs BEFORE linkGeneration so the un-freeze happens before HM reclaims.
  home.activation.healHMDrift = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    for f in \
      "$HOME/.config/starship.toml" \
      "$HOME/.config/alacritty/alacritty.toml" \
      "$HOME/.config/btop/btop.conf" \
      "$HOME/.config/fish/config.fish" \
      "$HOME/.config/gtk-3.0/gtk.css" \
      "$HOME/.config/gtk-4.0/gtk.css" \
      "$HOME/.config/lazygit/config.yml" \
      "$HOME/.config/kitty/kitty.conf" ; do
      if [ -e "$f" ] && [ ! -L "$f" ]; then
        echo "healHMDrift: $f drifted from HM (plain file) — un-freezing so HM can reclaim it"
        chmod u+w "$f" 2>/dev/null || true
      fi
    done
  '';
}
