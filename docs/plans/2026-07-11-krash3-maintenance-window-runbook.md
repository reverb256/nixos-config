# krash3-vm — Consolidated Maintenance Window Runbook

> STATUS: READY TO EXECUTE, NOT RUN. Requires user-approved window + dad off.
> Author: Hermes | Date: 2026-07-11
> Scope: activate ALL committed-but-dormant tuning + move C: to RAID (kill btrfs COW).
> Every step is idempotent or guarded. STOP if any gate fails; do not retry blindly.

## What this window accomplishes (all currently committed, dormant)
1. Host CPU governor = performance  (LIVE already; oneshot persists across boot)
2. `pcie_aspm=off` + `kvm_amd.msr_filter=0`  → ACTIVATES (needs host restart)
3. 8-vCPU isolation: isolcpus=1-8,13-20 + vcpu=8 pinning  → ACTIVATES (needs host restart)
4. iothreadpin 1/2 → cpuset 0  → ACTIVATES on next VM start (needs colmena apply + VM restart)
5. ioapic driver='kvm'  → ACTIVATES on next VM start (needs colmena apply + VM restart)
6. C: → md0p2 raw block (kill btrfs COW)  → needs VM stop + md0p1 shrink + host work
7. Host BIOS Above4G Decoding + ReBAR ON  → the ONLY ReBAR lever (BIOS, not config)

## PREREQUISITES (do before window)
- Dad confirmed OFF krash3-vm. Mining pause window accepted (host restart pauses forge? NO — forge is separate host; only krash3 host restarts, which pauses krash3 mining if any runs there. Confirm).
- Decide Q1: how to populate md0p2 (see Phase 4). Options:
  (a) Clone existing c.raw into md0p2 (keep current Windows install + apps), or
  (b) Fresh Windows install into md0p2 (clean, then reinstall apps/games).
  RECOMMENDED: (a) block-level clone — preserves dad's exact setup, zero reinstall.
- Backup c.raw first (it is the rollback): it already lives on btrfs; a host-side
  `cp --reflink=auto` to a safe location OR just keep it as-is (never deleted).

## EXECUTION SEQUENCE (verbatim)

### Phase 0 — Pre-flight (read-only, VM running)
```sh
ssh j_kro@10.1.1.150 "sh -c 'virsh -c qemu:///system domstate krash3-vm; sudo lsblk -b /dev/md0 /dev/md0p1; sudo virsh -c qemu:///system qemu-agent-command krash3-vm --cmd \"{\\\"execute\\\":\\\"guest-ping\\\"}\"'"
```
GATE: expect `running`, two lines of lsblk sizes, `{"return":{}}`.

### Phase 1 — Stop VM
```sh
ssh j_kro@10.1.1.150 "sh -c 'sudo virsh -c qemu:///system shutdown krash3-vm --mode acpi'"
# poll until shut off:
ssh j_kro@10.1.1.150 "sh -c 'sudo virsh -c qemu:///system domstate krash3-vm'"
```
GATE: state = `shut off`. If it hangs >2 min, `sudo virsh reset krash3-vm` (agent wedge, mode #4).

### Phase 2 — Shrink E: (md0p1) to free space for md0p2
E: is EMPTY (verified 2026-07-11: 0 GB used) → safe to shrink.
```sh
ssh j_kro@10.1.1.150 "sh -c 'sudo ntfsresize --size 1270G /dev/md0p1 && sudo parted /dev/md0 resizepart 1 1270GB && sudo parted /dev/md0 mkpart primary 1270GB 100% && sudo partprobe /dev/md0 && sudo lsblk /dev/md0'"
```
GATE: ntfsresize exits 0; lsblk shows md0p1 (~1.27T) + md0p2 (~700G).
  If ntfsresize FAILS → ABORT, leave md0p1 intact, skip Phase 4 (C: move), continue
  with Phases 3/5/6 (those do not need md0p2).

### Phase 3 — Deploy declarative changes (zephyr → krash3)
All tuning + C:→md0p2 are already COMMITTED on origin/main. Just pull + apply:
```sh
cd /etc/nixos && git pull origin main
colmena apply --on krash3
```
GATE: colmena exits 0; guard already passed in-session (krash3_vm_guard.py → PASS).
  The deploy's `assemble-games-raid` idempotently creates md0p2 (guarded if [ ! -b /dev/md0p2 ]).
  Verify: `ssh j_kro@10.1.1.150 "sh -c 'ls -l /dev/md0p2'"`.

### Phase 4 — Populate md0p2 (C:) — DECISION Q1
Option (a) CLONE existing c.raw into md0p2 (recommended, preserves install):
```sh
# c.raw is 700G; md0p2 is ~700G. Block-clone (host-side, VM stopped):
ssh j_kro@10.1.1.150 "sh -c 'sudo dd if=/var/lib/libvirt/images/c.raw of=/dev/md0p2 bs=1M status=progress conv=noerror,sync'"
```
  GATE: dd exits 0; `sudo virsh -c qemu:///system dumpxml krash3-vm | grep vdc` shows
  `source=/dev/md0p2` and bootOrder=1.
Option (b) FRESH INSTALL: boot Windows ISO + virtio drivers, install to vdc.
  (Only if user prefers clean.)

### Phase 5 — Host BIOS: enable Above4G Decoding + ReBAR
Physical BIOS on krash3 motherboard (manual step, not SSH):
- Enable "Above 4G Decoding" (Above 4G MMIO)
- Enable "Resizable BAR" / "ReBAR Support" (AMD: "Smart Access Memory")
GATE: none automatable; verified post-boot in Phase 7.

### Phase 6 — Host restart (activates isolcpus + aspm + msr_filter)
```sh
ssh j_kro@10.1.1.150 "sh -c 'sudo reboot'"
# wait for host back; confirm:
ssh j_kro@10.1.1.150 "sh -c 'tr \" \" \"\\n\" < /proc/cmdline | grep -iE \"pcie_aspm|msr_filter|isolcpus\"; grep -h . /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c'"
```
GATE: cmdline contains pcie_aspm=off, kvm_amd.msr_filter=0, isolcpus=1-8,13-20;
  governor = 24 performance (oneshot ran at boot).

### Phase 7 — Start VM + verify
```sh
ssh j_kro@10.1.1.150 "sh -c 'sudo virsh -c qemu:///system start krash3-vm'"
# wait for guest login (qemu-ga answers only after desktop, mode: login-gated)
ssh j_kro@10.1.1.150 "sh -c 'sudo virsh -c qemu:///system qemu-agent-command krash3-vm --cmd \"{\\\"execute\\\":\\\"guest-get-fsinfo\\\"}\"'"
```
GATE: C:\ now on PhysicalDrive with total-bytes ~700G, Healthy; D:/E: Healthy.

### Phase 8 — Verify ReBAR inside Windows (GUI check, ask dad/user)
  GPU-Z → "Resizable BAR: Enabled", OR NVIDIA Control Panel → System Info.
  If NO: re-check Phase 5 BIOS (Above4G usually the missing piece).

## ROLLBACK (any time)
- C: move: in params.nix uncomment c.raw (bootOrder=1), comment vdc; `colmena apply`;
  VM restart. c.raw never deleted.
- Tuning (isolcpus/aspm/msr/ioapic): revert the specific commit, `colmena apply`,
  host restart. All individually revertible.
- BIOS ReBAR: toggle off in firmware only.

## RISKS
- ntfsresize on md0p1 (Phase 2): E: empty → low risk, but ABORT if it fails.
- dd clone (Phase 4a): ~700G, takes minutes; do NOT interrupt (mode #14).
- Host restart (Phase 6): kills krash3-vm + any krash3-host mining; bundle with downtime.
- md0 is RAID0 (sda+sdb): single disk failure loses C: AND E: (same as today).
- Manual BIOS step (Phase 5): requires physical/kvm access to krash3.

## SUCCESS CRITERIA
- C: boots from md0p2, Healthy, write ≥ 500 MB/s (vs 351 MB/s COW).
- Host cmdline: pcie_aspm=off + msr_filter=0 + isolcpus=1-8,13-20.
- Governor 24× performance post-boot.
- iothreadpin + ioapic present in running dumpxml.
- Guest ReBAR = Enabled (GPU-Z).
- No config drift; all state in /etc/nixos, deployed via colmena.
