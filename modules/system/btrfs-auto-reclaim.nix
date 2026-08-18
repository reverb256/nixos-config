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
        Optional `bg_reclaim_threshold` percentage. A Data block group whose
        usage falls below this percent becomes a reclaim candidate.

        0 means "leave the kernel default alone", which is the conservative
        choice: reclaim still happens via dynamic/periodic reclaim, just at the
        kernel's own thresholds. Raise it only with evidence, since aggressive
        reclaim means more background rewriting and more SSD wear.
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

          # Each knob is written independently and guarded: a kernel without
          # one of them must not abort the whole unit.
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

          ${lib.optionalString (cfg.bgReclaimThreshold > 0) ''
          if [ -w "$data/bg_reclaim_threshold" ]; then
            echo ${toString cfg.bgReclaimThreshold} > "$data/bg_reclaim_threshold" 2>/dev/null \
              && echo "$fsid: bg_reclaim_threshold = ${toString cfg.bgReclaimThreshold}" \
              || echo "$fsid: bg_reclaim_threshold write failed" >&2
          fi
        ''}
        done

        if [ "$found" -eq 0 ]; then
          echo "no btrfs filesystems found under /sys/fs/btrfs — nothing to do"
        fi
      '';

      path = [pkgs.coreutils];
    };
  };
}
