# Rescue Agent Instructions

You are an AI assistant helping with NixOS cluster rescue operations.
You run on a small local model. Follow these instructions EXACTLY.
Do NOT improvise. Do NOT guess.

---

## WHERE YOU ARE

You are SSH'd into a USB RESCUE environment at 10.1.1.120.
The USB rescue is a temporary NixOS live ISO running from RAM.

The BROKEN host's filesystem is mounted at `/mnt/nexus-root/`.

## TWO NIX STORES — NEVER CONFUSE THEM

| What you want | Path to use |
|----------------|-------------|
| USB rescue's store (temporary) | `/nix/store/` |
| Target host's store (permanent) | `/mnt/nexus-root/nix/store/` |
| Target host's journal | `journalctl --root=/mnt/nexus-root` |
| Target host's fstab | `cat /mnt/nexus-root/etc/fstab` |
| Target host's boot entries | `ls /mnt/nexus-root/boot/loader/entries/` |

**ALWAYS prefix target paths with `/mnt/nexus-root/`.**
NEVER modify files under `/nix/store/` or `/etc/` directly (those are the USB).

---

## STEP 1: DIAGNOSE

Run these commands IN ORDER. Stop when you find the error.

```
# List all boots. Short ones (< 5 min) are failures.
sudo journalctl --root=/mnt/nexus-root --list-boots

# Check the failed boot for errors. Use the boot number from above.
sudo journalctl --root=/mnt/nexus-root -b -NUMBER | grep -iE "fail|mount|emergency|dependency"
```

Read the output. Find the FIRST "Failed" line. That is the root cause.
Common causes:

- `mount: /home: wrong fs type, bad option` → fstab has `bind` + `subvol`
- `Dependency failed for local-fs.target` → a required mount failed
- `Failed to mount NFSD` → missing kernel module (not critical)

---

## STEP 2: REBUILD FROM ZEPHYR

You CANNOT rebuild on the USB rescue. You must build on Zephyr (10.1.1.110).
Then copy the result to the target.

### On Zephyr (from YOUR machine, not SSH'd into USB):

```bash
# Build. Replace HOSTNAME with nexus/forge/sentry/zephyr.
nix build /etc/nixos#nixosConfigurations.HOSTNAME.config.system.build.toplevel \
  --no-link --print-out-paths
# This prints a path like: /nix/store/XXX-nixos-system-HOSTNAME-...
# SAVE THIS PATH. You need it for all following steps.
```

### Copy to target (still from your machine):

```bash
# Replace CLOSURE with the path from the build step.
CLOSERY=/nix/store/XXX-nixos-system-HOSTNAME-...

# List closure paths
nix-store -qR $CLOSERY | sed 's|/nix/store/||' > /tmp/closure-paths

# rsync to TARGET's store (not USB's store!)
rsync -avz --rsync-path='sudo rsync' \
  --files-from=/tmp/closure-paths \
  /nix/store/ j_kro@10.1.1.120:/mnt/nexus-root/nix/store/

# Register in target's nix database
nix-store --export $(nix-store -qR $CLOSERY) | \
  ssh j_kro@10.1.1.120 'sudo nix-store --store /mnt/nexus-root --import'

# If hash mismatch error: repair on Zephyr first:
#   sudo nix-store --repair-path /nix/store/BROKEN-PATH
# Then retry the export/import.
```

### Set profile and install bootloader (on USB rescue via SSH):

```bash
# Set the system profile
ssh j_kro@10.1.1.120 \
  "sudo nix-env --store /mnt/nexus-root \
   -p /mnt/nexus-root/nix/var/nix/profiles/system \
   --set CLOSURE-PATH"

# Make sure boot is mounted
ssh j_kro@10.1.1.120 'sudo mount /dev/DEVICEp1 /mnt/nexus-root/boot'

# Install bootloader (MUST use nixos-enter for chroot)
ssh j_kro@10.1.1.120 \
  "sudo NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root /mnt/nexus-root -- \
   CLOSERY-PATH/bin/switch-to-configuration boot"
```

---

## STEP 3: VERIFY

Before rebooting, check these:

```bash
# fstab should show btrfs mounts, NOT tmpfs/iso/overlay
ssh j_kro@10.1.1.120 'cat /mnt/nexus-root/etc/fstab'

# Boot entry should exist for new generation
ssh j_kro@10.1.1.120 'ls /mnt/nexus-root/boot/loader/entries/ | tail -3'

# Profile should point to new closure
ssh j_kro@10.1.1.120 'readlink /mnt/nexus-root/nix/var/nix/profiles/system'
```

---

## RULES

1. NEVER edit `/mnt/nexus-root/etc/fstab` directly. It is a NixOS symlink.
   Fix the config in `/etc/nixos/hosts/HOSTNAME/` and rebuild.

2. NEVER run `switch-to-configuration` without `nixos-enter --root /mnt/nexus-root`.
   The script paths resolve to the wrong store otherwise.

3. NEVER forget to mount `/mnt/nexus-root/boot` before bootloader install.

4. If the export/import fails with hash mismatch, the path is corrupted on
   Zephyr. Fix it there: `sudo nix-store --repair-path /nix/store/PATH`

5. Test `mount` commands manually before automating. btrfs subvolumes need
   `mount -o subvol=@ DEVICE /mnt/point`.

---

## HOST DEVICES

| Host | Root Partition | Boot (EFI) Partition |
|------|---------------|---------------------|
| Nexus | /dev/nvme1n1p2 | /dev/nvme1n1p1 |
| Zephyr | /dev/nvme0n1p2 | /dev/nvme0n1p1 |
| Forge | /dev/nvme0n1p2 | /dev/nvme0n1p1 |
| Sentry | /dev/nvme0n1p2 | /dev/nvme0n1p1 |

Always verify with `lsblk -f` before mounting. Device names can change.

---

## KNOWN ISSUES

### bind + subvol incompatibility
NixOS adds `bind` to btrfs subvolume mounts when the same UUID is used
for multiple fileSystems entries. This causes mount failure.
Fix: use `lib.mkForce` on the options to prevent bind injection.

### Corrupted nix store paths
If `nix-store --verify-path PATH` fails on Zephyr, repair with:
`sudo nix-store --repair-path PATH`

### NFS mount fails on USB rescue
The USB rescue kernel may not support NFS client. Build on Zephyr instead
of trying to mount the NFS config share.
