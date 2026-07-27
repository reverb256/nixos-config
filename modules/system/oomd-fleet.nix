# ─────────────────────────────────────────────────────────────────────────────
# oomd-fleet — fleet-wide memory-pressure + trim + nix-gc scheduling.
#
# Replaces the broken per-host oomd block on zephyr (which wrote the obsolete
# NixOS 25.x keys MemoryUsedLimit/SwapUsedLimit=integer). NixOS 26.11 expects
#   * settings.OOM.MemoryUsedPercent = N       (integer percent 0..100)
#   * settings.OOM.SwapUsedPercent   = N       (same)
# Bare integers under the legacy key names are parsed-as-bad and silently
# ignored, which produced the "Failed to parse SwapUsedLimit=90, ignoring"
# journal noise that the audit captured.
#
# Loaded once via common-modules-list.nix; lib.mkDefault on every value so
# host configs that need a tighter ceiling (e.g. forge's mining slice capping
# at MemoryUsedPercent=80) can still win.
# ─────────────────────────────────────────────────────────────────────────────
{ config, lib, ... }:
{
  config = {
    systemd.oomd = {
      enable = lib.mkDefault true;
      settings.OOM = {
        MemoryUsedPercent = lib.mkDefault 90;
        SwapUsedPercent   = lib.mkDefault 85;        # percent not raw integer
      };
    };

    # Fleet-wide VM tuning for in-memory swap (zramOnly). mkDefault so hosts
    # that want to push swappiness higher (zephyr does 180) can still do so.
    # Obsolete keys vm.extra_free_kbytes / vm/page-cache-limit were REMOVED
    # from the upstream kernel (6.10 / 5.15 respectively); systemd-sysctl
    # will log a benign "Failed to write" for any host that still tries to
    # set them — they will not break boot.
    boot.kernel.sysctl = {
      "vm.watermark_scale_factor" = lib.mkDefault 200;
      "vm.page-cluster"            = lib.mkDefault 0;
      "vm.vfs_cache_pressure"      = lib.mkDefault 50;
    };

    # fstrim was running per-boot on zephyr (20m 35s!). Switch to weekly.
    services.fstrim = {
      enable   = lib.mkDefault true;
      interval = lib.mkDefault "weekly";
    };

    # nix.gc was running per-boot on every host (3-4 minutes each). Switch
    # to weekly +30d cutoff to keep stable store backpressure without
    # blocking boot.
    nix.gc = {
      automatic = lib.mkDefault true;
      dates      = lib.mkDefault "weekly";
      options    = lib.mkDefault "--delete-older-than 30d";
    };
  };
}
