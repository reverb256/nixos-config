{
  config,
  lib,
  pkgs,
  ...
}:

# Omarchy UX layer — Tier-1 verbatim port (epic #655, Phase 1 #656).
#
# Installs the pinned `omarchy` flake input (via pkgs.omarchy) and wires the
# runtime contract upstream expects:
#   - OMARCHY_PATH  →  $out/share/omarchy (themes/plugins/config/dots resolve)
#   - bin/omarchy*  →  on PATH (the router + ~160 commands)
#   - applications/*.desktop + icons  →  XDG_DATA_DIRS (launcher entries)
#   - manual/*.md   →  installed read-only docs
#
# Tier 1 is verbatim: no Hyprland/Arch coupling, no QML patch. The hard shell
# work (Quickshell.Niri) is Phase 2 (#657); command re-targeting Phase 3 (#658);
# package parity Phase 4 (#659). This module only proves the flake-input
# integration model and makes `omarchy` CLI + themes work.
let
  cfg = config.programs.omarchy;
in
{
  options.programs.omarchy = {
    enable = lib.mkEnableOption "Omarchy UX layer (themes, router, plugins, dots)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.omarchy;
      defaultText = lib.literalExpression "pkgs.omarchy";
      description = "The Omarchy package (verbatim Tier-1 source tree).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    # The runtime root upstream hardcodes as /usr/share/omarchy. Nix store
    # paths are the equivalent; every omarchy-* command that resolves data
    # (themes, plugins, shell.json, dots) reads $OMARCHY_PATH. Set it
    # session-wide so both interactive shells and the future Quickshell unit
    # inherit the correct root.
    environment.sessionVariables.OMARCHY_PATH = "${cfg.package}/share/omarchy";

    # XDG launcher entries + manual. The .desktop files land in the package's
    # share/applications so they show up in niri/fuzzel via XDG_DATA_DIRS; the
    # manual is exposed read-only so `omarchy` help can point at it.
    environment.pathsToLink = ["/share/applications" "/share/icons" "/share/doc"];
  };
}
