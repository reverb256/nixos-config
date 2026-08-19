# btrfs automatic block-group reclaim — fleet-wide ENOSPC prevention.
#
# THE PROBLEM THIS SOLVES
# On a btrfs filesystem holding /nix/store, space is allocated to the filesystem
# in "block groups" (chunks) that are typed Data or Metadata. A chunk allocated
# to Data can never serve Metadata. Over time a write-heavy store allocates
# nearly every chunk as Data, driving `Device unallocated` toward zero. Once
# there is no unallocated space, btrfs cannot create a new Metadata chunk, and
# any operation needing metadata fails with ENOSPC — even though `df` still
# reports tens of GiB free, because that free space sits INSIDE Data chunks.
#
# Measured on this cluster 2026-08-18:
#   nexus : unallocated 1.00MiB, Metadata 38.56/40.50GiB (95%), 50GiB "free"
#   sentry: unallocated 0,       hit a hard outage (1017 ENOSPC events/24h)
#   zephyr: unallocated 0        (latent, same class)
# This is a KNOWN btrfs+Nix interaction; the NixOS discourse thread on it is
# titled "No space on Btrfs although there is plenty of free disk space" and
# reports it occurring specifically on partitions holding /nix/store.
#
# WHY NOT A SCHEDULED BALANCE
# The conventional remedy is a periodic `btrfs balance`. Upstream btrfs
# maintainers advise against scheduling it, and specifically against ever
# balancing METADATA: a metadata balance repacks and REMOVES metadata block
# groups, which is the opposite of what a metadata-starved filesystem needs, and
# can drive the filesystem read-only — a state you cannot balance your way out
# of, because balance requires a writable filesystem. A read-only builder means
# physical recovery. Data-only balance is safe but still needs free workspace,
# which is exactly what is missing once unallocated hits zero.
#
# WHAT THIS DOES INSTEAD
# Kernel-side automatic reclaim. `dynamic_reclaim` lets the kernel return
# lightly-used Data block groups to unallocated on demand, and
# `periodic_reclaim` does so on a periodic sweep. The kernel reclaims when
# unallocated runs low, so unallocated never reaches zero and metadata can
# always grow. This removes the need for scheduled balances entirely and, unlike
# a cron job, cannot fire at a moment when there is no workspace left.
#
# Requires kernel support for the sysfs knobs (present on 7.1.3-cachyos, which
# every host in this fleet runs). The service tolerates their absence so a
# kernel downgrade degrades to a no-op instead of failing activation.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.btrfs-auto-reclaim;
in {
  options.services.btrfs-auto-reclaim = {
    enable =
      lib.mkEnableOption ''
        kernel-side automatic btrfs block-group reclaim, which keeps
        `Device unallocated` above zero so Metadata chunks can always be
        allocated. Prevents the ENOSPC class where df shows free space but
        every write fails
      ''
      // {
        default = true;
      };

    bgReclaimThreshold = lib.mkOption {
      type = lib.types.ints.between 0 100;
      default = 0;
      description = ''
        FIXED reclaim threshold percentage, as an ALTERNATIVE to dynamic reclaim.
        A Data block group whose usage falls below this percent becomes a
        reclaim candidate.

        MUTUALLY EXCLUSIVE with `dynamic`. The kernel refuses a write to
        `bg_reclaim_threshold` with EINVAL while `dynamic_reclaim` is set —
        upstream `btrfs_sinfo_bg_reclaim_threshold_store()` begins with
        `if (READ_ONCE(space_info->dynamic_reclaim)) return -EINVAL;`, and the
        file becomes a read-only view of the current dynamic threshold. Setting
        both is therefore not a "belt and braces" configuration; it is a
        guaranteed failed write.

        Leave at 0 and keep `dynamic = true` unless you have measured evidence
        that a fixed threshold suits this host better. Upstream experience at
        scale found a fixed threshold either works perfectly or falls apart
        depending on the value, and a workload that oscillates around it causes
        unbounded reclaim churn; a fixed 30 produced ~150 reclaims/day/host
        versus ~5/day with dynamic.

        Only consulted when `dynamic = false`.
      '';
    };

    dynamic = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Use the kernel's DYNAMIC reclaim threshold instead of a fixed percentage.

        The dynamic threshold targets a fixed amount of unallocated space
        (upstream: ~10 block-group-sized chunks) and scales its aggression
        linearly as unallocated falls below that target — no reclaim while
        unallocated is healthy, progressively harder as it trends toward zero.
        That is precisely the failure mode this fleet hit: eager Data allocation
        starving Metadata until no chunk could be created.

        This is the recommended setting and excludes `bgReclaimThreshold`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.btrfs-auto-reclaim = {
      description = "Enable btrfs dynamic + periodic block-group reclaim";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Writes only to /sys/fs/btrfs. Everything else stays read-only so a
        # bug here cannot touch the store or host state.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateNetwork = true;
        ReadWritePaths = ["/sys/fs/btrfs"];
        NoNewPrivileges = true;
      };

      script = ''
        set -u
        shopt -s nullglob

        found=0
        for data in /sys/fs/btrfs/*/allocation/data; do
          fsid="$(basename "$(dirname "$(dirname "$data")")")"
          found=1

          # ORDER MATTERS. The kernel rejects a write to bg_reclaim_threshold
          # with EINVAL while dynamic_reclaim is set, so the fixed threshold
          # must be written FIRST (and only when dynamic is off).
          ${
          if cfg.dynamic
          then ''
            # Dynamic threshold: the kernel computes the reclaim aggression from
            # how far unallocated has fallen below its target. bg_reclaim_threshold
            # is deliberately NOT written — it is read-only in this mode.
            for knob in dynamic_reclaim periodic_reclaim; do
              if [ -w "$data/$knob" ]; then
                if echo 1 > "$data/$knob" 2>/dev/null; then
                  echo "$fsid: $knob = 1"
                else
                  echo "$fsid: $knob present but write failed" >&2
                fi
              else
                echo "$fsid: $knob unavailable on this kernel — skipping"
              fi
            done
          ''
          else ''
            # Fixed threshold mode: ensure dynamic is OFF first so the
            # bg_reclaim_threshold write is accepted, then set the value.
            if [ -w "$data/dynamic_reclaim" ]; then
              echo 0 > "$data/dynamic_reclaim" 2>/dev/null \
                && echo "$fsid: dynamic_reclaim = 0 (fixed-threshold mode)"
            fi

            if [ -w "$data/bg_reclaim_threshold" ]; then
              echo ${toString cfg.bgReclaimThreshold} > "$data/bg_reclaim_threshold" 2>/dev/null \
                && echo "$fsid: bg_reclaim_threshold = ${toString cfg.bgReclaimThreshold}" \
                || echo "$fsid: bg_reclaim_threshold write failed" >&2
            else
              echo "$fsid: bg_reclaim_threshold unavailable — skipping"
            fi

            # Periodic sweep still applies to a fixed threshold.
            if [ -w "$data/periodic_reclaim" ]; then
              echo 1 > "$data/periodic_reclaim" 2>/dev/null \
                && echo "$fsid: periodic_reclaim = 1"
            fi
          ''
        }
        done

        if [ "$found" -eq 0 ]; then
          echo "no btrfs filesystems found under /sys/fs/btrfs — nothing to do"
        fi
      '';

      path = [pkgs.coreutils];
    };
  };
}
