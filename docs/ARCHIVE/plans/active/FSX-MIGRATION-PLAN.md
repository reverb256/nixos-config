# Flight Simulator X — Migration Plan

**Status:** Active — transfer in progress
**Started:** 2026-06-17
**Source:** krash1.5 (DESKTOP-ONB6NLM, 10.1.1.79)
**Destination:** krash3 (10.1.1.150) — E:\Games\Microsoft Flight Simulator X\

## Overview

Migrate a heavily-modded FSX installation (~81 GB, 206K files) from the old krash1.5 Windows 10 machine to the E: drive on krash3's Windows host, which has 741 GB free.

Addons include: A2A, PMDG, Carenado, REX, Flight One Software, Aerosoft, and many more.

## Transfer Method

- **Tool:** rclone v1.74.3 (installed on both ends)
- **Protocol:** SFTP from krash1.5 → krash3 (via SSH on port 22222)
- **Auth:** krash1.5's ed25519 key added temporarily to j_kro@krash3 authorized_keys
- **Command:**
  ```
  rclone sync -P \
    "C:\Program Files (x86)\Microsoft Games\Microsoft Flight Simulator X" \
    "krash3:/mnt/e/Games/Microsoft Flight Simulator X/"
  ```

## Post-Migration Steps

- [ ] Remove temporary SSH key from krash3's ~/.ssh/authorized_keys
- [ ] Verify file count and integrity on destination
- [ ] Test FSX launches from krash3's Windows
- [ ] Clean up old FSX source on krash1.5 (after verification)
- [ ] Remove FSX_Migration SMB share on krash1.5 (if no longer needed)

## Network Topology

```
krash1.5 (10.1.1.79)          krash3 (10.1.1.150)
┌─────────────────────┐       ┌──────────────────────┐
│ FSX: C:\Program     │  rclone sync (SFTP)   │ WSL NixOS (j_kro)   │
│   Files...\FSX      │ ──────────────────→   │  /mnt/e/Games/FSX/  │
│ 81 GB / 206K files  │                       │  (→ E:\Games\FSX\)  │
└─────────────────────┘       └──────────────────────┘
```

## Notes

- Destination directory already exists at `/mnt/e/Games/Microsoft Flight Simulator X/`
- E: drive has 741 GB free (1.9 TB total, 1.1 TB used)
- rclone sync = one-way mirror (adds/updates files on dest, does NOT delete from source)
- ~20-50 minute transfer over gigabit LAN depending on file mix
