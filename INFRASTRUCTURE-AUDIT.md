# Infrastructure Audit — 2025-04-15

## Cluster Overview

| Host | CPU | RAM | Swap | GPUs | Disk | Load | Uptime |
|------|-----|-----|------|------|------|------|--------|
| **Zephyr** | 16c | 31GB | 39GB (11GB used ⚠️) | RTX 3060 Ti 8GB + RTX 3090 24GB | - | - | 5d |
| **Nexus** | 24c | 46GB (28GB avail) | 15GB (206MB) | RTX 3060 Ti 8GB @100% | 915GB (36%) | 6.2 | 5d |
| **Forge** | 6c | 15GB (5.2GB avail) | 19GB (88MB) | 2× RX 5600 XT + 2× RTX 4060 @100% | 230GB (81% ⚠️) | 0.01 | 3d |
| **Sentry** | 16c | 31GB (15GB avail) | 8GB (843MB) | RX 5600 XT 6GB | 230GB (73%) | 8.3 | 5d |

**Total**: 78 cores, 123GB RAM, 7 GPUs (3 NVIDIA + 4 AMD), 8.4TB storage

---

## P0 — Critical (Fix Now)

### 🔴 68% of Prometheus targets are DOWN
Only 7/22 targets scrape successfully. We're flying blind on most metrics.

| Target | Status | Fix |
|--------|--------|-----|
| node-exporter forge | DOWN | Check firewall/port 9100 |
| node-exporter zephyr | DOWN | Check k3s iptables interference |
| nvidia-gpu zephyr/nexus/forge | ALL DOWN | Install/configure dcgm-exporter |
| mining zephyr/nexus/forge | DOWN | Check mining-exporter binding |
| redis zephyr:9121 | DOWN | Check redis-exporter |
| garage zephyr/nexus/sentry | DOWN | Garage service not running |
| caddy-ingress | DOWN | K8s service not reachable |
| ai-inference-gateway | DOWN | K8s service not reachable |

### 🔴 No alerting rules configured
`rule_files: []` in Prometheus config. Zero alerts despite having Alertmanager running on 2 hosts.

### 🔴 Zephyr thermal alarm
`Tctl: +70.9°C` on k10temp with ALARM flag. Needs investigation — likely the RTX 3090 dumping heat.

### 🔴 Nexus thermal concern
`Tctl: +87.9°C` — very hot for a mining node. May need fan curve adjustment.

### 🔴 Forge disk at 81%
230GB disk, only 44GB free. Mining logs? Docker images? Needs cleanup.

---

## P1 — Monitoring Gaps

### 🟡 No AMD GPU metrics
Forge has 2× RX 5600 XT, Sentry has 1× RX 5600 XT — zero GPU metrics exported.
Need: `rocm-smi` exporter or `amd_gpu` node-exporter collector.

### 🟡 No NVIDIA GPU metrics
All 3 NVIDIA hosts (zephyr, nexus, forge) have dcgm-exporter configured but DOWN.
Need: Fix DCGM exporter or switch to `nvidia-smi` textfile collector.

### 🟡 Loki ingester not ready on sentry
Log aggregation service exists but is broken. `Ingester not ready: waiting for 15s after being ready`.

### 🟡 Duplicate monitoring stack
Prometheus + Grafana + Alertmanager running on BOTH nexus AND sentry. Redundant, wastes resources.
Action: Consolidate to nexus (46GB RAM) as single observability hub.

### 🟡 No benchmark tools installed
No sysbench, fio, iperf3 (except zephyr), stress-ng, phoronix, gpu-burn installed anywhere.

### 🟡 No network performance baseline
Unknown inter-node bandwidth. 10Gbps on main NICs but untested.

---

## P2 — Security Gaps

### 🟠 llama-server exposed on 0.0.0.0
Both zephyr (port 1235) and sentry (port 1235) bind to all interfaces.
Should bind to 10.1.1.x (LAN only) or 127.0.0.1 + Tailscale proxy.

### 🟠 Grafana exposed on 0.0.0.0 (nexus:3000)
No anonymous access (good), but auth behind plain HTTP on LAN.
Should be behind Caddy with TLS or restricted to Tailscale.

### 🟠 AI inference gateway metrics on 0.0.0.0:9190
Exposed on all hosts. Should be 127.0.0.1 or LAN-only.

### 🟠 Mining exporter on 0.0.0.0:9105
Exposed on all hosts. Read-only but leaks mining data.

### 🟠 Multiple high ports exposed
Zephyr: 3333, 3456, 8080, 8082, 8222, 8644 — unclear what these are.

### 🟠 etcd ports accessible on LAN
2379/2380 bound to LAN IP on zephyr/nexus/sentry. Should be restricted to cluster nodes only.

### 🟠 fail2ban only on zephyr + forge
nexus and sentry have no fail2ban. All hosts have SSH exposed.

### 🟠 No USB guard on most hosts
Only forge has usbguard. Other 3 hosts accept arbitrary USB devices.

---

## P3 — Operational Issues

### 🔵 backup-to-garage.service FAILED on zephyr
Garage S3 is down on all 3 nodes. Backups are not happening.

### 🔵 nixos-auto-update FAILED on forge
Auto-update service failing. No auto-update on sentry at all.

### 🔵 keepalived failing on some nodes
Previously noted as pre-existing. VIP failover may be broken.

### 🔵 Spotify listening on 0.0.0.0:57155 on zephyr
User app exposing ports unnecessarily.

### 🔵 lm-studio + llamafile dual inference on zephyr
Both LM Studio (port 1234) and llamafile (port 1235) running on zephyr. Redundant.

### 🔵 WiVRn server exposed on 0.0.0.0:9757 (zephyr + nexus)
VR streaming server on all interfaces.

---

## P4 — Optimization Opportunities

### ⚡ Consolidate observability to nexus
Single Prometheus + Grafana + Alertmanager on nexus (46GB RAM, low utilization).

### ⚡ Add benchmark tools to all hosts
- `iperf3` — network throughput
- `fio` — disk I/O
- `sysbench` — CPU/memory
- `gpu-burn` — GPU stress test (NVIDIA)
- `rocm-bandwidth-test` — AMD GPU bandwidth

### ⚡ Fix NVIDIA power limits
- Forge RTX 4060: limited to 90W (could be 115W for more mining perf)
- Nexus RTX 3060 Ti: at 150W (max)
- Zephyr RTX 3090: at 245W — check if PL1/PL2 optimized

### ⚡ Forge storage optimization
81% disk usage. Audit and clean:
- Docker/container images
- Mining logs
- Old nix generations

### ⚡ Zephyr swap optimization
11GB swapped on 31GB RAM. Earlyoom running but may need tuning.
Consider reducing workloads (mining + AI + gaming = too much for 31GB).

### ⚡ Sentry load average 8.3 on 16 cores
51% CPU despite being a monitoring + inference node. Investigate what's consuming CPU.

---

## Observability Stack — Current vs Target

| Component | Current | Target |
|-----------|---------|--------|
| Prometheus | 2 instances (nexus+sentry) | 1 on nexus |
| Grafana | 2 instances (nexus+sentry) | 1 on nexus |
| Alertmanager | 2 instances | 1 on nexus |
| Loki | 1 on sentry (broken) | Fix on nexus |
| Node Exporter | 4 hosts (2 down) | 4 hosts, all up |
| NVIDIA Exporter | 3 hosts (all down) | 3 hosts, all up |
| AMD GPU Exporter | NONE | 2 hosts (forge+sentry) |
| Mining Exporter | 4 (3 down) | 4, all up |
| Redis Exporter | 1 (down) | 1 on zephyr |
| Smart/ Disk | NONE | All hosts via smartctl |
| Alert Rules | ZERO | CPU, RAM, disk, GPU temp, mining |

---

## Plan — Execution Order

### Phase 1: Fix Broken Monitoring (1-2 hours)
1. Fix node-exporter on forge (firewall?)
2. Fix NVIDIA GPU exporter on zephyr/nexus/forge
3. Fix mining exporter on zephyr/nexus/forge
4. Fix redis exporter on zephyr
5. Add AMD GPU exporter for forge + sentry

### Phase 2: Consolidate Observability (1 hour)
1. Remove duplicate Prometheus/Grafana/Alertmanager from sentry
2. Point all scrape targets to nexus Prometheus
3. Fix Grafana datasources on nexus
4. Fix Loki ingester

### Phase 3: Alerting Rules (30 min)
1. Add CPU > 90% for 5m alert
2. Add RAM > 90% alert
3. Add disk > 85% alert
4. Add GPU temp > 85°C alert
5. Add node down alert (1m scrape missing)
6. Add mining hashrate drop alert
7. Add systemd unit failed alert

### Phase 4: Security Hardening (1-2 hours)
1. Bind llama-server to LAN IP only (not 0.0.0.0)
2. Bind AI gateway metrics to 127.0.0.1
3. Add fail2ban to nexus + sentry
4. Restrict etcd to cluster node IPs only
5. Audit and close unnecessary 0.0.0.0 bindings

### Phase 5: Benchmarks & Baselines (1 hour)
1. Install iperf3 on all hosts, run mesh bandwidth test
2. Install fio, run disk I/O benchmarks
3. Run GPU stress tests on all GPUs
4. Document baseline numbers in wiki

### Phase 6: Operational Fixes (30 min)
1. Fix backup-to-garage (or replace with alternative)
2. Fix nixos-auto-update on forge
3. Clean forge disk (audit large files)
4. Investigate zephyr thermal alarm
5. Investigate nexus 87°C thermal issue
