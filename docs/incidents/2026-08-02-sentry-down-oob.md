# Incident: Sentry (10.1.1.140) Offline — No Out-of-Band Recovery Path

**Date:** 2026-08-02
**Severity:** 🔴 Critical (monitoring + k8s control-plane node down, unrecoverable remotely)
**Status:** 🛠️ Resolving (OOB config added; PHYSICAL power-cycle still required on-site)
**Author:** ops (automated OOM audit + t_21884f04)
**Reviewer:** on-site operator (required to close)

---

## Executive Summary
Sentry has been unreachable for ~3 days (ARP FAIL from all hosts, Tailscale last
seen 3d ago). Root cause: the host is powered off / hard-hung with **no L2 reply**.
Critically, the NixOS inventory had **no out-of-band management** for sentry
(no IPMI/BMC/iLO/iDRAC, no WoL, no managed PDU/smart outlet, not virtualized),
so there was no remote recovery path. This incident record adds the OOB contract
(WoL + watchdog + escalation) and escalates the physical power-cycle.

## Impact
- Sentry is a k8s control-plane (server) node + monitoring host (Prometheus/Grafana/Loki/Alertmanager).
- While down: loss of its monitoring slice + one control-plane quorum member.
- No data loss expected (etcd state intact on disk); mining not affected (sentry CPU mining disabled).

## Timeline
| Time | Event |
|------|-------|
| ~2026-07-30 | Sentry last seen on Tailscale / L2 |
| 2026-08-02 07:0x | Daily OOM audit flags sentry UNKNOWN/DOWN, no OOB in inventory |
| 2026-08-02 | t_21884f04 filed: add OOB mgmt + escalate physical power-cycle |
| 2026-08-02 | OOB contract committed (WoL module + nexus watchdog + alert rule) |
| **TBD** | **On-site operator performs physical power-cycle (see below)** |
| **TBD** | Sentry returns; earlyoom/swap/zram verified; incident closed |

---

## ESCALATION — ACTION REQUIRED: PHYSICAL POWER-CYCLE
**Sentry is at the rack, powered off or hard-hung. There is no remote recovery.**

1. Go to the rack. Physically power-cycle sentry (10.1.1.140):
   - If soft-off: hold power button ~5s, wait 10s, power back on.
   - If hard-hung (fans/spin but no network): long-press power ~10s to force off, then power on.
2. Watch the host boot. It should rejoin the k3s cluster and Tailscale mesh.
3. Once it responds on `10.1.1.140` / Tailscale, verify on sentry (or from nexus):
   ```
   systemctl is-active earlyoom
   swapon --show
   zramctl
   journalctl -k | grep -i oom
   ```
4. Report the four outputs back so the audit (t_aa70469a) can be closed with sentry's real status.

## OOB Recovery Contract (now committed, deploys on next `just deploy nexus sentry`)
- **Wake-on-LAN** is the only software lever: sentry NIC MAC `70:85:c2:d2:87:bf` (lan0, r8169).
  Requires BIOS "Wake on LAN"/"PME" + PSU keeps NIC alive in S5.
- **Watchdog** `services.sentry-sentinel` runs on **nexus** (host that stays up). Every 5m it pings
  sentry; after 15m down it logs a `journalctl -t sentry-sentinel -p crit` entry and fires a WoL packet (30m cooldown).
  (In-sentry `HostDown` alerts are useless when sentry is the dead node — it runs its own Prometheus.)
- **No IPMI/BMC/PDU** exists in this hardware. If WoL is disabled in BIOS or inert, the fallback is this physical power-cycle.
- Runbook files: `hosts/sentry/oob-management.nix`, `modules/services/sentry-sentinel.{nix,sh}`, `etc/oob/sentry.txt` on sentry.

## Root Cause
Bare-metal host down/hard-hung, no L2 reply, no OOB management ⇒ unrecoverable remotely.
No kernel OOM on the *other* three hosts (zephyr/nexus/forge all earlyoom-active, 0 kernel kills).

## Follow-ups
- [ ] On-site power-cycle (blocker to close).
- [ ] Confirm BIOS WoL enabled so future outages self-heal via nexus watchdog.
- [ ] Consider a managed PDU / smart outlet on the rack for true OOB (hardware procurement).
- [ ] Verify earlyoom/swap/zram post-recovery; file result to t_aa70469a.
