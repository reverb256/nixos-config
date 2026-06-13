# Home Harmonization Plan
# Declarative /home/j_kro across Zephyr, Nexus, Forge, Sentry
#
# Goal: Centralize config, preserve critical data, standardize environments

## Architecture

```
Declarative (home-manager)     →  .config/*, dotfiles
Persistent (preservation)      →  SSH, GPG, Zen Browser, .agents
Data (no management)            →  ~/models, ~/projects, .cache, .local
```

## Backup Plan

### Zephyr (5.9M home - CRITICAL before void)
```bash
# Backup to Nexus
BACKUP_DATE=$(date +%Y%m%d)
ssh zephyr 'tar -czf - /home/j_kro' | \
  ssh nexus "sudo dd of=/data/backups/zephyr-${BACKUP_DATE}/home.tar.gz bs=4M"

# Verify
ssh nexus "tar -tzf /data/backups/zephyr-${BACKUP_DATE}/home.tar.gz | head -20"
```

### Nexus (288G home - SELECTIVE backup)
```bash
# Only backup config, not data
BACKUP_DATE=$(date +%Y%m%d)
ssh nexus 'tar -czf - /home/j_kro/.config /home/j_kro/.bashrc /home/j_kro/.vimrc' | \
  ssh nexus "sudo dd of=/data/backups/nexus-${BACKUP_DATE}/home-config.tar.gz bs=4M"

# Skip: ~/models (94G), ~/projects (1.2G), .cache (28G), .local (126G)
```

## Implementation

### 1. Add home-manager to modules/default.nix
```nix
imports = [
  # ...
  ./home-manager/default.nix  # Shared home-manager config
];
```

### 2. Update preservation.nix (already done)
```nix
users.j_kro = {
  directories = [
    { directory = ".ssh"; mode = "0700"; }
    { directory = ".gnupg"; mode = "0700"; }
    ".config"  # Home-manager config
    ".local/share"  # User app state
    ".agents"  # Agent state
    "tplink-backups"  # Router backups (Zephyr only)
  ];
  files = [
    ".screenrc"
    ".gtkrc-2.0.backup"
  ];
};
```

### 3. Per-host configuration

#### Zephyr (gaming workstation)
- Declarative: Wayfire, Steam, Discord, OBS
- Persistent: tplink-backups
- Data: Gaming files (not managed)

#### Nexus (AI server)
- Declarative: AI tools, dev config, podman
- Persistent: AI model configs (not models themselves)
- Data: ~/models (94G), ~/projects (1.2G)

#### Forge (mining)
- Declarative: Mining tools config
- Persistent: Mining pool configs
- Data: Mining output (not managed)

#### Sentry (monitoring)
- Declarative: Monitoring dashboards, scripts
- Persistent: Zen Browser (crypto wallets - CRITICAL)
- Data: Logs (already in /var/log)

## Migration Steps

### Phase 1: Backup (NOW)
1. ✅ Zephyr home to Nexus
2. ✅ Nexus config to Nexus
3. ✅ Sentry data (already done)

### Phase 2: Setup home-manager (NEXT)
1. Add home-manager module to modules/default.nix
2. Test on Sentry (about to be reformatted)
3. Migrate Zen Browser from Zephyr to Sentry

### Phase 3: Apply to all hosts
1. Zephyr: Apply after reinstall
2. Nexus: Apply in-place (risk - test first)
3. Forge: Apply in-place (risk - test first)

### Phase 4: Clean up
1. Remove old config files from home
2. Verify preservation module works
3. Test generation rollback

## Critical Data

### Zen Browser (Crypto Wallets)
- Location: /home/j_kro/.config/zen
- Backup: /data/backups/sentry-20260531/zen-browser-profile.tar.gz
- Preserved by: preservation module
- NOT managed by: home-manager

### SSH Keys
- Location: /home/j_kro/.ssh
- Preserved by: preservation module

### GPG Keys
- Location: /home/j_kro/.gnupg
- Preserved by: preservation module

### Agent Configs
- Location: /home/j_kro/.agents
- Preserved by: preservation module

## Testing Checklist

- [ ] Zephyr home backed up
- [ ] Nexus config backed up
- [ ] Sentry data backed up (✅ done)
- [ ] home-manager module added
- [ ] Build succeeds for all hosts
- [ ] Zen Browser test restore
- [ ] SSH keys survive generation rollback
- [ ] GPG keys survive generation rollback
- [ ] Agent configs survive generation rollback