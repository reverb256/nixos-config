# Sentry Migration Plan (UPDATED - Full Disko Control)

## ⚠️ CRITICAL: HDD (sda) Will Be Wiped

### Disks (ALL managed by disko)

**SSD (sdb) - 256GB:**
- Partition 1: EFI boot (1G, vfat)
- Partition 2: Swap (8G)
- Partition 3: btrfs
  - @root → / (system)
  - @persistent → /persistent (state)
  - @nix → /nix (store)
  - @srv → /srv
  - @var/tmp → /var/tmp

**HDD (sda) - 1TB:**
- Partition 1: btrfs (FULL DISK)
  - @ → /storage (user data)
  - @home → /home (user home)
  - @var → /var/storage (additional storage)
- ✅ **WILL WIPE EXISTING DATA** (@home, @var, and everything on sda)
- ✅ Backup already complete

## Backup Status (Nexus /data/backups/sentry-20260531/)

```
ssd-persistent.tar.gz (1.7 GB) - System state (/persistent on SSD)
hdd-home.tar.gz (1.4 GB) - User home (@home on HDD)
zen-browser-profile.tar.gz (1.3 GB) - CRYPTO WALLETS (.config/zen)
```

**✅ All critical data backed up - safe to wipe**

## Installation (nixos-anywhere)

```bash
# Use j_kro (not root) - has passwordless sudo and SSH keys configured
nix run github:numtide/nixos-anywhere -- --flake .#sentry j_kro@10.1.1.140
```

This will:
1. ✅ Format SSD (sdb) with new layout
2. ✅ Format HDD (sda) with new layout
3. ✅ Install system
4. ⏸️ Reboot

**User configuration:**
- j_kro: UID 1000, passwordless sudo (NOPASSWD: ALL)
- root: Same password hash as j_kro (for consistency)
- Both SSH accessible

## Post-Install Restore

### Step 1: Restore persistent (system state)
```bash
BACKUP_DATE=20260531
scp root@nexus:/data/backups/sentry-${BACKUP_DATE}/ssd-persistent.tar.gz sentry:/persistent.tar.gz
ssh sentry "sudo tar -xzf /persistent.tar.gz -C /"
```

### Step 2: Restore home (user data)
```bash
scp root@nexus:/data/backups/sentry-${BACKUP_DATE}/hdd-home.tar.gz sentry:/home.tar.gz
ssh sentry "sudo tar -xzf /home.tar.gz -C /home"
```

### Step 3: Restore Zen Browser (CRYPTO WALLETS - CRITICAL)
```bash
scp root@nexus:/data/backups/sentry-${BACKUP_DATE}/zen-browser-profile.tar.gz sentry:/tmp/
ssh sentry "sudo tar -xzf /tmp/zen-browser-profile.tar.gz -C /home/j_kro"
# Verify
ssh sentry "ls -la /home/j_kro/.config/zen/l3auzmdm.Default\ Profile/storage/"
```

## New Layout Benefits

**Declarative:**
- ✅ All disks managed by disko
- ✅ Reproducible rebuild
- ✅ Easy migration to new hardware

**Backup/Restore:**
- ✅ System state separated from user data
- ✅ Home on fast btrfs (compress=zstd)
- ✅ Storage on same disk (accessible)
- ✅ Critical wallets backed up separately

**Persistence:**
- ✅ /persistent survives generation rollback
- ✅ /storage persists (on HDD)
- ✅ /home persists (on HDD)
- ✅ Zen Browser in preservation module

## Verification Checklist

- [ ] ✅ All backups complete
- [ ] ✅ HDD backup verified
- [ ] ✅ SSD backup verified
- [ ] ✅ Zen Browser backup verified
- [ ] ⏳ Run nixos-anywhere
- [ ] ⏳ Restore persistent
- [ ] ⏳ Restore home
- [ ] ⏳ Restore Zen Browser
- [ ] ⏳ Verify crypto wallets
- [ ] ⏳ Test generation rollback
- [ ] ⏳ Verify preservation module

## Declarative System Complete

**Disks:** 100% disko-managed (no manual partitions)
**Home:** Declarative (home-manager) + persistent (preservation module)
**State:** Tracked and survives rollback
**Backups:** All critical data safe

**Ready to run nixos-anywhere!**