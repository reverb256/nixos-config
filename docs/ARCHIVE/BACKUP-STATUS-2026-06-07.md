# Backup Status (2026-05-31)

## All Backups Complete ✅

### Nexus: /data/backups/

```
sentry-20260531/
├── ssd-persistent.tar.gz (1.7 GB) - System state
├── hdd-home.tar.gz (1.4 GB) - Sentry home data
└── zen-browser-profile.tar.gz (1.3 GB) - CRYPTO WALLETS
Total: 4.3 GB

zephyr-20260531/
└── home-current.tar.gz (456 KB) - Current Zephyr home (config only)

/home/backups/
└── zephyr-home/
    └── j_kro/ (84 GB) - Old Zephyr backup (May 29)
        - SSH private keys ✅
        - Gaming files ✅
        - tplink-backups (empty)
```

## Critical Data Verification

### Zen Browser (Crypto Wallets)
- ✅ Backed up: `/data/backups/sentry-20260531/zen-browser-profile.tar.gz`
- Size: 1.3 GB
- Location: `/home/j_kro/.config/zen` (will restore here)
- Preserved by: `preservation.nix`
- NOT managed by: `home-manager`

### SSH Keys
- ✅ Zephyr old backup: `/home/backups/zephyr-home/j_kro/.ssh/` (May 29)
- ✅ Zephyr current: `/data/backups/zephyr-20260531/home-current.tar.gz` (today)
- ⚠️ Need to restore from old backup (current only has known_hosts)
- Preserved by: `preservation.nix`

### GPG Keys
- ✅ Tracked in `preservation.nix`
- Should be in backup

### tplink-backups
- ❌ Empty in current Zephyr home
- ❌ Empty in old backup
- ❓ Likely migrated elsewhere (check Nexus /data or /home/j_kro)
- ❌ NOT tracked in preservation (removed)

## Zephyr Post-Void Restore Plan

### Step 1: Restore SSH keys (CRITICAL)
```bash
# From old backup (May 29) - has private keys
scp -r root@nexus:/home/backups/zephyr-home/j_kro/.ssh zephyr:/home/j_kro/
chmod 700 /home/j_kro/.ssh
chmod 600 /home/j_kro/.ssh/id_ed25519
```

### Step 2: Restore gaming files (if needed)
```bash
# From old backup (May 29)
scp -r root@nexus:/home/backups/zephyr-home/j_kro/.local/share/Steam zephyr:/home/j_kro/.local/share/
```

### Step 3: Restore current config
```bash
# From today's backup
scp root@nexus:/data/backups/zephyr-20260531/home-current.tar.gz zephyr:/tmp/
ssh zephyr "tar -xzf /tmp/home-current.tar.gz -C /home/j_kro"
```

### Step 4: Verify
```bash
# SSH keys
ssh zephyr 'ls -la /home/j_kro/.ssh/id_ed25519'

# Config
ssh zephyr 'ls -la /home/j_kro/.config/ | wc -l'

# Gaming
ssh zephyr 'du -sh /home/j_kro/.local/share/Steam'
```

## Sentry Post-Install Restore Plan

### Step 1: Restore persistent (system state)
```bash
scp root@nexus:/data/backups/sentry-20260531/ssd-persistent.tar.gz sentry:/persistent.tar.gz
ssh sentry "sudo tar -xzf /persistent.tar.gz -C /"
```

### Step 2: Restore home (data)
```bash
scp root@nexus:/data/backups/sentry-20260531/hdd-home.tar.gz sentry:/home.tar.gz
ssh sentry "sudo tar -xzf /home.tar.gz -C /home"
```

### Step 3: Restore Zen Browser (CRYPTO WALLETS - CRITICAL)
```bash
scp root@nexus:/data/backups/sentry-20260531/zen-browser-profile.tar.gz sentry:/tmp/
ssh sentry "sudo tar -xzf /tmp/zen-browser-profile.tar.gz -C /home/j_kro"
# Verify
ssh sentry "ls -la /home/j_kro/.config/zen/l3auzmdm.Default\ Profile/storage/"
```

## Verification Checklist

- [ ] ✅ Sentry data backed up
- [ ] ✅ Zephyr old backup verified (84 GB)
- [ ] ✅ Zephyr current backup verified (456 KB)
- [ ] ✅ Zen Browser backup verified
- [ ] ✅ SSH keys in old backup
- [ ] ❓ tplink-backups location unknown (not critical)

## Next Steps

1. ✅ **NOW**: Sentry backups complete
2. ⏳ **NEXT**: Run nixos-anywhere on Sentry
3. ⏳ **AFTER Sentry boots**: Restore Sentry data
4. ⏳ **BEFORE Zephyr void**: Double-check tplink-backups location
5. ⏳ **AFTER Zephyr reinstall**: Restore Zephyr data (see plan above)

## Preservation Module Status

**Sentry:**
- ✅ Tracks: .config, .local/share, .ssh, .gnupg, .agents
- ✅ Zen Browser: Crypto wallets preserved
- ❌ tplink-backups: Removed (empty)

**Zephyr (when reinstalled):**
- ✅ Will use same preservation module
- ✅ tplink-backups NOT tracked (empty)
- ✅ Home-manager will manage .config/* declaratively