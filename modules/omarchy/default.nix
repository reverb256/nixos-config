{
  config,
  lib,
  pkgs,
  ...
}:

# Omarchy UX layer — Tier-1 verbatim port (epic #655, Phase 1 #656) + Phase 2
# shell wiring (#657).
#
# Installs the pinned `omarchy` flake input (via pkgs.omarchy) and wires the
# runtime contract upstream expects:
#   - OMARCHY_PATH  →  $out/share/omarchy (themes/plugins/config/dots resolve)
#   - bin/omarchy*  →  on PATH (the router + ~160 commands)
#   - applications/*.desktop + icons  →  XDG_DATA_DIRS (launcher entries)
#   - manual/*.md   →  installed read-only docs
#
# Phase 2 wires the shell: `programs.omarchy.shell` defaults to
# `pkgs.quickshell-niri` (quickshell 0.3.0 + the third-party `import Niri`
# plugin), and `NIRI_SOCKET` is inherited from the niri session environment
# (niri exports it to its children, so no explicit wiring is needed — but we
# document it here because the plugin hard-fails without it).
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

    shell = {
      enable = lib.mkEnableOption "the Omarchy Quickshell shell on Niri (Phase 2)";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.quickshell-niri;
        defaultText = lib.literalExpression "pkgs.quickshell-niri";
        description = "Quickshell with the Niri plugin wired in (import Niri).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      [cfg.package]
      ++ (lib.optional cfg.shell.enable cfg.shell.package);

    # The runtime root upstream hardcodes as /usr/share/omarchy. Nix store
    # paths are the equivalent; every omarchy-* command that resolves data
    # (themes, plugins, shell.json, dots) reads $OMARCHY_PATH. Set it
    # session-wide so both interactive shells and the Quickshell shell unit
    # inherit the correct root.
    environment.sessionVariables.OMARCHY_PATH = "${cfg.package}/share/omarchy";

    # The shell (shell/shell.qml) locates its plugins/config via OMARCHY_PATH;
    # the Niri plugin (`import Niri`) needs NIRI_SOCKET, which niri exports to
    # its children. QML_IMPORT_PATH is already handled by quickshell-niri's
    # wrapQtAppsHook (the plugin ships in buildInputs), so no manual entry.
    # Documented here so the contract is visible in one place.

    # XDG launcher entries + manual. The .desktop files land in the package's
    # share/applications so they show up in niri/fuzzel via XDG_DATA_DIRS; the
    # manual is exposed read-only so `omarchy` help can point at it.
    environment.pathsToLink = ["/share/applications" "/share/icons" "/share/doc"];
  };
}
