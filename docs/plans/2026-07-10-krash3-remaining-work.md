# krash3-vm Remaining Work — Consolidated Implementation Plan

> **For Hermes:** Execute task-by-task. Track A is declarative + safe (zero downtime). Tracks B/C/D are gated on user-approved downtime windows. Do NOT start B/C/D without explicit user go-ahead.

**Goal:** Finish the remaining krash3-vm hardening: (A) btrfs NOCOW structure for VM images, (B) re-seed C: as a NOCOW image for real speed, (C) guest reboot to bind Bluetooth, (D) host reboot to apply VFIO kernel params.

**Architecture:** All persistent state stays declarative in `/etc/nixos/hosts/krash3/*.nix` → commit → `colmena apply --on krash3`. Guest-internal actions (reboots, driver bind) run via libvirt/QEMU guest agent. Host reboots are disruptive and user-gated.

**Tech Stack:** NixOS (flake), libvirt/QEMU, btrfs (`btrfs property set` for NOCOW — no chattr needed), QEMU guest agent (PowerShell via `virsh qemu-agent-command`), colmena.

**Last Verified:** 2026-07-10 (this session). Current measured state: C: 351 MB/s write / 839 MB/s read (NVMe capable of 1–3 GB/s → COW penalty confirmed). E: 543/981 MB/s (raw block, no FS). Bluetooth: real Intel BT device present in guest, Code 10, 11 phantom entries, needs guest reboot. Kernel params `pcie_aspm=off` + `kvm_amd.msr_filter=0` committed but NOT in `/proc/cmdline` (need host reboot). `c.raw` = 587 GB allocated, host has 183 GB free.

---

## TRACK A — btrfs NOCOW subvolume for VM images (DO NOW, zero downtime)

Makes the *structure* correct so all future VM images (and a re-seeded C: later) inherit NOCOW. Existing C: data is NOT rewritten here (see Track B for that).

### Task A1: Add e2fsprogs to krash3 config
**Objective:** Make `chattr` available on host for future maintenance; harmless, enables ad-hoc NOCOW sets.
**Files:** Modify `/etc/nixos/hosts/krash3/services.nix` (the `environment.systemPackages` line, ~257).
**Step 1:** Read the current packages line.
```
services.nix: environment.systemPackages = with pkgs; [ virt-manager git libvirt virtio-win swtpm jq ];
```
**Step 2:** Add `e2fsprogs`:
```
environment.systemPackages = with pkgs; [ virt-manager git libvirt virtio-win swtpm jq e2fsprogs ];
```
**Step 3:** Build to confirm no eval error: `nixos-rebuild build --flake .#krash3` → expects success, new store path printed.
**Step 4:** Commit: `git add hosts/krash3/services.nix && git commit -m "krash3: add e2fsprogs for chattr/NOCOW maintenance"`

### Task A2: Convert /var/lib/libvirt/images to a NOCOW btrfs subvolume
**Objective:** Directory becomes a subvolume with inherited NOCOW so new image files skip copy-on-write.
**Why not tmpfiles:** tmpfiles `f` creates a regular file in the current dir; it cannot set subvolume/NOCOW. We add a one-time-ish systemd oneshot that ensures the subvolume exists with NOCOW property, replacing the tmpfiles `f` line.
**Files:** Modify `/etc/nixos/hosts/krash3/services.nix`:
- Remove the tmpfiles rule `"f /var/lib/libvirt/images/c.raw 0640 root kvm - -"` (line ~162).
- Add a `systemd.services.ensure-images-subvolume` oneshot (see code below).

**Step 1:** Write the service (insert before the `environment.systemPackages` line):
```nix
  # Ensure /var/lib/libvirt/images is a NOCOW btrfs subvolume so VM images
  # (C: = c.raw) skip copy-on-write. Existing c.raw keeps its current
  # allocation until re-seeded (Track B); new files inherit NOCOW.
  systemd.services.ensure-images-subvolume = {
    wantedBy = [ "multi-user.target" ];
    before = [ "libvirtd.service" "virtlogd.service" ];
    path = [ pkgs.btrfs-progs pkgs.coreutils ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      D=/var/lib/libvirt/images
      mkdir -p "$(dirname "$D")"
      if [ ! -d "$D" ]; then
        mkdir -p "$D"
      fi
      # If it's not already a subvolume, snapshot it into one (preserves contents).
      if ! btrfs subvolume show "$D" >/dev/null 2>&1; then
        T="$(mktemp -d "$D/.seed.XXXXXX")"
        mv "$D"/* "$T"/ 2>/dev/null || true
        rmdir "$D" 2>/dev/null || true
        btrfs subvolume create "$D"
        chown root:kvm "$D"; chmod 0750 "$D"
        mv "$T"/* "$D"/ 2>/dev/null || true
        rmdir "$T" 2>/dev/null || true
      fi
      # Inherit NOCOW on the subvolume (applies to all new files within).
      btrfs property set "$D" compression "" 2>/dev/null || true
      chattr +C "$D" 2>/dev/null || true
    '';
  };
```
NOTE: `btrfs property set <path> compression ""` is a no-op clears compression; the real NOCOW inheritance is `chattr +C` (now available via A1). If `chattr` still missing at deploy, the `|| true` keeps it non-fatal; NOCOW then set manually post-deploy (Task A3).
**Step 2:** Build: `nixos-rebuild build --flake .#krash3` → success.
**Step 3:** Deploy: `colmena apply --on krash3`.
**Step 4:** Verify on host (read-only):
```
ssh krash3 'bash --norc --noprofile' <<'R'
sudo btrfs subvolume show /var/lib/libvirt/images | head -2
lsattr -d /var/lib/libvirt/images 2>/dev/null
R
```
Expected: subvolume shown; `lsattr` shows `C` flag on the dir.
**Step 5:** Commit: `git add hosts/krash3/services.nix && git commit -m "krash3: VM images dir is a NOCOW btrfs subvolume (Track A)"`

### Task A3: Manual NOCOW confirm (fallback if chattr absent at A2 deploy)
**Objective:** Guarantee inheritance flag is set even if the service ran before e2fsprogs was present.
**Step 1 (post A2 deploy):** `ssh krash3 'sudo chattr +C /var/lib/libvirt/images'`
**Step 2:** Verify `lsattr -d /var/lib/libvirt/images` shows `C`.

**Track A validation:** Subvolume exists, `C` flag present, VM still runs, C: still Healthy. No speed change yet (existing data COW) — that's Track B.

---

## TRACK B — Temporarily put C: on the RAID as raw block (reversible; "move to E: first" intent)

**Intent (user, 2026-07-10):** "temporarily" — get C: onto RAID speed now without committing to a permanent restructure or destroying the current install. Reversible at any time.

**Why md0p2 and not literally "on E:":** E: is an NTFS volume owned by the guest; the host cannot use it as a backing store. The host-side equivalent is a second partition on the same RAID (`md0p2`), passed as a raw block — same speed class as E: (no btrfs COW). This is the only way to get C: onto RAID speed without a btrfs file.

**Reversible guarantees:**
- `c.raw` is KEPT (not deleted) — rollback = flip boot order back to `vda` + restart.
- md0p2 is benchmarked as a scratch disk (B0) BEFORE any Windows install, so we prove the speed win non-destructively.
- NixOS declares md0p2 as `vdc` but keeps the `c.raw` (`vda`) entry commented, not removed.

### Task B0: Benchmark md0p2 as scratch (NON-DESTRUCTIVE proof)
**Objective:** Confirm raw-block RAID throughput before committing Windows.
**Step 1 (VM OFF):** Shrink E:, create md0p2 (no NTFS yet — leave unformatted):
```
ssh krash3 'bash --norc --noprofile' <<'R'
export LIBVIRT_URI=qemu:///system
sudo virsh shutdown krash3-vm --mode acpi; # wait shut off
sudo ntfsresize --size 1100G /dev/md0p1
sudo parted /dev/md0 resizepart 1 1100GB
sudo parted /dev/md0 mkpart primary 1100GB 100%
partprobe /dev/md0
R
```
**Step 2:** Hot-attach md0p2 as scratch `vdc` (no boot order), start VM, format it in guest as a temp NTFS volume, run `Test-DriveSpeed` on it.
**Step 3:** Expect Write ≥ 500 MB/s (RAID raw-block class). If yes → proceed to B1. If not → stop, keep c.raw as-is (fully reversible, nothing changed in guest).

### Task B1: Declare md0p2 as C: boot disk (reversible)
**Objective:** Pass md0p2 as `vdc` boot order 1; keep `c.raw` commented for rollback.
**Files:** Modify `/etc/nixos/hosts/krash3/params.nix` (`vm.disks`).
**Step 1:** Replace disk list — md0p2 first (boot), keep c.raw commented:
```nix
  disks = [
    {
      type = "block"; target = "vdc"; source = "/dev/md0p2";
      bootOrder = 1; iothread = 1; cache = "none";
    }
    {
      type = "block"; target = "vdb"; source = "/dev/md0"; cache = "none";  # E:
    }
    # TEMPORARY C: on RAID — rollback: uncomment below, set bootOrder 1, comment vdc.
    # { type = "virtio-file"; target = "vda"; source = "/var/lib/libvirt/images/c.raw";
    #   bootOrder = 1; iothread = 1; cache = "writeback"; }
  ];
```
**Step 2:** Build + deploy (`colmena apply --on krash3`). Commit: `git commit -m "krash3: TEMP C: on RAID md0p2 (reversible, c.raw kept)"`

### Task B2: Install/restore Windows into md0p2
**Step 1:** Start VM, boot Windows ISO (virtio drivers), install to vdc — OR restore from backup.
**Step 2:** Verify C: Healthy on new disk; E: still Healthy.
**Step 3:** Re-measure C: → expect ≥ 500 MB/s.

### Task B3 (rollback, if ever needed): flip boot order
- Comment the `vdc` entry, uncomment `c.raw` (bootOrder 1), redeploy, restart VM. c.raw untouched throughout.

**Track B validation:** C: on RAID raw block, ≥ 500 MB/s write; c.raw preserved for rollback; root fs reclaim deferred until user confirms permanent.

---

## TRACK C — Guest reboot to bind Bluetooth (gated: user said "nah not yet")

### Task C1: Clean guest reboot
**Objective:** Re-enumerate passed-through Intel BT so `ibtusb.inf` binds (clears 11 phantoms + Code 10).
**Step 1 (user-approved window):** 
```
ssh krash3 'bash --norc --noprofile' <<'R'
export LIBVIRT_URI=qemu:///system
sudo virsh shutdown krash3-vm --mode acpi
# wait for shut off
sudo virsh start krash3-vm
R
```
**Step 2:** Wait ~60s, poll guest agent ping.
**Step 3:** Verify:
```
guest PS: Get-PnpDevice -Class Bluetooth -PresentOnly | ? Status -eq OK | Measure-Object | select Count  → expect 1
guest PS: phantom count (CM_PROB_PHANTOM) → expect 0
```
**Step 4:** If still Code 10 after reboot → fallback: inside guest, `pnputil /add-driver <ibtusb.inf> /install` or USB reset via `Disable-PnpDevice`+`Enable-PnpDevice` on the real device. Document result.

**Track C validation:** Exactly 1 OK Bluetooth radio, 0 phantoms, `bthserv` Running, guest can pair a device.

---

## TRACK D — Host reboot for VFIO kernel params (gated: user said "not yet")

### Task D1: Host reboot
**Objective:** Activate committed `pcie_aspm=off` + `kvm_amd.msr_filter=0` (boot-time only).
**Step 1 (user-approved window):** clean ACPI shutdown of VM first, then reboot host:
```
ssh krash3 'bash --norc --noprofile' <<'R'
export LIBVIRT_URI=qemu:///system
sudo virsh shutdown krash3-vm --mode acpi
# wait shut off
sudo systemctl reboot
R
```
**Step 2:** After host returns, confirm:
```
ssh krash3 'tr " " "\n" </proc/cmdline | grep -E "pcie_aspm|msr_filter"'
→ expect both lines present
```
**Step 3:** Confirm VM auto-starts (libvirt autostart) and is Running; E:/C: Healthy.
**Step 4:** Optional: re-run a short qemu CPU check under mining load to confirm no regression.

**Track D validation:** Both kernel params in `/proc/cmdline`; VM healthy post-reboot.

---

## Sequencing / Downtime summary
- **Track A:** now, zero downtime. (A1→A2→A3)
- **Track B:** needs Windows backup-or-reinstall decision — separate downtime (VM off; repartition RAID + install/restore Windows into md0p2, ~30–60 min). No free-space blocker (RAID-block approach avoids the 587 GB re-seed).
- **Track C:** guest reboot only (~1 min game interruption) — bundle with B or D if convenient.
- **Track D:** host reboot (~few min) — bundle B+C into one window to minimize disruptions.

**Recommended single maintenance window:** D (host reboot) naturally restarts the VM → that single reboot satisfies C (BT bind) for free. Do B (RAID repartition + Windows into md0p2, VM off) in the same window before the host reboot, then D brings it all up. Order: B (VM off: repartition md0, deploy md0p2 config, install/restore Windows) → D (host reboot, VM auto-starts, C: now on RAID, BT binds) → done. Track A can land anytime beforehand (zero downtime).

## Risks / Tradeoffs
- A2 subvolume conversion moves files; if VM is running during deploy, libvirt holds the file open — deploy first, then the oneshot runs next boot OR after a clean stop. Safer: stop VM, deploy A2, start VM.
- B repartitions md0 (shrinks E: from 1.8 TB to ~1.1 TB, adds md0p2). E: is currently EMPTY so no data loss, but shrinking NTFS still carries a small risk — just ensure md0p1 shrink succeeds before mkpart.
- B is TEMPORARY/reversible: `c.raw` is preserved (not deleted), so the current install survives. Rollback = flip boot order to `vda` (B3). No data destroyed unless Windows is installed into md0p2.
- C: and E: will share the same physical RAID 0 (sda+sdb). Acceptable for a game VM; a single disk failure takes both (no worse than today, where E: already lives there).
- D host reboot kills mining on krash3 temporarily.
- Raw-block (B) trades btrfs COW checksum/integrity on C: for speed — acceptable for a game VM.
- Root-fs space reclaim (delete c.raw) is DEFERRED — only after user confirms the RAID setup is permanent.

## Open Questions
- Q1: Is there a Windows image backup to restore into md0p2 (B2), or will it be a fresh reinstall? (Temporary intent means we may install fresh, validate, then decide.)
- Q2: Target size for md0p2 — plan assumes ~700 GB (md0p1→1100G, md0p2 gets ~760G). Adjust if Windows needs more.
- Q3: When is the maintenance window? B (repartition + install) → D (host reboot, also binds BT) in one window; Track A can land anytime zero-downtime.
