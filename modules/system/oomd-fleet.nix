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
{
  config,
  lib,
  ...
}: {
  config = {
    systemd.oomd = {
      enable = lib.mkDefault true;
      settings.OOM = {
        # systemd-oomd (>=261) has NO MemoryUsedPercent key — memory is
        # governed by PSI via DefaultMemoryPressureLimit (default 60%).
        # SwapUsedPercent is likewise not a key; the swap/memory threshold is
        # SwapUsedLimit (fires when memory-used AND swap-used both exceed it).
        SwapUsedLimit = lib.mkDefault "85%";
      };
    };

    # systemd-oomd reads /etc/systemd/oomd.conf ONLY at startup; a deploy
    # rewrites the file but the running daemon keeps the previous limits
    # (2026-08-15 audit: SwapUsedLimit=85% was on disk but nexus/forge/sentry
    # daemons still enforced the old defaults). Restart the daemon whenever
    # the generated config changes so OOM settings go live at switch time,
    # not at the next boot. Upstream oomd.nix sets wantedBy on this service;
    # adding restartTriggers merges with that definition.
    systemd.services.systemd-oomd.restartTriggers = [
      config.environment.etc."systemd/oomd.conf".source
    ];

    # Sysctl tuning is owned by modules/system/vm-tuning.nix (predates this
    # module and is the canonical source for vm.* keys). The previous block
    # here (vm.watermark_scale_factor / vm.page-cluster / vm.vfs_cache_pressure)
    # produced a NixOS "defined multiple times" error against vm-tuning.nix's
    # own mkDefault of the same keys and was removed on 2026-07-27 to
    # unblock the cluster-fix-batch rebuild. Host-specific zram overrides
    # (e.g. zephyr=180 swappiness) remain in vm-tuning.nix.

    # fstrim was running per-boot on zephyr (20m 35s!). Switch to weekly.
    services.fstrim = {
      enable = lib.mkDefault true;
      interval = lib.mkDefault "weekly";
    };

    # nix.gc was running per-boot on every host (3-4 minutes each). Switch
    # to weekly +30d cutoff to keep stable store backpressure without
    # blocking boot.
    nix.gc = {
      automatic = lib.mkDefault true;
      dates = lib.mkDefault "weekly";
      options = lib.mkDefault "--delete-older-than 30d";
    };

    # 2026-08-18: nix-gc.timer was `enabled` + `active` on nexus yet
    # ExecMainExitTimestamp was EMPTY — it had NEVER executed. Its last window
    # (Aug 17) was missed and simply dropped, next was Aug 24. Meanwhile 89,402
    # dead store paths accumulated uncollected, which is what drove btrfs
    # Metadata to 38.57/40.50GiB and `Device unallocated` to 1.00MiB on the
    # builder. Retained generations were NOT involved: nexus held exactly 20,
    # the policy below, already satisfied.
    #
    # Persistent=true makes a missed weekly window run at the next opportunity
    # instead of being skipped. On a builder that is busy or rebooting at the
    # trigger moment, that is the difference between GC running and never
    # running at all.
    systemd.timers.nix-gc = {
      timerConfig = {
        Persistent = true;
        # Stagger across the fleet: four hosts GC'ing simultaneously all churn
        # metadata at once, which is the pressure we are trying to relieve.
        RandomizedDelaySec = "45m";
      };
    };

    # 2026-08-11: nix.gc.options only bounds store paths by AGE. It does NOT
    # cap the number of system generations — nexus had accumulated 435 of them
    # (a rebuild every few hours creates a new gen; 30d of churn = hundreds).
    # Add a count-based prune: keep the newest N generations and delete the
    # rest. `nix-env --delete-generations +N` keeps the N most recent.
    # Ordering only (after=, not requires=) so hosts that disable nix.gc still
    # get generation pruning; store paths unrooted here are collected by the
    # next nix-gc run. Uses config.nix.package (the host's actual Nix/Lix).
    #
    # 2026-08-18 — THIS NEVER RAN EITHER. `systemctl is-enabled nix-gc-prune`
    # reported `linked` and ExecMainExitTimestamp was EMPTY. Two defects, both
    # fixed below:
    #   1. startAt= alone did not get the timer installed into a target, so it
    #      never fired. wantedBy=timers.target fixes that.
    #   2. Persistent was false, so a missed weekly window was dropped rather
    #      than caught up. On a builder that is exactly when it gets missed.
    # SCOPE NOTE: the +20 policy here was already being honoured — nexus held
    # exactly 20 generations. Generation retention did NOT cause the ENOSPC
    # incident; nix-gc never running did (see the nix-gc timer note above).
    # This unit is still worth fixing so the cap keeps holding unattended.
    # PITFALL: the prune ABORTS on a malformed generation link. nexus carried a
    # `system-365-link.bad` (a FORGE closure left by a misfired deploy) and
    # nix-env stopped with "cannot unlink ... No such file or directory" without
    # pruning anything. If this unit reports that, move the offending `*.bad`
    # link out of /nix/var/nix/profiles and re-run.
    systemd.services.nix-gc-prune = {
      description = "Prune old NixOS system generations (keep newest 20)";
      after = ["nix-gc.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +20";
      };
      startAt = "weekly";
    };

    # Make the generated timer actually install and catch up missed windows.
    # Without these the unit is `linked` but never fires (see defect 1 + 2 above).
    systemd.timers.nix-gc-prune = {
      wantedBy = ["timers.target"];
      timerConfig = {
        Persistent = true;
        # Spread the fleet so four hosts do not all churn metadata at once.
        RandomizedDelaySec = "30m";
      };
    };
  };
}
