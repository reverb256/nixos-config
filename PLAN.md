# Infrastructure Hardening Plan

**Date:** 2026-04-22 | **Branch:** feature/brain-v2-embedding-first | **Status:** Draft

## Current State Summary

The cluster runs 4 NixOS nodes (zephyr, nexus, forge, sentry) with K3s, Unbound DNS,
Caddy ingress, and a keepalived VIP. An audit revealed several systemic issues:

1. **Keepalived is crash-looping** on all nodes — wrong interface name (`enp38s0` on zephyr,
   where the actual interface is `eth0`). The VIP (10.1.1.100) is dead, yet K3s workers
   reference it for the API server.
2. **~10 hardcoded IPs** in service configs instead of using the canonical
   `networking.cluster` option or `.lan` names.
3. **Stale Tailscale domain** — config references `tigris-ule.ts.net` everywhere,
   but the actual tailnet is `taila21e09.ts.net`.
4. **DNS split-brain** — Unbound and K8s CoreDNS both define `.lan` records with
   different IPs for `search.lan` (Unbound: 10.1.1.120, CoreDNS: 10.1.1.100/VIP).
5. **Single point of failure** — all `.lan` services point to nexus directly; no
   HA if nexus goes down.
6. **cluster-services module on nexus** uses a mix of ClusterIPs and hardcoded node IPs
   for backends.

---

## Phase 1: Fix Keepalived (Unblocks VIP, K3s HA)

### Problem
Keepalived crash-loops because `zephyr/services.nix` references `interface = "enp38s0"`
which doesn't exist — zephyr's actual LAN interface is `eth0`. The interface name changed
at some point (likely hardware swap or kernel upgrade).

### Fix
- Change `interface = "enp38s0"` to `interface = "eth0"` in `/etc/nixos/hosts/zephyr/services.nix:28`
- Verify sentry's `interface = "enp7s0"` is still correct (it was correct as of last check)
- Add `clusterNetworking.interfaceName` to zephyr's configuration.nix (currently missing —
  this is the root cause; zephyr is the only node without it)

### Files
- `/etc/nixos/hosts/zephyr/services.nix` — line 28: `enp38s0` -> `eth0`
- `/etc/nixos/hosts/zephyr/configuration.nix` — add `interfaceName = "eth0"` to `clusterNetworking`
- `/etc/nixos/hosts/zephyr/firewall.nix` — line 45/55: `"enp38s0"` -> `"eth0"` (firewall rules reference the old interface name)

### Verification
- `just switch` then `systemctl status keepalived` on zephyr — should be active
- `ip addr show eth0 | grep 10.1.1.100` — VIP should be bound
- K3s agents (sentry, forge) should remain connected (they were already reaching the
  API via direct node IPs despite the VIP config, since K3s has embedded etcd)

### Risk
Low. Keepalived is currently dead so it can't get worse. The VIP is only used by K3s
server join and CoreDNS NodeHosts — both of which already work around it.

---

## Phase 2: Centralize Network Constants in Service Modules

### Problem
Multiple service modules hardcode IPs (`10.1.1.120`, `10.1.1.110`, `10.1.1.140`)
instead of reading from `config.networking.cluster.hosts.<name>.ip`. This means
any IP change requires editing every service module individually.

### Fix
Replace hardcoded IPs with references to `config.networking.cluster`:

| File | Line | Current | Replacement |
|---|---|---|---|
| `modules/services/hermes-cli.nix` | 109,115 | `http://10.1.1.120:8080/v1` | `http://${config.networking.cluster.hosts.nexus.ip}:8080/v1` |
| `modules/services/vane.nix` | 11 | `http://10.1.1.120:30888` | `http://${config.networking.cluster.hosts.nexus.ip}:30888` |
| `modules/services/binary-cache.nix` | 21 | `10.1.1.110` | `config.networking.cluster.hosts.zephyr.ip` |
| `modules/services/cluster-services.nix` | 67 | `default = "10.1.1.120"` | `default = config.networking.cluster.hosts.nexus.ip` |
| `hosts/zephyr/services.nix` | 35 | `http://10.1.1.110:3900` | `http://${config.networking.cluster.hosts.zephyr.ip}:3900` |
| `hosts/zephyr/services.nix` | 281 | `http://10.1.1.120:30888` | `http://${config.networking.cluster.hosts.nexus.ip}:30888` |
| `hosts/sentry/services.nix` | (promtail) | `http://10.1.1.140:3100` | `http://${config.networking.cluster.hosts.sentry.ip}:3100` |
| `modules/services/nixos-share.nix` | 18-20,30 | nexus/forge/sentry IPs | `config.networking.cluster.hosts.<name>.ip` |

### HAProxy Exception
`haproxy-ingress.nix` and `haproxy-lb.nix` reference backend server IPs — these are
LB pool member definitions and **should** use literal IPs (they define the pool, not
consume it). No change needed.

### Verification
- `nix flake check --no-build`
- Grep for remaining `10.1.1.` literals in `modules/services/` and `hosts/*/services.nix`
  (excluding HAProxy, NixOS module options, and comments)

### Risk
Low. Pure refactor — no behavioral change. The resolved values are identical.

---

## Phase 3: Fix Stale Tailscale Domain

### Problem
4 files reference `tigris-ule.ts.net` which is a dead tailnet. The actual tailnet is
`taila21e09.ts.net`. The stale domain causes:
- Broken references in grafana config, browser vaultwarden URL, search domain list
- `dig zephyr.tigris-ule.ts.net` times out (NXDOMAIN)

### Fix
- Update `network-constants.nix` line 67: `domain = "tigris-ule.ts.net"` -> `"taila21e09.ts.net"`
- Update `cluster-networking.nix` line 96: search domain
- Update `modules/home-manager/zen-browser.nix` line 582: vaultwarden URL
- Update `modules/services/monitoring/grafana-v2.nix` line 19: sentry domain

### Verification
- `dig zephyr.taila21e09.ts.net +short` returns `100.76.234.6`
- Grep for remaining `tigris-ule` references — should be zero

### Risk
Low. The old domain doesn't resolve at all. The new domain is already live.

---

## Phase 4: Resolve DNS Split-Brain (Unbound vs CoreDNS)

### Problem
Two DNS authorities define `.lan` records independently:
- **Unbound** (system-level): `search.lan` -> `10.1.1.120` (nexus)
- **CoreDNS** (K8s-internal): `search.lan` -> `10.1.1.100` (VIP)

LAN clients use Unbound (which doesn't have the VIP). K8s pods use CoreDNS (which does).
Once keepalived is fixed, Unbound should also point to the VIP for services that
should be HA.

### Approach
This is a design decision, not a simple fix. Two options:

**Option A: Make Unbound the single source of truth for `.lan`**
- Remove duplicate `.lan` records from CoreDNS NodeHosts
- Update Unbound local-data to point service records to the VIP (once keepalived works)
- Pros: one DNS authority, LAN clients and K8s pods see the same answers
- Cons: K8s pods would need to forward `.lan` queries to Unbound instead of CoreDNS

**Option B: Keep DNS split but align the records**
- Update Unbound service records to match CoreDNS (VIP instead of nexus IP)
- Accept that K8s internal resolution is separate from LAN resolution
- Pros: K8s DNS stays self-contained, standard K3s setup
- Cons: still two authorities to maintain

**Recommendation: Option B** — K3s CoreDNS managing its own NodeHosts is standard
behavior. Align Unbound's service `.lan` records to use the VIP once keepalived is
confirmed working. Don't break K8s DNS self-containment.

### Changes (deferred until Phase 1 is verified)
- `/etc/nixos/modules/services/unbound-common.nix` — change service `.lan` records
  from `10.1.1.120` to `10.1.1.100` (VIP)
- CoreDNS NodeHosts already points to VIP — no change needed

### Verification
- `dig search.lan @10.1.1.110` returns `10.1.1.100` (VIP)
- `dig search.lan @10.4.0.10` returns `10.1.1.100` (VIP, unchanged)
- Stop nexus, verify `search.lan` still resolves via VIP on zephyr

### Risk
Medium. If keepalived fails over but Caddy isn't running on the backup node,
services go dark. Caddy runs as a K8s Deployment pinned to nexus — the VIP alone
doesn't provide application-level HA. This is documented as a known limitation.

---

## Phase 5: Consolidate cluster-services Backends

### Problem
The `cluster-services` module on nexus uses a mix of ClusterIPs (e.g., `10.4.98.141:8080`)
and hardcoded node IPs (e.g., `10.1.1.120:8080` for `ai.lan`). ClusterIPs are stable
within a K8s cluster but opaque and not self-documenting. Node IPs are fragile if
services move.

### Approach
This is a K8s service discovery concern. The cluster-services module already generates
Caddy virtualHosts — the backend addresses should reference K8s Service names where
possible, or use ClusterIPs with a comment mapping them to service names. Changing
to K8s DNS (`service.namespace.svc.cluster.local`) would require Caddy to resolve
via CoreDNS.

**Recommendation: leave as-is for now.** The current mix works because Caddy runs on
the same node (nexus) as the K8s API. ClusterIPs are stable. The real fix is
moving Caddy to a DaemonSet so it runs on every node, but that's a larger
architectural change.

### Verification
N/A — no changes in this phase.

---

## Execution Order

| Step | Phase | Depends On | Risk |
|---|---|---|---|
| 1 | Phase 1 (keepalived) | None | Low |
| 2 | Phase 2 (hardcoded IPs) | None | Low |
| 3 | Phase 3 (Tailscale domain) | None | Low |
| 4 | Phase 4 (DNS split-brain) | Phase 1 | Medium |
| 5 | Phase 5 (cluster-services) | Deferred | N/A |

Phases 1-3 are independent and can be done in parallel. Phase 4 depends on Phase 1
(VIP must be alive before pointing DNS to it). Phase 5 is deferred.

---

## Open Questions

1. **Caddy HA**: All `.lan` services terminate on Caddy running on nexus. If nexus
   goes down, the VIP floats but Caddy doesn't. Should Caddy become a DaemonSet
   with a shared TLS cert? This is the real single-point-of-failure, not DNS.
2. **`ai.lan` and `api.hermes.lan` return 404**: The backends are reachable (Caddy
   proxies successfully) but the applications themselves return 404. Is this expected
   (not yet deployed)? Or misconfigured?
3. **Forge is `Unknown` in K3s**: `kubectl get nodes` shows forge as `Unknown` status
   (17 days). This may be unrelated to DNS but worth investigating.
