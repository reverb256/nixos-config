# Plan: Zephyr I/O Audit Remediation

**Last Verified:** 2026-05-21
**Scope:** Zephyr-only (does not affect other hosts)
**Drives (both NVMe):**
  - **NVMe #1** (b07258b9) — `/`, `/home`, bind mounts: `/data/hermes`, `/data/pi`, `/data/models`
  - **NVMe #2** (4c249712) — `/data`, `/data/games`, `/data/projects`, `/data/archive`
  - **zram** — swap (35% RAM, ~10.8GB, zstd, priority 999)
  - **vfat** (EB7C-E7CC) — `/boot`

---

## Issue 1: sysstat.service Not Enabled

**Problem:** `sysstat` package installed via `system-tools` `basic` set, but `sysstat.service` (sadc background collector) never enabled. No historical I/O data. `iostat`/`sar` works live only.

**Fix:** Add `services.sysstat.enable = true` to zephyr's monitoring.nix. This activates the sadc cron/ timer that collects system activity data every 10 minutes by default.

**File:** `hosts/zephyr/monitoring.nix`
**Change:** Add `services.sysstat.enable = true;`

**Verification:** `systemctl status sysstat.service`, `sar -d` shows historical data

---

## Issue 2: No Disk Latency Monitoring

**Problem:** node-exporter `diskstats` collector tracks ops/sec and bytes/sec but not latency percentiles. No insight into whether I/O is actually slow.

**Option A — Node Exporter diskstats (already present, enhance):**
Prometheus `rate(node_disk_io_time_weighted_seconds[5m])` already in Grafana deep-insights dashboard. This is average IO service time. But no percentile breakdown.

**Option B — Add disk latency histogram via custom script:**
Use `/sys/block/<dev>/stat` to compute avg latency per device. Node-exporter textfile collector already configured at `/var/lib/prometheus/node-exporter/textfile-collector`.

**Option C — fio or ioping for active probing (reactive only):**
Not recommended for continuous monitoring.

**Recommended:** Option B — lightweight shell script collecting per-disk avg I/O latency from `/sys/block/*/stat`, exported via node_exporter textfile collector. Already have the textfile directory set up.

**File:** New: `modules/services/monitoring/disk-latency-monitor.nix` (NixOS module, reusable)
**Or:** `hosts/zephyr/services.nix` inline systemd service + timer

**Verification:** `curl localhost:9100/metrics | grep disk_latency`

---

## Issue 3: No BTRFS Device Stats Monitoring

**Problem:** btrfs device stats (`btrfs device stats /`) report checksum errors, I/O errors, flush errors — valuable health signal. Not collected anywhere.

**Fix:** Add a periodic systemd service (weekly) that collects `btrfs device stats` for both drives and exports to node_exporter textfile collector. Can be a new module or added to existing `btrfs-compression.nix`.

**File:** `modules/system/btrfs-compression.nix` (add collector service + timer)
**OR** new module: `modules/system/btrfs-stats-monitor.nix`

**Verification:** `curl localhost:9100/metrics | grep btrfs`

---

## Issue 4: zram Swap I/O Blind Spot

**Problem:** zephyr OOMs regularly (31GB RAM across control plane + AI + gaming). zram swap activity invisible to disk metrics — no way to tell if swapping causes slowness.

**Fix:** Add zram monitoring via node_exporter textfile collector. Metrics include:
- `/sys/block/zram0/mm_stat` — compressed size, orig size, mem used
- `/sys/block/zram0/stat` — I/O operations on zram

Two approaches:
1. **Existing** — `node_exporter` collects `meminfo` which includes SwapTotal/SwapFree/SwapCached. Covers capacity but not I/O.
2. **Add** — shell script reading zram stats, exporting as Prometheus metrics via textfile collector.

**Recommended:** Add to same disk-latency-monitor script (or separate), collect `zram0/mm_stat` fields (orig_data_size, compr_data_size, mem_used_total) and `zram0/stat` (io count).

**File:** Same as Issue 2 script or separate

**Verification:** `curl localhost:9100/metrics | grep zram`

---

## Issue 5: I/O Pressure/Stall Not Tracked

**Problem:** PSI (Pressure Stall Information) at `/proc/pressure/io` gives real-time I/O contention signal. Not exposed anywhere.

**Fix:** Node exporter has a `pressure` collector (part of `--collector.pressure` flag). Current node-exporter config does NOT enable it.

**Change:** Add `"pressure"` to `enabledCollectors` in `modules/services/monitoring/node-exporter.nix`.

**Note:** This affects ALL hosts, not just zephyr. Run-note: verify on nexus/forge/sentry too.

**Verification:** `curl localhost:9100/metrics | grep pressure`

---

## Issue 6: NFS Export I/O Not Tracked Separately

**Problem:** NFS export traffic for `/data/hermes`, `/data/pi`, `/data/models` competes with local workloads on same NVMe. No way to tell if NFS is causing I/O contention.

**Fix:** Track NFS server metrics via `/proc/net/rpc/nfsd`. nfsd proc interface exposes:
- `proc/net/rpc/nfsd` — RPC counts, read/write ops, bytes
- Node exporter already collects `netdev` metrics on NFS-facing interface (eth0)

**Recommended:** Add nfsd stats to node-exporter via textfile collector script, or enable `--collector.nfsd` if node_exporter supports it (check: `prometheus-node-exporter --collector.nfsd`). If not, custom script.

**File:** Same textfile collector script as Issues 2/4, or separate

**Verification:** `curl localhost:9100/metrics | grep nfs`

---

## Issue 7: Data Drive Single Contention Point

**Problem:** `/data` (NVMe #2) hosts games, projects, archive, and some agent data. Gaming I/O + backup-to-garage (nightly) + syncthing + project builds all hit same drive. If NVMe #2 is a slower generation (e.g. PCIe 3.0 vs NVMe #1 at PCIe 4.0), contention is more meaningful.

**Fix options:**
1. **Document** — both are NVMe, bottleneck less severe than SATA. Monitor via new latency metrics.
2. **Move `/data/archive` to NVMe #1** — archive is cold storage, frees IOPS on data drive.
3. **Pin backup-to-garage to idle IO priority** — already at night (02:00).
4. **ionice on heavy services** — `btrfs-dedup-all` already uses `IOSchedulingClass = "idle"`.
5. **Identify NVMe generations** — check `/sys/block/nvme*/device/` for PCIe link speed.

**Recommended:** Document + option 2 (relocate `/data/archive` to NVMe #1) if free space permits.

---

## Implementation Order

| # | Issue | Effort | Impact | Priority |
|---|-------|--------|--------|----------|
| 1 | Enable sysstat.service | Trivial | Medium — unlocks historical I/O data | P1 |
| 5 | Enable PSI pressure collector | Trivial (1 line) | High — real-time I/O contention signal | P1 |
| 2 | Disk latency monitor | Small (script + service) | Medium — quantify slow I/O | P2 |
| 4 | zram swap monitoring | Small (extend same script) | Medium — detect swap-induced slowness | P2 |
| 3 | BTRFS device stats | Small (systemd timer) | Low — health signal, not performance | P3 |
| 6 | NFS export I/O tracking | Small (nfsd stats) | Low — nice to have | P3 |
| 7 | Move /data/archive | Medium (rsync + remount) | Low — marginal gain | P4 |

---

## Files Changed

| File | Change |
|------|--------|
| `hosts/zephyr/monitoring.nix` | Add `services.sysstat.enable = true;` |
| `modules/services/monitoring/node-exporter.nix` | Add `"pressure"` to enabledCollectors |
| `hosts/zephyr/services.nix` or new module | Add disk latency + zram + nfsd stats collection service |
| `modules/system/btrfs-compression.nix` or new module | Add btrfs device stats collection service |

---

## Acceptance Criteria

- [ ] `systemctl status sysstat.service` = active, `sar -d` returns historical data
- [ ] `curl localhost:9100/metrics | grep pressure` shows PSI metrics
- [ ] `curl localhost:9100/metrics | grep disk_latency` shows per-device avg latency
- [ ] `curl localhost:9100/metrics | grep zram` shows compression ratio + IO
- [ ] `curl localhost:9100/metrics | grep btrfs` shows device stats
- [ ] `curl localhost:9100/metrics | grep nfsd` shows NFS server RPC stats
- [ ] All existing Grafana disk panels still work
- [ ] `nix flake check` passes
- [ ] `just switch` on zephyr succeeds
