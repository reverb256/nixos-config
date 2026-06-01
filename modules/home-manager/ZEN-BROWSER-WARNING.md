# Zen Browser Configuration (CRITICAL: Crypto Wallets)
#
# NOT managed by home-manager because:
# 1. Contains crypto wallets that must survive generation rollback
# 2. Preserved via preservation module
# 3. Backed up to Nexus: /data/backups/sentry-20260531/zen-browser-profile.tar.gz
#
# To restore after disko install:
#   scp root@nexus:/data/backups/sentry-20260531/zen-browser-profile.tar.gz sentry:/tmp/
#   ssh sentry "sudo tar -xzf /tmp/zen-browser-profile.tar.gz -C /home/j_kro"
#
# Size: 1.3 GB (.config/zen + .cache/zen)
# Location: /home/j_kro/.config/zen/
# Contains: Profile data, IndexedDB, storage (wallets)