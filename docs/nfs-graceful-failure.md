# NFS Graceful Failure Configuration

**Last Updated:** 2026-03-14
**Purpose:** Ensure cluster remains responsive when NFS server is unavailable

---

## Problem

Previously, NFS mounts used `hard` mount option which causes processes to **hang indefinitely** when the NFS server becomes unavailable. This could cause:
- Shells freezing when trying to `cd` into NFS directories
- Services hanging during startup if NFS is unavailable
- System becoming unresponsive during network partitions

## Solution

Changed all NFS mounts to use **soft mounts** with appropriate timeouts:

### Mount Options Explained

| Option | Value | Purpose |
|--------|-------|---------|
| `soft` | - | Return errors after timeout instead of hanging forever |
| `timeo=50` | 5 seconds | Timeout in deciseconds (50 × 0.1s = 5s) |
| `retrans=2` | 2 retries | Give up after 2 timeout attempts |
| `nofail` | - | Don't fail boot if mount unavailable |
| `x-systemd.mount-timeout=10s` | 10 seconds | Systemd gives up on mount after 10s |

### Behavior Comparison

**Before (hard mount):**
```
NFS server down → Process hangs indefinitely → System unresponsive
```

**After (soft mount):**
```
NFS server down → 5s timeout → 2 retries → I/O error after ~10s → Process continues (with error handling)
```

---

## Impact by Service

### Critical Services (Use with Care)

These services may need to handle I/O errors gracefully:

| Service | NFS Dependency | Recommended Action |
|---------|----------------|-------------------|
| `mining` | None | No impact |
| `kubernetes` | None | No impact (uses local storage) |
| `garage` | None | No impact (uses local storage) |
| `promtail` | None | No impact (reads journald locally) |
| Application data on `/data/shared` | HIGH | Add error handling for I/O failures |

### Mount Points Affected

| Mount Point | Server | New Behavior |
|-------------|--------|--------------|
| `/run/nixos-shared` | Zephyr | Errors after 10s if Zephyr down |
| `/data/shared` | Nexus | Errors after 10s if Nexus down |
| `/data/home` | Nexus | Errors after 10s if Nexus down |
| `/data/media` | Nexus | Errors after 10s if Nexus down |

---

## Testing Graceful Failure

### Test 1: Server Unavailable at Boot

```bash
# On Nexus (NFS server)
sudo systemctl stop nfs-server

# On Forge (client) - reboot should not hang
sudo reboot

# Expected: Forge boots without NFS, shows mount errors in logs
```

### Test 2: Server Goes Down During Operation

```bash
# On Forge, access NFS share
cd /data/shared
ls

# On Nexus, stop NFS server
sudo systemctl stop nfs-server

# On Forge, try to access again
ls
# Expected: "Input/output error" after ~10 seconds
# Shell remains responsive
```

### Test 3: Server Recovers

```bash
# On Nexus, restart NFS server
sudo systemctl start nfs-server

# On Forge, access again
cd /data/shared
ls
# Expected: Normal operation resumes (may need to cd out and back in)
```

---

## Application Error Handling

Applications using NFS should handle these errors:

### Python Example
```python
import os
import errno

try:
    with open('/data/shared/file.txt', 'r') as f:
        data = f.read()
except IOError as e:
    if e.errno == errno.EIO:
        # NFS unavailable - use fallback or retry
        print("NFS unavailable, using local cache")
    else:
        raise
```

### Shell Script Example
```bash
#!/bin/bash

if ! ls /data/shared >/dev/null 2>&1; then
    echo "NFS unavailable, using local fallback"
    # Use alternative path or cached data
fi
```

### Systemd Service Example
```nix
# Add to service configuration
serviceConfig = {
  # Don't fail if NFS mounts aren't ready
  Requires = [ ];
  After = [ "remote-fs.target" ];  # But try to wait for them
};
```

---

## Rollback Plan

If soft mounts cause issues, revert to hard mounts:

```nix
# In modules/services/nfs-client.nix
# Change: "soft" "timeo=50" "retrans=2"
# To: "hard" "intr" "timeo=600" "retrans=2"
```

---

## Monitoring

### Check NFS Mount Status
```bash
# Show all NFS mounts
df -hT -t nfs,nfs4

# Show mount options
mount | grep nfs
```

### Monitor for NFS Issues
```bash
# Check dmesg for NFS errors
dmesg | grep -i nfs

# Check systemd mount units
systemctl status remote-fs.target
systemctl status *.mount | grep data
```

---

## References

- [NFS Mount Options (kernel.org)](https://www.kernel.org/doc/html/latest/filesystems/nfs/nfsroot.html)
- [systemd.mount(5)](https://man7.org/linux/man-pages/man5/systemd.mount.5.html)
- [NFS Troubleshooting](https://tldp.org/HOWTO/NFS-HOWTO/troubleshooting.html)
