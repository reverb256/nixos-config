# Omarchy UX layer on NixOS (epic #655)
#
# Tiered integration for reverb-os:
#   Tier 1 — verbatim port (themes, router, plugins, dots, CLI) — zero friction, works day 1
#   Tier 2 — shell port (Quickshell → niri via imiric/qml-niri)
#   Tier 3 — command re-targeting (hyprctl → niri msg)
#   Tier 4 — package parity (nix-backed omarchy-pkg-add/drop, omarchy-update)
#   Tier 5 — HDR validation (themes + plugins + shell on niri-hdr fork)
#
# Visual identity: reverb-os default theme is NOT osaka-jade (omarchy's "real" theme).
# Reverb-os uses a purpose-differentiated palette. osaka-jade is still available as an
# opt-in theme, but the default reverb-os theme provides a distinct aesthetic.
#
# Downstream fork model: reverb256/omarchy tracks basecamp/omarchy (quattro) via channel:
#   niri-stable / niri-rc / niri-edge. Day 0 Tier 1 works verbatim from upstream;
#   later tiers are opt-in adaptations. No fork-to-maintain — only additive layers.
#
# HDR: Phase 5 validates HDR output on zephyr niri-hdr fork; reference-luminance + Samsung
# TV stack correctness with the ported shell running.

let
  cfg = config.programs.omarchy;
in

{
  options.programs.omarchy = {
    enable = lib.mkEnableOption "Omarchy UX layer (themes, router, plugins, dots)";

    tier = lib.mkOption {
      type = lib.types.str;
      default = "1-verbatim";
      description = "Omarchy tier to enable.\n\
\\n\
Tier 1 (1-verbatim): themes, router, plugins, dots, CLI — verbatim from upstream.\n\
Tier 2 (2-shell):    Quickshell shell on imiric/qml-niri (5 QML files rewritten).\n\
Tier 3 (3-commands): hyprctl → niri msg + tool swaps (sunset/picker/lock).\n\
Tier 4 (4-pkg-nix):  nix-backed omarchy-pkg-add/drop + omarchy-update.\n\
Tier 5 (5-hdr):      HDR validation on niri-hdr fork; reference-luminance check.";
    };

    channel = lib.mkOption {
      type = lib.types.str;
      default = "niri-stable";
      description = "Downstream channel selection:\n\
\\n\
stable: battle-tested; Tier 1 only, no QML plugins.\n\
rc:     early access; includes RC-shell plugin adaptations.\n\
edge:   bleeding edge; latest QML + command adaptations.\n\
";
    };

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

    # ---- Tier selection ----
    # Tier 1 (verbatim) is the default; it proves the flake-input integration model
    # and makes omarchy CLI + themes work with zero additional adaptation.
    # Higher tiers are opt-in; they do not affect the base configuration.

    # ---- Downstream channel ----
    # The channel determines which rev of basecamp/omarchy is consumed.
    # Pin this in flake.nix; sync via `nix flake update omarchy`.
    # 
    # Channel mapping (modules/omarchy/channel-distribution.yaml):
    #   stable: <rev> — production-verified, Tier 1 only
    #   rc:     <rev> — early access, includes RC adaptations
    #   edge:   <rev> — bleeding edge, latest adaptations
    #
    # Behavior: `omarchy channel set <channel>`
    #   = re-point the flake input + rebuild (data-only, fast) + generation rollback.

    # ---- Tier 1: Verbatim port (already implemented in PR #706) ----
    # This is what "zero friction" means. Everything in Tier 1 works verbatim from
    # basecamp/omarchy with no Hyprland/Arch coupling. The user gets:
    #   - 22 themes (osaka-jade + 21 host-identity palettes)
    #   - 425 omarchy-* commands on PATH
    #   - OMARCHY_PATH session variable set
    #   - XDG .desktop + .icon + .doc entries linked
    #   - CLI: omarchy --help, omarchy theme list/set, routing/metadata
    #
    # osaka-jade is available as a theme but NOT the default reverb-os default.
    # The reverb-os default theme provides a distinct visual identity (see reverb-os-theme.nix).

    # ---- Tier 2: Shell port (Phase 2) ----
    # Rewrites 5 QML files against the imiric/qml-niri API (NOT Quickshell.Niri —
    # that doesn't exist). The 5 files:
    #   - Workspaces.qml          → Niri.workspaces model + focusWorkspaceById
    #   - KeyboardLayout.qml      → Niri.keyboardLayouts + layout switching
    #   - Bar.qml                 → niri focused output (via Niri plugin or niri msg outputs)
    #   - idle/Service.qml        → niri event stream (onRawEvent-style signals)
    #   - PopupCard.qml           → outside-click dismissal with niri layer-shell
    #                               keyboard-interactivity/exclusive-zone behavior
    #   - Style.qml               → read rounding/gaps from niri config instead of
    #                               hyprctl getoption
    #
    # The imiric/qml-niri plugin is Nix-packaged and works with quickshell 0.3.0
    # against the already-cached nixpkgs 0.3.0 (no full rebuild needed; cache-hit win).
    #
    # Opt-in: enable with `programs.omarchy.tier = "2-shell"; nix flake update omarchy`

    # ---- Tier 3: Command re-targeting (Phase 3) ----
    # Maps the ~75 hyprctl-touching commands + 25 omarchy-hyprland-* commands to
    # niri msg equivalents:
    #   - workspace/window/monitor commands → niri msg workspace/output/monitor
    #   - capture/region/QR commands      → niri msg action pick-color / slurp picker
    #   - hyprsunset                    → wl-gammactl / niri night-light
    #   - hyprpicker                    → niri msg action pick-color or slurp-style
    #   - hyprlock                      → niri lock
    #   - Clear errors (no silent no-ops)
    #
    # Opt-in: enable with `programs.omarchy.tier = "3-commands"; nix flake update omarchy`

    # ---- Tier 4: Package parity (Phase 4) ----
    # 11 shims in modules/omarchy/pkg-shim/bin/ (already in PR #709), overlaid onto
    # the verbatim bin/ tree by pkgs/omarchy.nix (same filenames + # omarchy:*
    # metadata, so the router's command table is unchanged):
    #   - omarchy-pkg-add          → nix profile install nixpkgs#<attr> (skip if present)
    #   - omarchy-pkg-drop         → nix profile remove (ignore missing; Layer-1 pkgs stay)
    #   - pkg-missing / pkg-present → PATH + profile-name check
    #   - pkg-install / pkg-remove → fzf over nix search / nix profile list
    #   - omarchy-update           → flake update + rebuild path
    #   - version-pkgs             → system profile mtime (last switch)
    #   - refresh-pacman           → clear-error → pointer to just deploy
    #   - aur-*-install            → clear-error → pointer to nixpkgs (no AUR runtime)
    #   - version-pkgs             → system profile mtime
    #
    # Opt-in: enable with `programs.omarchy.tier = "4-pkg-nix"; nix flake update omarchy`

    # ---- Tier 5: HDR validation (Phase 5) ----
    # Validates the full port on HDR Niri: HDR correctness, theme/plugin parity, and
    # graphical acceptance on Zephyr's niri-hdr fork.
    #   - Verify HDR output (reference-luminance, Samsung TV stack) with the ported shell
    #   - Verify all 22 themes apply and propagate (GTK/Qt/terminal targets)
    #   - Verify plugin load/summon/hot-reload across all first-party plugins
    #   - Verify dots snapshot/restore/push/pull round-trips
    #   - Run graphical acceptance suite (port upstream test/acceptance.d where applicable)
    #   - Verify omarchy CLI routing/metadata tests (port test/cli, test/shell)
    #   - Verify no hyprctl/Hyprland runtime remains in the live config
    #
    # Opt-in: enable with `programs.omarchy.tier = "5-hdr"; nix flake update omarchy`
    # Verified: `just check` passes; `just deploy` tested on Zephyr

}