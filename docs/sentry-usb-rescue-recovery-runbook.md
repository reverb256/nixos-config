# Sentry USB-Rescue Recovery Runbook

> **Last verified:** 2026-08-01 (during the 2026-08-01 Sentry recovery)
> **Status:** Validated end-to-end on Sentry's actual rescue (mounts + build relaunch).
> **Related issues:** #243 (Nexus USB rescue tooling debt), #242 (standardize preservation/BTRFS recovery).
>
> Doc-rot rule: if this doc is >7 days stale, re-verify against the live cluster before
> following it (see knowledge.md "Doc-rot prevention").

## TL;DR

Sentry's OS lives on the **Micron 1100 SATA SSD** (`sdb` in rescue = `disk-sdb-root`), NOT the
1TB HDD (`sda1` = `disk-sda-data`, data only). Mount the SSD's subvolumes read-only first,
build the closure on Nexus (never delegate to rescue Sentry), transfer via
`nix-store --export | gzip | ssh ... nix-store --import` with `NIX_STORE_DIR`/`NIX_STATE_DIR`
pointing at the target store, register the profile, then boot through `nixos-enter` with
`NIXOS_INSTALL_BOOTLOADER=1`.

## 1. Identify the correct storage (do NOT guess)

Sentry has **two disks**. The previous recovery wasted time assuming `/dev/sda3` — wrong disk.

| Disk | Rescue device | partlabel | Size | Role |
|------|--------------|-----------|------|------|
| Micron 1100 SSD | `sdb3` | `disk-sdb-root` | 229G | **OS**: `@root` `@nix` `@persistent` `@srv` `@var/tmp` |
| Micron 1100 SSD | `sdb1` | `disk-sdb-boot` | 1G | ESP (vfat) |
| Micron 1100 SSD | `sdb2` | `disk-sdb-swap` | 8G | swap |
| ST1000DM010 HDD | `sda1` | `disk-sda-data` | 931G | **Data**: `@home` `@` (storage) `@var` |

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,SERIAL
sudo blkid
# /dev/disk/by-partlabel must contain disk-sdb-root, disk-sdb-boot, disk-sda-data
```

Declarative source of truth: `hosts/sentry/hardware-configuration.nix` (uses partlabels, not
UUIDs — durable across disk swaps).

## 2. Mount target read-only first

Use the partlabel (not `sda3`/`sdb3` — device names can shift between rescues):

```bash
ROOT_DEV=/dev/disk/by-partlabel/disk-sdb-root
ESP_DEV=/dev/disk/by-partlabel/disk-sdb-boot
for pair in '@root:/mnt' '@nix:/mnt/nix' '@persistent:/mnt/persistent' '@srv:/mnt/srv' '@var/tmp:/mnt/var/tmp'; do
  SUBVOL="${pair%%:*}"; MNT="${pair##*:}"
  sudo mkdir -p "$MNT"
  sudo mount -o ro,subvol="$SUBVOL" "$ROOT_DEV" "$MNT"
done
sudo mkdir -p /mnt/boot && sudo mount -o ro "$ESP_DEV" /mnt/boot
```

**Gotcha:** `@var/tmp` mounts *under* `/mnt`, so it requires `/mnt` to be RW first. Mount
`@root` RW (or remount RW) before mounting `@var/tmp`. For pure inspection, `@var/tmp` can be
deferred.

Verify:
```bash
sudo findmnt -l | grep /mnt
sudo readlink -f /mnt/nix/var/nix/profiles/system   # current target generation
sudo find /mnt/nix/store -maxdepth 1 -type d -name '*nixos-system-sentry-*' | sort -r
```

## 3. Build the closure on Nexus (never on rescue Sentry)

Nexus is the designated builder (46G RAM). **Never** let the build delegate to the rescue
Sentry (it can't be a remote builder). The Garnix cache has been flaky (HTTP 502s) — exclude it.

Robust async launch (tmux sessions died on us; use `setsid nohup` + verified log):

```bash
# On Nexus, as j_kro:
cat > /tmp/sentry-build-launcher.sh << 'LAUNCH'
#!/usr/bin/env bash
LOG=/tmp/sentry-build-v3.log
cd /etc/nixos || exit 1
{
  echo "===== SENTRY BUILD START $(date --iso-8601=seconds) ====="
  echo "commit=$(git rev-parse HEAD 2>&1)"
  nix build \
    --builders '' \
    --option substituters 'https://cache.nixos.org https://nix-community.cachix.org https://reverb-os.cachix.org https://maplespike.cachix.org https://ezkea.cachix.org https://nix-gaming.cachix.org' \
    /etc/nixos#nixosConfigurations.sentry.config.system.build.toplevel \
    --no-link --print-out-paths --show-trace
  echo "build_exit=$?"
  echo "===== SENTRY BUILD DONE $(date --iso-8601=seconds) ====="
} > "$LOG" 2>&1
LAUNCH
chmod +x /tmp/sentry-build-launcher.sh
setsid nohup /tmp/sentry-build-launcher.sh < /dev/null > /dev/null 2>&1 &
sleep 8
pgrep -af 'sentry-build-launcher|nix build.*sentry'   # both must show
stat -c 'size=%s mtime=%y' /tmp/sentry-build-v3.log   # must be >0 and growing
```

A full closure is **463+ derivations** (thrift, arrow-cpp, pyarrow, qtbase 6.11, rocblas…).
Budget **1–3 hours**. Monitor with:
```bash
tail -f /tmp/sentry-build-v3.log
# Completion = a fresh non-.drv path:
ls -d /nix/store/*nixos-system-sentry-* | grep -v .drv | sort -r
```

## 4. Transfer the closure into the target store

Best-practice method (research-validated 2026-08-01; #243 documented every naive alternative
failing). `nix-store --export` does **not** compute closures — pipe requisites explicitly.
Raw rsync of store files without DB registration = GC will delete them.

```bash
# On Nexus, after build finishes, CLOSURE = path from log:
# NOTE: grep the WHOLE log (not tail -1) — the launcher appends
# build_exit= and a DONE banner AFTER the --print-out-paths line.
CLOSURE=$(grep -oP '/nix/store/[a-z0-9]{32}-nixos-system-sentry[^ ]*' /tmp/sentry-build-v3.log | tail -1)

# Sanity: CLOSURE must be a non-empty /nix/store path ending in nixos-system-sentry-*
[ -n "$CLOSURE" ] || { echo "closure path not found in log"; exit 1; }
echo "$CLOSURE"

# Export closure (gzip), pipe over SSH, import into the TARGET store:
nix-store --export $(nix-store -qR "$CLOSURE") | gzip \
  | ssh sentry 'sudo bash -c "gunzip -c | NIX_STORE_DIR=/mnt/nix/store NIX_STATE_DIR=/mnt/nix/var/nix nix-store --import"'
```

> **⚠️ CRITICAL (2026-08-14): canonicalize modes after import.**
> The import writes every file with build-user ownership (0775 nixbld:nixbld)
> instead of canonical Nix store modes (0444/0555 root:root). Because the NAR
> hash includes the executable bit, ALL imported paths become hash-invalid
> (nix store verify reports them "modified"), and sentry then serves
> divergent NARs into the ssh-ng builder pool → "hash mismatch importing path"
> on every build that races nexus/sentry.
> After import, ALWAYS run (on the target host):
> ```bash
> sudo nix-store --verify --check-contents --repair --store local
> ```
> This re-canonicalizes modes/ownership from the store DB (content is
> byte-identical; no re-download) and deletes the corrupted .links entries.
> Verify afterwards: `nix store verify --all --no-trust | grep -c "was modified"` should return 0.

Requires `/mnt/nix` RW first:
```bash
sudo mount -o remount,rw /mnt/nix
```

## 5. Register the generation

Inside `nixos-enter` (chroot where `/nix` = target store naturally), or with env vars:

```bash
# Via nixos-enter (auto-binds /proc /sys /dev; needs complete target profile closure with bash):
sudo nixos-enter --root /mnt -- \
  nix-env --profile /nix/var/nix/profiles/system --set "$CLOSURE"

# Or with env vars on the rescue host:
sudo env NIX_STORE_DIR=/mnt/nix/store NIX_STATE_DIR=/mnt/nix/var/nix \
  nix-env --profile /mnt/nix/var/nix/profiles/system --set "$CLOSURE"
```

## 6. Install the boot entry (official builder, never hand-written .conf)

**Never hand-write `/boot/loader/entries/*.conf`** — systemd-boot can only read files the ESP
can see; the official `systemd-boot-builder.py` copies kernel/initrd and writes correct BLS
entries. A previous botched attempt left a stale `/mnt/nix-store/...` init path — do not
reproduce that.

```bash
# Inside nixos-enter with /boot (ESP) mounted at /mnt/boot:
sudo nixos-enter --root /mnt -- \
  env NIXOS_INSTALL_BOOTLOADER=1 \
  "$CLOSURE/bin/switch-to-configuration" boot
```

Verify before rebooting:
```bash
sudo ls -la /mnt/boot/loader/entries/
sudo cat /mnt/boot/loader/entries/nixos-*.conf   # linux/initrd/init must be /nix/store/... NOT /mnt/...
sudo bootctl --path=/mnt/boot status
```

**Rollback safety:** the new generation is additive — old generations stay in
`/mnt/boot/loader/entries/` and the boot menu preserves them. Only reboot after verifying the
new entry's `init=` path resolves inside the target `/nix/store`.

## 7. Post-recovery hygiene

- `nix-store --verify --check-contents` on the target store (repair DB if needed:
  `nix-store --init` / `nix-store --load-db`).
- Bring Sentry back under colmena: `just deploy sentry` (adds remote-builder registration so
  the distributed-builds pool includes it again).
- Update this runbook's "Last verified" date with actual outcomes.

## Failure modes seen

| Symptom | Cause | Fix |
|---------|-------|-----|
| `mount: special device /dev/sda3 does not exist` | Wrong disk (HDD instead of SSD) | Use `/dev/disk/by-partlabel/disk-sdb-root` |
| `mkdir: /mnt/var/tmp: Read-only file system` | `@var/tmp` nests under `/mnt` | Mount/remount `@root` RW first |
| Build dies after ~1h, no log | tmux server death / SSH disconnect | `setsid nohup` + verified log file |
| `nix-store -qR <closure>` returns 1 path | Closure deps not registered in target DB | Re-import via `nix-store --import` (registers DB) |
| 502s from `cache.garnix.io` | Garnix flaky | Exclude Garnix from substituters for the build |
| Stale `/mnt/nix-store/...` init in boot entry | Previous manual/botched boot install | Never hand-write entries; use `switch-to-configuration boot` |

## Declarative layout reference

`hosts/sentry/hardware-configuration.nix`:
- `/` → `disk-sdb-root` subvol `@root`
- `/nix` → `disk-sdb-root` subvol `@nix` (`x-initrd.mount`, neededForBoot)
- `/persistent` → `disk-sdb-root` subvol `@persistent`
- `/srv` → `disk-sdb-root` subvol `@srv` (neededForBoot)
- `/var/tmp` → `disk-sdb-root` subvol `@var/tmp`
- `/home` → `disk-sda-data` subvol `@home`
- `/storage` → `disk-sda-data` subvol `@`
- `/var/storage` → `disk-sda-data` subvol `@var`
- `/boot` → `disk-sdb-boot` (vfat)
- swap → `disk-sdb-swap`
