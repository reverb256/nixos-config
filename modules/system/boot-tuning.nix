{ lib, ... }:

# OMARCHY-inspired boot speed tuning (2026-08-18).
#
# Lessons ported from the OMARCHY boot model + NixOS/systemd best practices
# (Discourse "Boot faster by disabling udev-settle", NixOS wiki, Framework
# boot writeup, systemd OPTIMIZATIONS doc):
#
#   1. Don't wait on the bootloader. systemd-boot holds its timeout
#      (default 5s) for generation select; timeout=0 skips it. Spacebar
#      still opens the menu.
#   2. Quiet console is cosmetic on modern NixOS, but cuts boot spam on a
#      desktop (niri) host for a cleaner handoff. Use the idiomatic option.
#   3. Maintenance (systemd-tmpfiles-clean) is a daily TIMER, NOT on the
#      boot critical path. Keep journald bounded so /var can't OOM or fill.
#   4. Network-dependent user services stay off the boot gate (already done
#      for opencode + k3s-CDI-generator in PR #666).

{
  # Skip the 5s systemd-boot generation-select wait. Spacebar opens the menu.
  boot.loader.timeout = 0;

  # Quiet console: fewer boot messages, cleaner niri handoff.
  boot.consoleLogLevel = 3;

  # Bounded journald: cap disk use, keep logs for debugging.
  services.journald.systemMaxUse = "200M";
  services.journald.maxLevelStore = "info";
}
