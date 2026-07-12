# krash3-vm — C: Drive Speed Fix (Full Execution Plan)

> **Status:** PLAN ONLY — not executed. Requires user-approved maintenance window.
> **Author:** Hermes | **Date:** 2026-07-11
> **Grounded in:** live host evidence collected 2026-07-10/11 (see "Evidence" below).

## Problem Statement

C: (Windows system disk) is a **700 GB file `c.raw`** on btrfs at
`/var/lib/libvirt/images`. The NOCOW (`+C`) flag is **NOT** set on it
(`lsattr` returned empty), so every write goes through btrfs
**copy-on-write**. Measured earlier this session: C: write **351 MB/s**,
read 839 MB/s, while the NVMe is capable of 1–3 GB/s. That COW penalty is
why C: feels "SO slow".

Root cause of the *crash* (separate, already fixed 2026-07-10): the live
domain XML had drifted to include `<qemu:del capability='usb-host.hostdevice'/>`
+ a malformed `usb-host hostdevice=/dev/bus/usb/001/002`, causing
`usbfs: ... did not claim interface 1 before use` and freezing the guest.
The clean declarative source is now deployed; qemu-ga 110.0.2 confirmed
connected. This plan is ONLY the C: speed fix.

## Evidence (collected, not assumed)

- `c.raw` size: 751619276800 bytes (~700 GB). Present and writable.
- `lsattr /var/lib/libvirt/images/c.raw` → empty (NOCOW NOT applied).
- Root fs `/` (btrfs, nvme0n1p2): 954G total, 768G used, **183G free (81%)**.
  → Cannot re-seed 700 GB c.raw onto RAID (old plan's blocker).
- RAID `md0`: raid0 over loop0/loop1 (sda/sdb, offset 1069056 sectors =
  547356672 bytes). Total **1999315009536 bytes (~1.999 TB)**.
- `md0p1` (Games/E:): **1999297839104 bytes (~1.999 TB)**, NTFS, LABEL "Games",
  UUID 1E24837E24835823, **currently EMPTY** (measured empty earlier this session).
- `assemble-games-raid` service: `mdadm --build` (no persistent superblock) →
  if `! -b /dev/md0p1`, writes GPT label + one NTFS part via sfdisk. So md0p1
  is the ONLY partition today; adding md0p2 is a host-side `parted` change.
- VM currently RUNNING and HEALTHY on the corrected definition (qemu-ga 110.0.2).

## Approach (why this, not the old re-seed)

Move C: onto the games RAID as a **raw block disk** (`md0p2` → `vdc`),
boot order 1. Raw block = no btrfs COW = full NVMe/RAID speed (same class
as E:, which measured 543/981 MB/s raw). This **avoids the 700 GB re-seed**
that root-fs free space makes impossible. c.raw is KEPT (not deleted) for
rollback — fully reversible.

md0p2 size proposed: **~700 GB** (md0p1 shrinks 1.999 TB → ~1.27 TB;
E: is empty so no data loss). Adjust if Windows needs more.

## Declarative Changes (the source-of-truth edits)

### Change 1 — `hosts/krash3/params.nix` (`vm.disks`)
Replace the disks list so md0p2 is the C: boot disk (`vdc`) and c.raw is
commented (kept for rollback). Current list (lines 58–79) becomes:

```nix
  disks = [
    {
      # NEW C: on RAID raw block — fixes btrfs COW slowness.
      type = "block";
      target = "vdc";
      source = "/dev/md0p2";
      bootOrder = 1;
      iothread = 1;
      cache = "none";
    }
    {
      # E: games volume (whole GPT RAID).
      type = "block";
      target = "vdb";
      source = "/dev/md0";
      cache = "none";
    }
    # ROLLBACK: uncomment, set bootOrder=1, comment vdc above.
    # { type = "virtio-file"; target = "vda";
    #   source = "/var/lib/libvirt/images/c.raw";
    #   bootOrder = 1; iothread = 1; cache = "writeback"; }
  ];
```

### Change 2 — `hosts/krash3/hardware.nix` (`assemble-games-raid`)
The service currently creates md0p1 only if absent. We must make it also
create md0p2 (idempotent) so the partition survives reboots. Insert after
the md0p1 creation block (after line 79), guarded so it runs once:

```nix
      # Create md0p2 (C: scratch/Raid disk) once, non-destructively.
      # md0p1 is shrunk by the operator BEFORE deploy (see Runbook B0);
      # here we just ensure the partition exists if space allows.
      if [ ! -b /dev/md0p2 ]; then
        # Only create if md0p1 already ends before ~1.27T (operator pre-shrank).
        end1=$(sfdisk --list /dev/md0 2>/dev/null | awk '/md0p1/{print $3}')
        if [ -n "$end1" ]; then
          printf ',,L\n' | sfdisk --append /dev/md0 2>/dev/null || true
        fi
      fi
```

NOTE: `--append` adds a new partition using remaining free space. Safe only
after md0p1 is shrunk. The operator MUST shrink md0p1 first (Runbook B0).

### Change 3 — `hosts/krash3/services.nix` (no change needed for C: speed,
but confirm e-drive-watchdog still passes D: or E: — already done 2026-07-10).
The watchdog now accepts either letter, so md0p2 (C:) and md0 (E:/D:) coexist
fine.

## Runbook (execution sequence — DO NOT RUN until window approved)

All commands are host-side on krash3 via `ssh j_kro@10.1.1.150`. Wrap in
`sh -c '...'` (fish shell). Avoid `(` in inline echo.

### Phase 0 — Pre-flight (VM running, read-only)
```
ssh krash3: virsh domstate krash3-vm          # expect running
ssh krash3: sudo lsblk -b /dev/md0 /dev/md0p1  # confirm sizes
ssh krash3: sudo virsh qemu-agent-command krash3-vm --cmd "$(printf '{"execute":"guest-ping"}')"
```

### Phase 1 — Stop VM + shrink E: (md0p1)
```
ssh krash3: sudo virsh shutdown krash3-vm --mode acpi
# wait until `virsh domstate` = shut off (poll)
ssh krash3: sudo ntfsresize --size 1270G /dev/md0p1
ssh krash3: sudo parted /dev/md0 resizepart 1 1270GB
ssh krash3: sudo parted /dev/md0 mkpart primary 1270GB 100%
ssh krash3: sudo partprobe /dev/md0
ssh krash3: sudo lsblk /dev/md0      # expect md0p1 (1.27T) + md0p2 (~700G)
```
Risk: shrinking NTFS. E: is EMPTY so no data loss, but ensure ntfsresize
succeeds before mkpart. If ntfsresize fails → abort, leave md0p1 intact.

### Phase 2 — Deploy declarative changes (zephyr)
```
cd /etc/nixos
# apply Change 1 + Change 2 to params.nix + hardware.nix
git add hosts/krash3/params.nix hosts/krash3/hardware.nix
git commit -m "krash3: C: on RAID md0p2 raw block (reversible, c.raw kept)"
git push origin main
colmena apply --on krash3
```
The deploy's `assemble-games-raid` will ensure md0p2 exists (idempotent).
Verify: `ssh krash3: ls -l /dev/md0p2`.

### Phase 3 — Install/restore Windows into md0p2 (guest-side)
```
ssh krash3: sudo virsh start krash3-vm
# Boot Windows ISO (virtio drivers) OR restore from backup into vdc.
# If fresh install: install to the new raw disk (vdc), NOT c.raw.
```
Open question for user: **backup restore vs fresh install?** (see Q1)

### Phase 4 — Verify speed + health
```
guest PS: Get-Volume | ? FileSystem -eq NTFS | % { "$($_.DriveLetter):$($_.HealthStatus)" }
# expect C: Healthy (on vdc), D:/E: Healthy (on md0)
guest PS: Test-FileCopy speed or use DiskSpd on C: → expect ≥ 500 MB/s write.
```
Compare to old 351 MB/s. If ≥ 500 MB/s → success.

### Phase 5 — Rollback (if needed, anytime)
- Comment `vdc` entry in params.nix, uncomment c.raw (bootOrder 1), redeploy,
  restart VM. c.raw was never deleted. md0p2 can be left or wiped later.

## Open Questions (need user answers before Phase 3)
- **Q1:** Windows backup to restore into md0p2, or fresh reinstall?
  (Temporary intent from 2026-07-10 suggests fresh install + validate, then decide.)
- **Q2:** md0p2 size — plan assumes ~700 GB. Enough for the Windows install + apps/games?
- **Q3:** When is the maintenance window? Recommend bundling with a future
  host reboot (Track D) so BT also re-binds, minimizing disruption.

## Risks
- Shrinking NTFS (Phase 1) carries small risk even when empty — verify ntfsresize OK.
- md0 is RAID0 (sda+sdb) — single disk failure loses C: AND E:. Same as today.
- Raw block trades btrfs checksum/COW integrity on C: for speed — fine for a game VM.
- Root-fs space reclaim (delete c.raw) DEFERRED until user confirms permanent.
- Host reboot (Track D) kills krash3 mining temporarily — bundle windows.

## Success Criteria
- C: boots from md0p2 (vdc), Healthy.
- C: write ≥ 500 MB/s (vs 351 MB/s before).
- E:/D: still Healthy on md0.
- c.raw preserved (rollback possible).
- No config drift — all state in /etc/nixos, deployed via colmena.
