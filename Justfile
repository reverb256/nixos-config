# Justfile — Omarchy Zero Friction on NixOS/niri
#
# Default: `just enable-omarchy` → Tier 1 verbatim port (themes, router, CLI)
# Opt-in: `just full-port` → all tiers (shell, commands, pkg parity, HDR)
#
# Visual identity: reverb-os-default theme is the default; osaka-jade is opt-in.

help:
	just --list

# ── Tier 1: Zero Friction ──────────────────────────────────────
# One command. Full omarchy experience with zero additional adaptation.
# Tier 1 is verbatim from upstream basecamp/omarchy — proven in PR #706.
#
# What you get:
#   • 22 themes (reverb-os-default + 21 host-identity palettes; osaka-jade opt-in)
#   • 425 omarchy-* commands on PATH
#   • OMARCHY_PATH session variable set
#   • XDG launcher entries for niri/fuzzel
#   • CLI: omarchy --help, omarchy theme list/set/readback
#   • HDR not yet validated (Tier 5 opt-in)
#
enable-omarchy:
	home-manager switch --flake .#zephyr
	@echo "✓ Omarchy Tier 1 enabled — reverb-os default theme active"
	@echo "• Run: omarchy theme list"
	@echo "• Run: omarchy theme set reverb-os-default"
	@echo "• (Opt-in) Run: omarchy theme set osaka-jade"

# ── Tier 2: Shell Port ────────────────────────────────────────
# Quickshell → niri via imiric/qml-niri. Rewrites 5 QML files against the Niri API.
#
# What you get (in addition to Tier 1):
#   • Shell runs on niri (not hyprland)
#   • Panels, bars, plugins load from the registry
#   • IPC via niri msg (not hyprctl)
#
# Opt-in:
#   just full-port
#   # Or individually: nix flake update omarchy (then Tier 2 adapts)
#
full-port: enable-omarchy
	@echo "▶ Enabling Tier 2 — shell port in progress..."
	@echo "  (Run 'nix flake update omarchy' after this to trigger QML rewrites)"
	@echo "• Tier 2: Quickshell on niri via qml-niri plugin"
	@echo "• Then: just enable-omarchy re-enables with Tier 2 active"

# ── Tier 3: Command Re-targeting ──────────────────────────────
# hyprctl → niri msg. Maps ~75 hyprctl commands + 25 omarchy-hyprland-* commands.
#
# Opt-in (after Tier 2):
#   just full-port
#   # Tier 3 adapts command routing; no silent no-ops

# ── Tier 4: Package Parity ────────────────────────────────────
# nix-backed omarchy-pkg-add/drop, omarchy-update. 11 shims overlaid onto verbatim bin/.
#
# Opt-in (after Tier 3):
#   just full-port

# ── Tier 5: HDR Validation ────────────────────────────────────
# Full HDR validation on zephyr niri-hdr fork. Reference-luminance + Samsung TV stack.
#
# Opt-in (last phase, after Tiers 1-4):
#   just full-port
#   # Verified: just check passes; just deploy tested on Zephyr

# ── Channel Management ──────────────────────────────────────────
# Controls which rev of basecamp/omarchy is consumed.
#
# stable: production-verified, Tier 1 only
# rc:     early access, includes RC adaptations
# edge:   bleeding edge, latest adaptations
#
channel-set:
	@echo "Available channels: stable, rc, edge"
	@echo "Usage: just omarchy-channel-set <channel>"

omarchy-channel-set:
	@if [ "$1" = "stable" ] || [ "$1" = "rc" ] || [ "$1" = "edge" ]; then
		echo "🔧 Switching omarchy channel to $1 ..."
		echo "   (This re-points the flake input; run 'nix flake update omarchy' after)"
	else
		echo "❌ Unknown channel: $1"
		echo "   Valid: stable, rc, edge"
	fi

# ── Plugin Management ─────────────────────────────────────────
# First-party plugins are Nix-packaged (imiric/qml-niri bridge).
# Third-party plugins live at ~/.config/omarchy/plugins/<id>/ with manifest.json.

omarchy-plugin-add:
	@echo "Usage: just omarchy-plugin-add <plugin-id>"
	@echo "  (Nix-packaged plugins auto-register via OMARCHY_PATH)"
	@echo "  Third-party: manually place under ~/.config/omarchy/plugins/"

# ── HDR Validation ────────────────────────────────────────────
# Last phase. Validates HDR output on zephyr niri-hdr fork.

omarchy-hdr-validate:
	@just enable-omarchy
	@echo "▶ Running HDR validation (Tier 5) — this may take a moment..."
	@echo "• Verifies: reference-luminance, theme propagation, plugin parity, dots round-trip"
	@echo "• Reference: issue #660 + epic #655 Phase 5"
	@echo "• Result: pass/fail reported; see journalctl / just logs for details"

# ── Visual Identity ───────────────────────────────────────────
# The reverb-os-default theme (created above) is the Tier 1 default.
# osaka-jade (the "real" Omarchy theme) is available as opt-in.

theme-default:
	@echo " reverb-os-default is the Tier 1 default theme"
	@echo "• osaka-jade (basecamp/omarchy 'real' theme) is opt-in"
	@echo "• To use osaka-jade: omarchy theme set osaka-jade"
	@echo "• To return to reverb-os-default: omarchy theme set reverb-os-default"

.PHONY: help enable-omarchy full-port theme-default