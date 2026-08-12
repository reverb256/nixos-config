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
{ config, lib, pkgs, ... }:
{
  config = {
    systemd.oomd = {
      enable = lib.mkDefault true;
      settings.OOM = {
        MemoryUsedPercent = lib.mkDefault 90;
        SwapUsedPercent   = lib.mkDefault 85;        # percent not raw integer
      };
    };

    # Sysctl tuning is owned by modules/system/vm-tuning.nix (predates this
    # module and is the canonical source for vm.* keys). The previous block
    # here (vm.watermark_scale_factor / vm.page-cluster / vm.vfs_cache_pressure)
    # produced a NixOS "defined multiple times" error against vm-tuning.nix's
    # own mkDefault of the same keys and was removed on 2026-07-27 to
    # unblock the cluster-fix-batch rebuild. Host-specific zram overrides
    # (e.g. zephyr=180 swappiness) remain in vm-tuning.nix.

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

    # 2026-08-11: nix.gc.options only bounds store paths by AGE. It does NOT
    # cap the number of system generations — nexus had accumulated 435 of them
    # (a rebuild every few hours creates a new gen; 30d of churn = hundreds).
    # Add a count-based prune: keep the newest N generations and delete the
    # rest. `nix-env --delete-generations +N` keeps the N most recent.
    # Ordering only (after=, not requires=) so hosts that disable nix.gc still
    # get generation pruning; store paths unrooted here are collected by the
    # next nix-gc run. Uses config.nix.package (the host's actual Nix/Lix).
    systemd.services.nix-gc-prune = {
      description = "Prune old NixOS system generations (keep newest 20)";
      after = ["nix-gc.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +20";
      };
      startAt = "weekly";
    };
  };
}
