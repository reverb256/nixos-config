# Sentry Disk Layout (Full Declarative Control)

## SSD (sdb) - 256GB Micron 1100 SATA
**Purpose:** System, K8s, Nix Store (fast I/O)

```
Partition 1: EFI boot (1G, vfat)
  └─ /boot

Partition 2: Swap (8G)
  └─ swap

Partition 3: btrfs (remaining 247G)
  ├─ @root → /
  │   ├─ /bin, /etc, /usr, ...
  │   ├─ /var/lib/rancher/k3s/ ← K8s data (containers, pods, images)
  │   ├─ /var/lib/systemd/
  │   ├─ /var/log/
  │   └─ /var/lib/containers/
  │
  ├─ @persistent → /persistent
  │   ├─ /persistent/etc/ssh/ (SSH keys)
  │   ├─ /persistent/var/log/
  │   ├─ /persistent/home/j_kro/.config/
  │   └─ /persistent/home/j_kro/.gnupg/
  │
  ├─ @nix → /nix
  │   └─ /nix/store/ ← Nix store (derivations, packages)
  │
  ├─ @srv → /srv
  │   └─ /srv/ (services data)
  │
  └─ @var/tmp → /var/tmp
      └─ /var/tmp/ (temp files)

Mount options: compress=zstd:3, ssd, discard=async, noatime
```

**SSD Usage:**
- ✅ System root (/)
- ✅ K3s/K8s data (/var/lib/rancher/k3s/)
- ✅ Nix store (/nix/store/)
- ✅ System state (/persistent)
- ✅ Services data (/srv)
- ✅ Temporary files (/var/tmp)

## HDD (sda) - 1TB ST1000DM010
**Purpose:** User data, home, additional storage (large capacity)

```
Partition 1: btrfs (full disk)
  ├─ @ → /storage
  │   └─ User data, downloads, media
  │
  ├─ @home → /home
  │   ├─ /home/j_kro/
  │   ├─ /home/j_kro/.config/zen/ ← Crypto wallets (backed up)
  │   └─ /home/j_kro/projects/
  │
  └─ @var → /var/storage
      └─ Additional storage (logs, exports, backups)

Mount options: compress=zstd, nofail
```

**HDD Usage:**
- ✅ User home (/home)
- ✅ User data (/storage)
- ✅ Additional storage (/var/storage)

## K8s Data Location

**K3s stores all data on SSD:**
```
/var/lib/rancher/k3s/
├── agent/
│   ├── pod-manifests/
│   └── containerd/
├── server/
│   ├── tls/
│   └── db/
└── data/
    └── containerd/ ← Container images, layers
```

**Why on SSD:**
- Fast I/O for container operations
- K8s needs low latency
- Images and layers benefit from SSD speed
- Nix store already there, can share space

## Nix Store Location

**Nix store on SSD:**
```
/nix/store/
├── 00... - Derivations
├── 01... - Packages
└── ...
```

**Why on SSD:**
- Build speed
- Package installation speed
- Same disk as K8s (can share space)

## Backup Strategy

**What to backup:**
- SSD @persistent → System state, SSH, GPG
- HDD @home → User home, Zen Browser (crypto)
- HDD @ → User data
- SSD @root → K8s configs (not state - K8s manages that)

**Not needed to backup:**
- Nix store (reproducible, can rebuild)
- K8s data (ephemeral, managed by K8s)

## Summary

| Disk | Path | Purpose | Speed |
|------|------|---------|-------|
| SSD | / | System root | Fast |
| SSD | /nix | Nix store | Fast |
| SSD | /var/lib/rancher/k3s | K8s data | Fast |
| SSD | /persistent | System state | Fast |
| HDD | /home | User home | Slow |
| HDD | /storage | User data | Slow |
| HDD | /var/storage | Additional storage | Slow |

**Perfect separation:**
- Fast I/O: System, K8s, Nix (SSD)
- Large capacity: User data, home (HDD)