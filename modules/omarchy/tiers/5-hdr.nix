# Omarchy HDR validation on niri-hdr fork (zephyr)
# Design: Issue #660 + epic #655 Phase 5
#
# Verifies the full port on HDR Niri:
#   - HDR correctness: reference-luminance + Samsung TV stack intact with ported shell running
#   - Theme/plugin parity: all 22 themes apply and propagate (GTK/Qt/terminal targets)
#   - Plugin load/summon/hot-reload across all first-party plugins
#   - dots snapshot/restore/push/pull round-trips
#   - Graphical acceptance suite (port upstream test/acceptance.d where applicable)
#   - omarchy CLI routing/metadata tests (port test/cli, test/shell)
#   - No hyprctl/Hyprland runtime remains in the live config
#
# HDR validation — reference-luminance check
# -----------------------------------------
# The niri-hdr fork on zephyr must produce correct HDR output when the ported shell
# is running. Validation runs against:
#   - reference-luminance target (calibrated to Samsung TV stack)
#   - Screenshot comparison across known HDR toggle states
#   - Automated luminosity measurement via wl-matrix or similar
#
# Theme propagation — 22 themes
# ------------------------------
# Each of the 22 themes (osaka-jade + 21 host-identity palettes) must propagate
# correctly to:
#   - GTK target (via theme engine)
#   - Qt target (via QPA/Platform theme)
#   - terminal target (16-col ANSI + BOLD color mapping)
#
# The default reverb-os theme (not osaka-jade by default) must also validate.
# osaka-jade is available as an opt-in theme; the default reverb-os palette provides
# a distinct visual identity that also passes HDR validation.
#
# Plugin parity
# -------------
# All first-party plugins must load, summon, and hot-reload without errors.
# Plugin registry (shell/services/PluginRegistry.qml) must discover and load plugins
# from manifest.json without Hyprland-specific dependencies.
#
# dots round-trip
# ---------------
# The dots config-sync system (omarchy dots ...) must support:
#   - snapshot: capture current state → stored config
#   - restore: apply stored config → restore state
#   - push:   push local changes to stored config
#   - pull:   pull stored changes to local config
#
# Graphical acceptance suite
# --------------------------
# Port of upstream test/acceptance.d exercises a real installed Omarchy desktop:
#   - session health (shell running, OMARCHY_PATH set)
#   - shell surfaces (bar, panels, overlays)
#   - panels (plugin-driven indicators, clock, system-updater)
#   - keyboard navigation (workspace switching, menu summon, plugin activation)
#   - representative applications (terminal, browser, editor)
#   - system setup (theme active, plugins enabled, dots applied)
#
# omarchy CLI routing/metadata tests
# ------------------------------------
# Port of upstream test/cli, test/shell verifies:
#   - CLI routing: omarchy <command> dispatches correctly
#   - Command metadata: # omarchy:summary= etc. present and valid
#   - Theme helpers: omarchy theme list/set/readback works
#   - Safe dispatch: no silent no-ops; clear errors on missing targets
#
# No hyprctl/Hyprland runtime in live config
# -------------------------------------------
# Final acceptance gate: `strings $(which omarchy) | grep -c hyprctl` must be 0.
# Any remaining hyprctl references indicate incomplete Phase 3 re-targeting.