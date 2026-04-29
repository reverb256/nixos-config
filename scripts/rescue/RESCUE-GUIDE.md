# NixOS Cluster Rescue Guide

## CRITICAL: Know Where You Are

**TWO separate systems exist simultaneously:**

| Path | System | Description |
|------|--------|-------------|
| `/` | USB Rescue | Live ISO running from RAM. Temporary. |
| `/nix/store/` | USB Rescue | RAM-based overlay store. Wiped on reboot. |
| `/mnt/nexus-root/` | TARGET SYSTEM | Mounted btrfs root of the broken host. |
| `/mnt/nexus-root/nix/store/` | TARGET SYSTEM | The target's REAL nix store on disk. |

**When you SSH to 10.1.1.120, you land on the USB rescue.**
The broken host's filesystem is mounted at `/mnt/nexus-root/`.

EVERY fix must target `/mnt/nexus-root/`, NOT `/`.

---

## Cluster Hosts

| Host | IP | Root Device | Boot Device | Root UUID |
|------|-----|-------------|-------------|-----------|
| Zephyr | 10.1.1.110 | /dev/nvme0n1p2 | /dev/nvme0n1p1 | 0893f780-7016-44cc-aae7-1f7996e498cc |
| Nexus | 10.1.1.120 | /dev/nvme1n1p2 | /dev/nvme1n1p1 | 0893f780-7016-44cc-aae7-1f7996e498cc |
| Forge | 10.1.1.130 | /dev/nvme0n1p2 | /dev/nvme0n1p1 | (check with lsblk) |
| Sentry | 10.1.1.140 | /dev/nvme0n1p2 | /dev/nvme0n1p1 | (check with lsblk) |

All hosts use btrfs with `@` (root) and `@home` subvolumes.

---

## Step 1: Boot Diagnostics

### Find failed boots

```bash
# List all boots from the TARGET system
sudo journalctl --root=/mnt/nexus-root --list-boots

# Short-duration boots (under 5 minutes) are likely failed/emergency mode
```

### Read the failed boot journal

```bash
# Replace -7 with the failed boot number from --list-boots
sudo journalctl --root=/mnt/nexus-root -b -7 --no-pager | \
  grep -iE "mount|fail|emergency|dependency|timeout"
```

### Common failure patterns

| Error | Cause | Fix |
|-------|-------|-----|
| `mount: /home: wrong fs type, bad option` | `bind` + `subvol` in fstab | Rebuild with fixed mount options |
| `Dependency failed for local-fs.target` | A required mount failed | Fix the specific mount |
| `Failed to mount /run/nixos-shared` | NFS server unreachable | Check Zephyr, or add `nofail` |
| `proc-fs-nfsd.mount: unknown filesystem` | NFS kernel module missing | Missing `CONFIG_NFSD` in kernel |

---

## Step 2: Rebuild From USB Rescue

### Overview

The rebuild process builds a new NixOS closure on Zephyr (has the config),
copies it to the target's nix store, and activates it.

### Prerequisites

- Target root mounted at `/mnt/nexus-root` (btrfs subvol=@)
- Target boot mounted at `/mnt/nexus-root/boot` (vfat ESP)
- SSH access to Zephyr (10.1.1.110) for building

### Automated Rebuild (run from Zephyr)

```bash
# 1. Build the closure on Zephyr
nix build /etc/nixos#nixosConfigurations.nexus.config.system.build.toplevel \
  --no-link --print-out-paths

# Save the output path, e.g.: /nix/store/XXXXX-nixos-system-nexus-...

# 2. Generate closure path list
nix-store -qR /nix/store/XXXXX-nixos-system-nexus-... | \
  sed 's|/nix/store/||' > /tmp/nexus-closure-paths

# 3. rsync closure to TARGET's nix store (not USB's!)
rsync -avz --rsync-path='sudo rsync' \
  --files-from=/tmp/nexus-closure-paths \
  /nix/store/ j_kro@10.1.1.120:/mnt/nexus-root/nix/store/

# 4. Register closure in target's nix database
nix-store --export $(nix-store -qR /nix/store/XXXXX-nixos-system-nexus-...) | \
  ssh j_kro@10.1.1.120 'sudo nix-store --store /mnt/nexus-root --import'

# 5. Set system profile
ssh j_kro@10.1.1.120 \
  'sudo nix-env --store /mnt/nexus-root -p /mnt/nexus-root/nix/var/nix/profiles/system \
   --set /nix/store/XXXXX-nixos-system-nexus-...'

# 6. Install bootloader (MUST use nixos-enter for chroot)
ssh j_kro@10.1.1.120 \
  'sudo NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root /mnt/nexus-root -- \
   /nix/store/XXXXX-nixos-system-nexus-.../bin/switch-to-configuration boot'
```

### Important: Step 4 may fail with hash mismatch

If `nix-store --export` fails with a hash error:
```bash
# The path is corrupted on Zephyr. Repair it first:
sudo nix-store --repair-path /nix/store/CORRUPTED-PATH

# Then retry the export/import
```

---

## Step 3: Verify Before Reboot

```bash
# Check fstab is correct (should be NixOS-managed, NOT ISO entries)
cat /mnt/nexus-root/etc/fstab
# Should show btrfs mounts with subvol=@, NOT tmpfs/iso9660/overlay

# Check bootloader entry exists for new generation
ls /mnt/nexus-root/boot/loader/entries/ | tail -3

# Check system profile points to new closure
readlink /mnt/nexus-root/nix/var/nix/profiles/system
```

---

## Common Mistakes to Avoid

### 1. Editing files in /mnt/nexus-root/etc/ directly

DON'T. NixOS manages /etc via symlinks to /nix/store. Changes will be
overwritten on next activation. Fix the NixOS config instead and rebuild.

### 2. Breaking the fstab symlink

`/mnt/nexus-root/etc/fstab` is a symlink to `/etc/static/fstab` which
points into /nix/store. NEVER replace it with a plain file. If broken:
```bash
sudo rm /mnt/nexus-root/etc/fstab
sudo ln -s /etc/static/fstab /mnt/nexus-root/etc/fstab
```

### 3. Confusing USB nix store with target nix store

- `/nix/store/` = USB rescue (RAM, temporary)
- `/mnt/nexus-root/nix/store/` = target host (disk, permanent)

Scripts that use `--store /mnt/nexus-root` target the correct store.

### 4. Running switch-to-configuration without nixos-enter

The script's internal paths resolve to `/nix/store/`. Without chroot,
these resolve to the USB rescue's store, not the target's. Always use:
```bash
sudo nixos-enter --root /mnt/nexus-root -- \
  /nix/store/.../bin/switch-to-configuration boot
```

### 5. Forgetting to mount /boot before bootloader install

```bash
# Check boot is mounted
mountpoint /mnt/nexus-root/boot || sudo mount /dev/nvme1n1p1 /mnt/nexus-root/boot
```

---

## NixOS fstab + btrfs Subvolumes

NixOS auto-adds `bind` when the same device UUID appears in multiple
fileSystems entries. This is WRONG for btrfs subvolumes.

**Broken (auto-generated):**
```
/dev/disk/by-uuid/XXX /home btrfs subvol=@home,bind,nodev,nosuid
```

**Fixed (in NixOS config):**
```nix
# In hosts/<host>/hardware.nix, use mkForce to prevent bind injection:
"/home".options = lib.mkForce [
  "subvol=@home"
  "compress=zstd:3"
  "ssd"
  "discard=async"
];
```

This generates:
```
/dev/disk/by-uuid/XXX /home btrfs subvol=@home,compress=zstd:3,ssd,discard=async
```

---

## Quick Reference

```bash
# Mount target root
sudo mount -o subvol=@ /dev/nvme1n1p2 /mnt/nexus-root
sudo mount /dev/nvme1n1p1 /mnt/nexus-root/boot

# Check journal for last failed boot
sudo journalctl --root=/mnt/nexus-root --list-boots
sudo journalctl --root=/mnt/nexus-root -b -1 --no-pager | grep -iE "fail|mount|emergency"

# Verify fstab
cat /mnt/nexus-root/etc/fstab

# Unmount when done
sudo umount /mnt/nexus-root/boot /mnt/nexus-root
```
