# Cluster Hardware Inventory

**Last verified:** 2026-07-23
**K3s version:** v1.36.1+k3s1 (all nodes)

---

## Node Summary

| Node | IP | CPU | RAM | GPUs | Storage Total | Role |
|------|----|-----|-----|------|---------------|------|
| Zephyr | 10.1.1.110 | Ryzen 9 5950X 16C/32T | 31 GB | RTX 3090 24GB + RTX 3060 Ti 8GB | 1.9 TB NVMe | Control plane, workstation, K3s server |
| Nexus | 10.1.1.120 | Ryzen 9 3900X 12C/24T | 46 GB | RTX 3060 Ti 8GB | 5.2 TB (SSD+HDD) | Primary server, AI gateway, K3s server |
| Forge | 10.1.1.130 | Core i5-9500 6C/6T | 16 GB | RTX 4060 ×2 + RX 5700 XT ×2 | 462 GB SSD | GPU compute, mining, K3s worker |
| Sentry | 10.1.1.140 | Ryzen 7 1700 8C/16T | 31 GB | RX 5600 XT 6GB | 1.2 TB (SSD+HDD) | Monitoring, logging, K3s server |

---

## Detailed Host Data

### Zephyr

| Field | Value |
|-------|-------|
| Motherboard | MSI MAG X570 TOMAHAWK WIFI (MS-7C84), BIOS 1.K1 |
| CPU | AMD Ryzen 9 5950X — 16C/32T, 3.4 GHz base |
| RAM | 31 GB |
| GPU 0 | RTX 3060 Ti — 8 GB GDDR6, PCIe 24:00.0, 200W |
| GPU 1 | RTX 3090 — 24 GB GDDR6X, PCIe 2D:00.0, 350W |
| Storage | `nvme0n1` XPG GAMMIX S11 Pro 953.9 GB → `/` `/nix` |
| | `nvme1n1` Samsung SSD 980 1TB 931.5 GB → `/home` |
| Network | `enp38s0` 10.1.1.110/24, `tailscale0` 100.102.39.25 |
| K3s | Server (control plane) |
| **gputemps GDDR6X** | ❌ Not enabled |

### Nexus

| Field | Value |
|-------|-------|
| Motherboard | Gigabyte X470 AORUS ULTRA GAMING-CF, BIOS F65d |
| CPU | AMD Ryzen 9 3900X — 12C/24T, 3.8 GHz base |
| RAM | 46 GB |
| GPU 0 | RTX 3060 Ti — 8 GB GDDR6, 120W (undervolted) |
| Storage | `nvme0n1` WD SN550 931.5 GB NVMe → `/` |
| | `nvme1n1` Kingston SA1000M8240G 223.6 GB NVMe |
| | `sda` Seagate ST4000VN008 3.6 TB HDD → `/data` |
| | `sdb` Samsung 860 EVO 500 GB SATA SSD |
| Network | `eth0` 10.1.1.120/24 + VIP 10.1.1.100/24 |
| K3s | Server (control plane) |

### Forge

| Field | Value |
|-------|-------|
| Motherboard | MSI B360-F PRO (MS-7B25), BIOS 1.C0 |
| CPU | Intel Core i5-9500 — 6C/6T, 3.0 GHz (no Hyper-Threading) |
| RAM | 16 GB |
| GPU 0 | RTX 4060 — 8 GB GDDR6, PCIe 0F:00.0, 110W |
| GPU 1 | RTX 4060 — 8 GB GDDR6, PCIe 11:00.0, 110W |
| GPU 2 | RX 5700 XT — 8 GB GDDR6 |
| GPU 3 | RX 5700 XT — 8 GB GDDR6 |
| Storage | `sda` ADATA SU635 223.6 GB SATA SSD → `/` |
| | `sdb` TEAM T253X2256G 238.5 GB SATA SSD → `/nix` `/home` |
| Network | `eth0` 10.1.1.130/24 |
| K3s | Worker node |
| **gputemps GDDR6X** | ✅ Enabled (`iomem=relaxed` set) |

### Sentry

| Field | Value |
|-------|-------|
| Motherboard | ASRock B450M-HDV R4.0, BIOS P4.80 |
| CPU | AMD Ryzen 7 1700 — 8C/16T, 3.0 GHz |
| RAM | 31 GB |
| GPU 0 | RX 5600 XT — 6 GB GDDR6, PCIe, 120W |
| Storage | `sda` Seagate ST1000DM010 931.5 GB HDD → `/storage` |
| | `sdb` Micron 1100 256 GB SATA SSD → `/` |
| Network | `eth0` 10.1.1.140/24 |
| K3s | Server (control plane) |
| SMT | Re-enabled via `enable-smt.service` |

---

## Temperature Thresholds

| Component | Cool | Warm | Hot | Critical |
|-----------|------|------|-----|----------|
| GDDR6 Tjunction | <85°C | 85-95°C | 95-100°C | **100°C** |
| GDDR6X Tjunction | <85°C | 85-95°C | 95-105°C | **105-110°C** |
| NVIDIA GPU core | <70°C | 70-80°C | 80-85°C | **91°C** |
| AMD GPU edge | <75°C | 75-85°C | 85-95°C | **100°C** |
| AMD GPU junction | <80°C | 80-90°C | 90-100°C | **105°C** |
| AMD GPU memory | <80°C | 80-90°C | 90-100°C | **100°C** |
| CPU (AMD Zen) | <60°C | 60-75°C | 75-85°C | **95°C** |
| CPU (Intel) | <60°C | 60-75°C | 75-85°C | **100°C** |
| AIO liquid | <35°C | 35-45°C | 45-55°C | **60°C** |
| NVMe SSD | <50°C | 50-60°C | 60-70°C | **70°C** |
| HDD | <35°C | 35-45°C | 45-50°C | **55°C** |

Sources: Micron GDDR6/GDDR6X datasheet, NVIDIA NVML, AMD ROCm, JEDEC.

---

## Sensor Stack Status

| | Zephyr | Nexus | Forge | Sentry |
|--|--------|-------|-------|--------|
| node-exporter (CPU, disk, net) | ✅ | ✅ | ✅ | ✅ (hub) |
| NVIDIA GPU (core, power) | ✅ :9400 | ✅ :9400 | ✅ :9400 | — |
| AMD GPU (edge/junction/mem) | — | — | ✅ textfile | ✅ textfile |
| gputemps GDDR6X per-module | ❌ | — | ✅ | — |
| SMART disk health | ❌ | ✅ | ✅ | ✅ |
| Prometheus | — | — | — | ✅ |
| Grafana | — | — | — | ✅ |
| Alertmanager | — | — | — | ✅ |
| Loki logging | — | — | — | ✅ |
| Self-healing alerts | — | — | — | ✅ |
| RGB temp-reactive | ✅ | ✅ | ✅ | ✅ |

### Open Gaps

1. **Zephyr: gputemps GDDR6X** — RTX 3090 memory runs 20-30°C over core, throttles at 110°C. Needs `gputemps-exporter.enable = true` + `iomem=relaxed` kernel param.
2. **Zephyr: SMART disk** — No disk health monitoring on either NVMe.
3. **GPU exporter configs** — Split between `hardware.nix` and `monitoring.nix`. Should be unified.
