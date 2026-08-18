{ lib, ... }:

# OMARCHY-inspired boot speed tuning (2026-08-18).
#
# Lessons ported from the OMARCHY boot model + NixOS/systemd best practices
# (Discourse "Boot faster by disabling udev-settle", Framework boot-speed
# writeup, NixOS Plymouth wiki):
#
#   1. Don't wait on the bootloader. systemd-boot holds 5s for generation
#      select by default; timeout=0 skips it (spacebar still opens the menu).
#   2. Quiet console is cosmetic (no measured speed gain) but reduces boot
#      spam on a desktop (niri) host. Use the idiomatic NixOS option.
#   3. Maintenance (systemd-tmpfiles-clean) is a TIMER (Before=shutdown.target),
#      NOT on the boot critical path. Do not pull it into boot. The earlier
#      1min14s clean stall was a one-off huge /tmp (build extracts), resolved
#      by nix-collect-garbage. Keep journald bounded so it can't OOM /var.
#   4. Network-dependent user services stay off the boot gate (already done for
#      opencode + k3s-CDI-generator in PR #666).
#
# Every setting here is non-fatal and reversible. Nothing disables a security
# boundary.

{
  # Skip the 5s systemd-boot generation-select wait. Spacebar opens the menu.
  boot.loader.timeout = 0;

  # Quiet console (cosmetic): fewer boot messages, cleaner niri handoff.
  consoleLogLevel = 3;

  # Bounded journald: cap disk use, keep logs for debugging (auto = persist).
  services.journald.extraConfig = """
    SystemMaxUse=200M
    MaxLevelStore=info
  """;
}
