# Per-host multi-monitor output configuration for niri.
# Extracted from modules/home-manager/niri-config.nix on 2026-07-29
# per audit F-22 (de-monolith niri-config.nix mega-module).
#
# `hostName` is injected by home-manager.nix extraSpecialArgs.
#
# DEPLOYMENT-LESSONS.md (§ shared-module-multi-monitor):
#   Zephyr's 4-monitor layout was previously the DEFAULT for all hosts.
#   This file explicitly gates each layout on hostName so headless-ish
#   hosts (sentry, forge) get a generic single-output default, nexus
#   gets HDMI-A-1 4K@60 scale 1.5, and zephyr gets its 4-output grid.
#   Adding a 5th host = add another if/else branch here.
{ config, lib, hostName, ... }:
let niriHmAvailable = config.lib ? niri;
in lib.mkIf niriHmAvailable {
  programs.niri.settings = {
    outputs =
      if hostName == "zephyr" then {
        # Zephyr: 4 monitors (main + secondary + tertiary + TV)
        "DP-5" = {
          mode = {
            width = 1920;
            height = 1080;
            refresh = 144.0;
          };
          position = {
            x = 0;
            y = 349;
          };
          scale = 1.0;
        };
        "DP-4" = {
          mode = {
            width = 1920;
            height = 1080;
            refresh = 75.0;
          };
          position = {
            x = 1920;
            y = 0;
          };
          scale = 1.0;
        };
        "DP-6" = {
          mode = {
            width = 1600;
            height = 900;
            refresh = 60.0;
          };
          position = {
            x = 1920;
            y = 1080;
          };
          scale = 1.0;
        };
        "HDMI-A-2" = {
          mode = {
            width = 3840;
            height = 2160;
            refresh = 60.0;
          };
          position = {
            x = 10000;
            y = 0;
          };
          scale = 1.5;
        };
      } else if hostName == "nexus" then {
        # Nexus: single 4K monitor (3840x2160@60)
        "HDMI-A-1" = {
          mode = {
            width = 3840;
            height = 2160;
            refresh = 60.0;
          };
          position = {
            x = 0;
            y = 0;
          };
          scale = 1.5;
        };
      } else {
        # Sentry/Forge: single 900p monitor, generic scale
        "*" = {
          scale = 1.0;
        };
      };
  };
}
