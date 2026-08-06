{ lib, pkgs, config, ... }:

# System-level alacritty + niri helper wrappers.
#
# These were previously defined in the Home Manager standalone repo's
# niri-config.nix as `home.packages`, but after the Layer-2 HM extraction
# they were never carried into the standalone home.packages and the
# binaries disappeared from zephyr (alacritty would not launch, and the
# niri Mod+Return / Mod+T / Mod+D / Mod+B / Mod+O binds — which call
# `alacritty-oom-safe` / `launch-or-focus` by bare name — silently failed).
#
# They are system-level on purpose: niri spawns children with a PATH that
# includes /run/current-system/sw/bin but NOT the per-user HM profile bin
# dir, so a HM-installed wrapper is not reachable by bare name from a
# niri keybind. Putting both the terminal and the wrappers in
# environment.systemPackages fixes Mod+Enter and the launch-or-focus binds.
#
# launch-or-focus is deliberately NOT defined here: the CORRECT version
# (app_id-based, jq JSON matcher, no orphan-kill loop, systemd service
# preference, focused-window bias) lives in the standalone
# home-manager-config flake at modules/niri-config.nix and is installed
# via home.packages. It lands in /etc/profiles/per-user/<user>/bin which
# IS present in the PATH niri passes to spawned children. The OLD awk/pgrep
# version with orphan-kill caused crashes (fought systemd restart on
# app crash-loop) — DO NOT RE-INTRODUCE.

let
  niriEnabled = config.programs.niri.enable or false;
in
lib.mkIf niriEnabled {
  environment.systemPackages = with pkgs; [
    # The terminal itself.
    alacritty

    # 2026-07-27 OOM emergency (zephyr: 31 GB RAM, persistent pressure from
    # control-plane + gaming + AI + mining). Wrap alacritty in a NEW --user
    # scope under systemd-run so it is a clearly-bounded leaf cgroup with its
    # own caps and OOM-score. The uwsm outer scope may still die, but
    # alacritty's branch terminates cleanly rather than dragging niri or
    # noctalia with it. Mirrors the systemd-run ownership pattern in
    # modules/gaming/gaming.nix (launch-game wrapper).
    (pkgs.writeShellScriptBin "alacritty-oom-safe" ''
      #!/bin/sh
      set -euo pipefail
      if [ "$#" -eq 0 ]; then
        set -- alacritty
      fi
      exec ${pkgs.systemd}/bin/systemd-run --user --scope --collect \
        --property=MemoryHigh=2G \
        --property=MemoryMax=4G \
        --property=OOMPolicy=continue \
        --property=OOMScoreAdjust=-800 \
        -- alacritty "$@"
    '')
  ];
}
