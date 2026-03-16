# Architectural Decision Log

**Purpose:** Record architectural decisions, their rationale, and alternatives considered
**Status:** Active | **Created:** 2026-03-16 | **Last Updated:** 2026-03-16 (Git History Analysis) | **Owner:** j_kro

> **Why This Matters:** Prevents re-litigating settled decisions and provides context for future changes.
> **Decision Count:** 19 recorded decisions spanning storage, networking, control plane, AI/gateway, compute, and containerization.

---

## Quick Reference

| # | Decision | Status | Category | Impact |
|---|----------|--------|----------|--------|
| 001 | Keepalived VIP (no HAProxy) | ✅ | Control Plane | Simpler HA architecture |
| 002 | 3-Master etcd (not 5) | ✅ | Control Plane | Quorum with fewer nodes |
| 003 | Single-Node Garage | ✅ | Storage | Simplified from 3-way |
| 004 | Local-Path Provisioner | ✅ | Storage | No Longhorn complexity |
| 005 | Caddy Ingress (not NGINX) | ✅ | Networking | HTTP/3 support |
| 006 | GPU Marketplace | ✅ | Compute | Dynamic allocation |
| 007 | Full K8s Migration Paused | ⏸️ | Roadmap | Hybrid approach working |
| 008 | Z.AI MCP Abandoned | ❌ | Gateway | 401 errors |
| 009 | VIP IPv4 Workaround | ⚠️ | Networking | Direct IP for Sentry |
| 010 | Pod CIDR Migration | ✅ | Networking | 10.244.0.0/16 |
| 011 | Native Interface Names | ✅ | Networking | Reverted "lan0" |
| 012 | x86-64-v3 Partial | ⚠️ | Build | Some components reverted |
| 013 | Harmonia Cache Disabled | ❌ | Build | Caused timeouts |
| 014 | Akash Helm Fix | ✅ | Fix | Package collision |
| 015 | Centralized GPU Proxy | ✅ | Compute | Forge protocol translation |
| 016 | Compute-Workload-Monitor | ✅ | Compute | Evolved from minepause |
| 017 | Podman Deferred | ⏸️ | Containerization | Docker Hub issue |
| 018 | Initial Architecture | ✅ | Foundation | 4-host cluster |

> **Why This Matters:** Prevents re-litigating settled decisions and provides context for future changes.

---

## Decision Template

```markdown
### Decision: [Title]

**Date:** YYYY-MM-DD
**Status:** Accepted | Deprecated | Superseded
**Context:** What problem were we solving?
**Decision:** What did we decide?
**Alternatives Considered:** What other options did we evaluate?
**Consequences:** What changed as a result?
**Revert Cost:** What would it take to change this decision?
```

---

## Control Plane & High Availability

### Decision 001: Keepalived VIP instead of HAProxy

**Date:** 2026-03-16 (retroactive - implementation date earlier)
**Status:** ✅ Accepted
**Context:** Needed high-availability API server access for 3-node control plane

**Decision:** Use Keepalived VIP (10.1.1.100) directly without HAProxy layer

**Alternatives Considered:**
| Option | Pros | Cons | Decision |
|--------|------|-------|----------|
| **Keepalived VIP only** | Simple, VRRP standard, low latency | No L4 proxy features | ✅ CHOSEN |
| HAProxy + Keepalived | L4 load balancing, health checks | More complex, another failure point | ❌ Rejected |
| kube-vip | Kubernetes-native, integrated | Less mature, fewer docs | ❌ Not evaluated |

**Rationale:**
- 3-node cluster small enough that direct API access is sufficient
- Keepalived is battle-tested for VIP failover
- Reduced complexity = fewer failure modes
- API servers can handle direct connections

**Consequences:**
- API server must be accessible on all master nodes (port 6443)
- No L4 proxy-level health checks (API server fails its own health)
- Simpler troubleshooting (fewer layers)

**Revert Cost:** **Medium** (4-8 hours)
- Deploy HAProxy DaemonSet on all 3 masters
- Update Keepalived config to point to HAProxy
- Test failover scenarios
- Update documentation

**Documentation:**
- Implementation: `docs/kubernetes/control-plane-architecture.md`
- Config: `modules/services/kubernetes.nix`, host configs

---

### Decision 002: 3-Master etcd Cluster (Not 5)

**Date:** 2026-03-08 (planning)
**Status:** ✅ Accepted
**Context:** Choosing etcd cluster size for HA control plane

**Decision:** 3-node etcd cluster (Zephyr, Nexus, Sentry)

**Alternatives Considered:**
| Option | Pros | Cons | Decision |
|--------|------|-------|----------|
| **3-node cluster** | Simpler, fewer nodes, adequate quorum | Can only lose 1 node | ✅ CHOSEN |
| 5-node cluster | Can lose 2 nodes | More complex, more nodes | ❌ Rejected |
| Single node | Simplest | No HA, SPOF | ❌ Rejected |

**Rationale:**
- 4-host cluster limits our options
- Quorum of 2/3 sufficient for homelab
- etcd on control plane nodes (no dedicated etcd nodes)

**Consequences:**
- Loss of 2 masters = etcd quorum lost = cluster read-only
- Must prioritize master node availability

**Revert Cost:** **High** (requires more hardware)

---

## Storage Architecture

### Decision 003: Single-Node Garage (Not 3-Way Replication)

**Date:** 2026-03-16 (retroactive - simplified from original plan)
**Status:** ✅ Accepted
**Context:** Needed S3-compatible object storage for cluster workloads

**Decision:** Deploy Garage in single-node mode with `replicationFactor = 1`

**Alternatives Considered:**
| Option | Pros | Cons | Decision |
|--------|------|-------|----------|
| **Single-node Garage** | Simple, less storage overhead | No data redundancy | ✅ CHOSEN |
| 3-way Garage replication | Data durability, quorum | 3x storage cost, complexity | ❌ Planned but dropped |
| MinIO | More mature, faster | No distributed mode in free tier | ❌ Not evaluated |
| External S3 (AWS, Wasabi) | Fully managed | Cost, egress fees | ❌ Rejected |

**Rationale:**
- Homelab data not critical enough to justify 3x storage overhead
- Backups provide sufficient durability for non-production
- Single node on Nexus (4.7TB storage) adequate
- Complexity of distributed cluster not justified for use case

**Current Configuration:**
```nix
# modules/services/akash-provider.nix:414
replicationFactor = 1;  # Single-node mode
```

**Consequences:**
- No automatic data redundancy if Garage fails
- 3.6TB usable instead of ~1.2TB with 3-way replication
- S3 API available at `http://10.1.1.120:3900`
- Manual backups required

**Revert Cost:** **Low-Medium** (2-4 hours)
- Update `replicationFactor = 3`
- Deploy Garage on 2 more nodes (Zephyr, Sentry)
- Migrate existing data
- Update documentation

**Documentation:**
- Correct: `docs/kubernetes/storage/storage-architecture.md`
- Incorrect (archived): `docs/storage-architecture.md` (claimed 3-way)

**To Revert If:**
- Production workloads need higher durability
- Additional nodes provisioned for storage
- Regulatory requirements emerge

---

## Kubernetes Storage

### Decision 004: Local-Path Provisioner (Not Longhorn)

**Date:** 2026-03-16 (retroactive)
**Status:** ✅ Accepted
**Context:** Need persistent storage for Kubernetes workloads

**Decision:** Use local-path provisioner instead of distributed block storage (Longhorn)

**Alternatives Considered:**
| Option | Pros | Cons | Decision |
|--------|------|-------|----------|
| **Local-path provisioner** | Simple, built-in, fast | Node-local only | ✅ CHOSEN |
| Longhorn | Distributed, replication | Complex, resource-heavy | ❌ Planned but dropped |
| NFS for everything | Simple, shared | Slow, single point of failure | ⚠️ Complementary |
| Ceph RBD | Enterprise-grade | Very complex, overkill | ❌ Not evaluated |

**Rationale:**
- Homelab workloads don't need distributed storage complexity
- Stateful workloads (DBs) run on specific nodes via node affinity
- NFS handles shared storage requirements
- Longhorn resource overhead not justified

**Consequences:**
- PVs tied to specific nodes (pod must schedule on same node)
- No automatic replication/migration
- Simpler operations, fewer moving parts

**Revert Cost:** **Medium** (4-6 hours)
- Deploy Longhorn cluster
- Migrate PVs to Longhorn
- Update storage classes
- Test failover

**Documentation:**
- `docs/kubernetes/storage/storage-architecture.md`

---

## Ingress & Networking

### Decision 005: Caddy Ingress (Not NGINX)

**Date:** 2026-03-14
**Status:** ✅ Accepted
**Context:** Needed ingress controller for Kubernetes workloads

**Decision:** Deploy Caddy Ingress Controller instead of NGINX Ingress

**Alternatives Considered:**
| Option | Pros | Cons | Decision |
|--------|------|-------|----------|
| **Caddy Ingress** | HTTP/3, auto HTTPS, simple config | Less common than NGINX | ✅ CHOSEN |
| NGINX Ingress | Most popular, extensive docs | No HTTP/3, more complex | ❌ Planned but dropped |
| Traefik | Great UX, auto discovery | Resource-heavy | ❌ Not evaluated |

**Rationale:**
- HTTP/3 (QUIC) support for better performance
- Automatic HTTPS (Let's Encrypt or internal CA)
- Simpler Caddyfile configuration vs NGINX config
- Already using Caddy for systemd services

**Consequences:**
- Less community knowledge than NGINX
- Caddyfile syntax to learn
- DaemonSet model (vs Deployment for NGINX)

**Current Deployment:**
- DaemonSet on nexus, sentry (2 pods)
- NodePort: 30080 (HTTP), 30443 (HTTPS)
- Routes: ai.cluster.local, search.cluster.local, echo.cluster.local

**Revert Cost:** **Low** (2-3 hours)
- Deploy NGINX Ingress Controller
- Migrate routes to NGINX annotations
- Update DNS if needed

**Documentation:**
- `docs/kubernetes/caddy-ingress.md`

---

## GPU Resource Management

### Decision 006: GPU Resource Marketplace (Not Static Partitioning)

**Date:** 2026-03-14
**Status:** ✅ Accepted
**Context:** Multiple competing workloads need GPU access (mining, Kubernetes, Akash, gaming)

**Decision:** Deploy auction-based GPU Resource Marketplace instead of static partitioning

**Alternatives Considered:**
| Option | Pros | Cons | Decision |
|--------|------|-------|----------|
| **Auction marketplace** | Dynamic allocation, fair, prioritizable | More complex | ✅ CHOSEN |
| Static partitioning | Simple, predictable | Wasteful, inflexible | ❌ Replaced |
| Time-based scheduling | Simple | Poor responsiveness | ❌ Not evaluated |

**Rationale:**
- GPU workloads have different priorities and values
- Mining (baseline) should yield to higher-value work (AI, gaming)
- Akash leases need preemption capability
- Marketplace model enables fair compensation

**Current Architecture:**
- Bidders: Mining (baseline), Kubernetes (AI workloads), Akash (leases), Gaming (override)
- Auction engine runs every 30 seconds
- Winners expose GPUs via `/dev/nvidiaX` symlinks

**Revert Cost:** **Medium** (3-4 hours)
- Disable marketplace
- Configure static GPU allocations
- Update all consumers

**Documentation:**
- `docs/compute-market.md`
- `modules/compute-market/default.nix`

---

## Roadmap Items Deferred/Dropped

### Decision 007: Full Kubernetes Migration Paused

**Date:** 2026-03-16
**Status:** ⏸️ Deferred
**Context:** 9-week Kubernetes migration plan (ROADMAP.md)

**Decision:** Pause migration after Phase 2; evaluate if full migration needed

**Current Status:**
| Phase | Status | Completion |
|-------|--------|------------|
| Phase 1: Foundation | ✅ Complete | 100% |
| Phase 2: Worker Nodes | ✅ Complete | 100% |
| Phase 3: Stateful Services | ⏸️ Deferred | 0% |
| Phase 4: Stateless Services | 🟡 Partial | 5% (Caddy only) |
| Phase 5: GPU Workloads | ⏸️ Deferred | 0% |
| Phase 6: Monitoring | ✅ Complete | 100% |
| Phase 7: Cleanup | ⏸️ Deferred | 0% |

**Rationale:**
- Hybrid approach (systemd + Kubernetes) working well
- GPU marketplace solves GPU coordination without K8s migration
- Some services better suited for systemd (desktop apps, gaming)
- Complexity of full migration may not be justified

**Remaining Questions:**
- Should stateful services (GlitchTip DB) migrate to K8s?
- Should AI/ML services (LM Studio, Whisper) move to K8s?
- Is full migration worth the effort for homelab use case?

**Resume Cost:** **High** (3-6 weeks per remaining phases)

**Documentation:**
- `ROADMAP.md`

---

## Gateway & AI Integration

### Decision 008: Z.AI MCP Integration Abandoned

**Date:** 2026-03-14
**Status:** ❌ Abandoned
**Context:** Attempted to integrate Z.AI MCP tools (web-search-prime, web-reader, zread, 4-5v-mcp-server)

**Decision:** Removed all Z.AI MCP logic from gateway

**Alternatives Considered:**
| Option | Pros | Cons | Decision |
|--------|------|-------|----------|
| **Remove Z.AI integration** | Cleaner code, remove broken code | Lost web search capability | ✅ CHOSEN |
| Debug Z.AI authentication | Would enable web search | 401 errors regardless of API key | ❌ Time-consuming |
| Use alternative MCP servers | Web search available | Need different provider | ⚠️ Future option |

**Rationale:**
- MCP endpoint only worked for tool discovery, not execution
- Direct tools/call always returned 401 regardless of API key validity
- Z.AI Chat API fallback also removed (`_call_via_chat_api`)
- Debug effort not justified for homelab use case

**Consequences:**
- Gateway v6 package bump (cleanup)
- Lost web search capability via Z.AI
- Later replaced with SearXNG integration

**Commit:** `6694d4c` - "refactor(ai-gateway): remove all Z.AI MCP logic"

**Revert Cost:** **Medium** (4-6 hours to re-integrate if Z.AI fixes their API)

**Follow-up Decision:** SearXNG MCP server integration added instead (commit `6db7e2f`)

---

### Decision 009: Gateway "Quick Wins" Not Completed

**Items:**
1. **Remove debug logs** (1 hour) - Lines 649, 651, 679-681, 700-703 in `main.py`
2. **Update README.md** (2 hours) - Document implemented vs planned features
3. **Implement health checks** (4-6 hours) - TODO at line 272

**Rationale for Delay:**
- Low priority vs other cluster work
- Gateway functional despite these issues
- No production urgency

**Recommendation:** Complete these before adding new gateway features

**Documentation:**
- `docs/gateway/gateway-improvement-roadmap.md`

---

## Future Decisions to Make

### Pending Decision 001: Multi-GPU LM Studio Architecture

**Status:** 🟡 Design Complete, Not Implemented
**Plan:** Distribute LM Studio across Zephyr, Forge, Nexus for ~1500 t/s total
**Effort:** 7-11 hours
**Decision Needed:** Proceed with multi-GPU setup or optimize single-node?

**Documentation:**
- `docs/gateway/gateway-improvement-roadmap.md` (Phase 1.5)

---

## Networking & Infrastructure

### Decision 010: VIP IPv4 Not Working Remotely

**Date:** 2026-03-15
**Status:** ⚠️ Workaround Implemented
**Context:** Sentry kubelet couldn't connect to API server via VIP (10.1.1.100:6443)

**Decision:** Use direct IP (10.1.1.110:6443) for Sentry kubelet

**Alternatives Considered:**
| Option | Pros | Cons | Decision |
|--------|------|-------|----------|
| **Use direct IP** | Works immediately | Not load balanced | ✅ CHOSEN (workaround) |
| Debug VIP IPv4 issue | Proper HA solution | Time-consuming | ⚠️ TODO |
| Use IPv6 VIP | May work | Need IPv6 network | ❌ Not evaluated |

**Rationale:**
- VIP IPv4 works on local nodes but not remotely
- Direct IP to Zephyr works fine
- TODO: Investigate IPv6 socket + VIP interaction

**Consequences:**
- Sentry kubelet connects directly to Zephyr (not HA)
- If Zephyr down, Sentry kubelet loses API access
- Not a critical issue since Sentry also runs control plane components

**Commit:** `9792bd3` - "fix(k8s): use direct IP for sentry kubelet - VIP IPv4 not working remotely"

**Revert Cost:** **Low** if VIP fixed, **Medium** to debug VIP issue

---

### Decision 011: Pod Network CIDR Migration

**Date:** 2026-03-14
**Status:** ✅ Completed
**Context:** Initial pod CIDR (10.1.0.0/16) conflicted with cluster network

**Decision:** Migrate to Flannel standard pod CIDR (10.244.0.0/16)

**Alternatives Considered:**
| Option | Pros | Cons | Decision |
|--------|------|-------|----------|
| **10.244.0.0/16** | Flannel standard, no conflicts | Required migration | ✅ CHOSEN |
| 10.1.0.0/16 | Original plan | Conflicts with host network | ❌ Conflicts |
| Other private CIDR | Many options | Non-standard | ❌ Not evaluated |

**Rationale:**
- 10.1.0.0/16 conflicted with cluster host network (10.1.1.0/24)
- 10.244.0.0/16 is Flannel's default, well-tested
- Required MASQUERADE rule for host IP access

**Consequences:**
- All pods had to be recreated
- Firewall rules updated (8472/UDP for VXLAN)
- CoreDNSConfig updated with new cluster domain suffix

**Commits:**
- `9326597` - "feat(kubernetes): migrate pod network to 10.244.0.0/16"
- `1fc7018` - "refactor(kubernetes): migrate pod CIDR from 10.1.0.0/16 to 10.244.0.0/16"

**Revert Cost:** **High** (would require another pod migration)

---

### Decision 012: Native Interface Names (Not "lan0" Standardization)

**Date:** 2026-03-14
**Status:** ✅ Reverted to Native Names
**Context:** Attempted to standardize all hosts to use "lan0" interface name

**Decision:** Revert to native hardware interface names

**Alternatives Considered:**
| Option | Pros | Cons | Decision |
|--------|------|-------|----------|
| **Native names** | No abstraction, aligns with x86_64 reversion | Different names per host | ✅ FINAL |
| "lan0" standardization | Consistent naming | Abstraction layer, bugs | ❌ Reverted |

**Rationale:**
- "lan0" abstraction caused issues
- x86_64-v3 migration also reverted to base architecture
- Native names more transparent: enp38s0, enp7s0, enp0s31f6

**Interface Mapping:**
| Host | Native Name | Previous "lan0" |
|------|-------------|-----------------|
| Zephyr | enp38s0 | lan0 |
| Nexus | enp7s0 | lan0 |
| Forge | enp0s31f6 | lan0 |
| Sentry | enp7s0 | lan0 |

**Commits:**
- `f167c98` - "fix(networking): revert to native interface names"
- `c39e467` - "fix(networking): correct interface names and revert to base x86_64"

**Revert Cost:** **Medium** (would require updating firewall, networking configs)

---

## Build System & Performance

### Decision 013: x86-64-v3 Migration (Partial/Abandoned)

**Date:** 2026-03-13 to 2026-03-14
**Status:** ⚠️ Partial / Reverted Key Components
**Context:** Attempted migration to x86-64-v3 for AVX2/AVX-512 SIMD optimizations

**Decision:** Migrate flake hosts but revert key components due to issues

**Components:**
| Component | Status | Notes |
|-----------|--------|-------|
| `-v3` suffixed hosts | ✅ Implemented | For nixos-rebuild compatibility |
| hostPlatform configuration | ✅ Implemented | Module-level gcc.arch settings |
| assimp doCheck | ❌ Disabled | FMA-induced FP test failures |
| Kubernetes from unstable | ❌ Reverted | Went back to stable 1.35.0 |
| Network interface names | ❌ Reverted | Back to native names |
| Base architecture | ❌ Reverted | Back to base x86_64 |

**Rationale:**
- x86-64-v3 enables AVX2/AVX-512 for ~30% performance improvement
- But introduced compatibility issues (assimp, Kubernetes)
- Some components just not worth debugging for homelab

**Assimp Floating Point Issue:**
```
Floating point difference with FMA (Fused Multiply-Add):
- result_cpp: CE (with FMA)
- result_c: D0 (without FMA)
```
Tests use exact equality comparison - mathematically fragile with SIMD.

**Commits:**
- `555cf5c` - "fix(v3): disable assimp doCheck for x86-64-v3 SIMD compatibility"
- `9931aea` - "fix(kubernetes): revert to kubernetes 1.35.0 from unstable"
- `f167c98` - "fix(networking): revert to native interface names"
- `c39e467` - "fix(networking): correct interface names and revert to base x86_64"

**Revert Cost:** **N/A** (partial migration is current state)

---

### Decision 014: Harmonia Binary Cache Disabled

**Date:** 2026-03-14
**Status:** ❌ Disabled
**Context:** Harmonia binary cache service causing timeouts

**Decision:** Disable Harmonia service and Garnix, remove local substituter

**Rationale:**
- Harmonia service not actually running on Nexus
- Causing build timeouts
- cache.nixos.org + local Cachix sufficient

**Commits:**
- `3f4b073` - "fix(nexus): disable harmonia and garnix services, remove local substituter"
- `be119b7` - "fix(distributed-builds): fix substituter precedence and remove stale Harmonia references"

**Revert Cost:** **Low** (can re-enable if Harmonia issues resolved)

---

### Decision 015: Helm Package Name Collision (Akash Provider)

**Date:** 2026-03-14
**Status:** ✅ Fixed
**Context:** 'helm' package resolving to audio synthesizer instead of Kubernetes Helm

**Decision:** Use `kubernetes-helm` package explicitly for Akash provider

**Rationale:**
- Package name collision in nixpkgs
- `helm` → Helm 0.9.0 (audio synthesizer)
- `kubernetes-helm` → Kubernetes Helm (what we needed)

**Commits:**
- `f096736` - "fix(akash-provider): use kubernetes-helm instead of audio synthesizer helm"

**Revert Cost:** **N/A** (fix is in place)

---

## Compute & Mining Architecture

### Decision 016: Centralized GPU Proxy Architecture

**Date:** 2026-03-15
**Status:** ✅ Implemented
**Context:** Multiple GPU workers (Zephyr, Nexus) connecting to different mining pools

**Decision:** Centralize GPU proxy on Forge (10.1.1.130:3334)

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                       Forge (10.1.1.130)                    │
│  ┌────────────────────────────────────────────────────────┐ │
│  │         gpu-proxy-cpp (Protocol Translation)         │ │
│  │  Monero Stratum ←→ Bitcoin Stratum (Kryptex CR29)   │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                         ▲
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   ┌────▼────┐      ┌───▼────┐      ┌───▼────┐
   │ Zephyr  │      │ Nexus  │      │ Sentry │
   │ lolMiner│      │lolMiner│      │ xmrig  │
   └─────────┘      └────────┘      └────────┘
```

**Rationale:**
- Kryptex uses Bitcoin Stratum format
- lolMiner uses Monero Stratum format
- Protocol translation needed
- Centralize proxy on Forge (multi-GPU node)

**Consequences:**
- Zephyr and Nexus lolMiner connect to Forge:3334
- Direct Kryptex connections remain as fallback
- Fixed Nexus's 0.00 g/s issue

**Commits:**
- `e7bffce` - "feat(mining): implement centralized GPU proxy architecture"

**Revert Cost:** **Medium** (would need to reconfigure all miners)

---

### Decision 017: Compute-Workload-Monitor Evolution

**Date:** 2025-2026 (evolved over time)
**Status:** ✅ Implemented
**Context:** Need to manage CPU/GPU resource conflicts between mining and builds

**Evolution:**
1. **Initial:** `minepause` wrapper script (simple pause/resume)
2. **Phase 1:** `mining-build-wrapper` module with systemd integration
3. **Phase 2:** `compute-workload-monitor` with PSI monitoring
4. **Current:** Full compute-market with auction-based GPU allocation

**Key Features:**
- HTTP API control for xmrig (pause/resume)
- Power limit management per profile
- Profile-based resource allocation (MINING, BUILD, GAMING)
- Integration with GPU marketplace

**Commits:**
- `e74675e` - "fix(distributed-builds): enable compute-workload-monitor on Nexus"
- `d0adaa2` - "feat(mining): update compute-workload-monitor to use HTTP API control"
- `ca7b873` - "feat(mining): add xmrig HTTP API control and Ryzen build pause"

**Revert Cost:** **High** (would lose sophisticated resource management)

---

## Containerization

### Decision 018: Podman/MCP-NixOS Containerization Deferred

**Date:** 2026-02-08 (Phase 2 partial)
**Status:** ⏸️ Deferred
**Context:** Attempted to containerize MCP-NixOS service using Podman

**Decision:** Podman infrastructure ready, but containerization deferred

**Rationale:**
- Docker Hub access denied during deployment
- MCP-NixOS continues in non-container mode (works perfectly)
- Phase 1 approach sufficient for current needs

**What Was Completed:**
- Quadlet-Nix input added to flake.nix
- Podman 5.7.0 configured (rootless containers working)
- systemd service for MCP-NixOS Podman container
- dendritic/nodes structure created

**Commit:** `a73e044` - "Phase 2: Partial complete - Podman ready, containerization deferred"

**Revert Cost:** **Low** (Podman still available if needed later)

---

## Project Origins

### Decision 019: Initial Cluster Architecture (January 2026)

**Date:** 2026-01-24
**Status:** ✅ Foundation
**Context:** Initial commit established 4-host cluster architecture

**Original Components (117 files, 20,234 lines):**

**Documentation:**
- Multiple improvement/optimization plans (now consolidated)
- Security audits and analysis
- Integration guides (astraldev)

**Infrastructure:**
- 4 hosts: Zephyr, Nexus, Forge, Sentry
- Gaming module with ezKEa anime game launchers
- Mining services (lolMiner, xmrig)
- MCP server integration
- Distributed builds

**Key Insights from Initial Setup:**
- Comprehensive documentation sprawl (25+ doc files)
- Multiple overlapping plans (modernization, optimization, cleanup)
- Strong gaming/VR focus (WiVRn, Lighthouse, Steam)
- Mining cluster already operational

**Evolution:**
- Much documentation consolidated over time
- Gaming maintained (anime launchers still present)
- Mining evolved into sophisticated marketplace
- MCP integration evolved from server.py to full broker

**Commit:** `40c6f9a` - "Initial commit"

---

## Future Decisions to Make

### Pending Decision 001: Multi-GPU LM Studio Architecture

**Status:** 🟡 Design Complete, Not Implemented
**Plan:** Distribute LM Studio across Zephyr, Forge, Nexus for ~1500 t/s total
**Effort:** 7-11 hours
**Decision Needed:** Proceed with multi-GPU setup or optimize single-node?

**Documentation:**
- `docs/gateway/gateway-improvement-roadmap.md` (Phase 1.5)

---

## Decision Review Process

**Monthly Review:**
- Are decisions still valid?
- Have requirements changed?
- Should any decisions be revisited?

**When to Revisit a Decision:**
- Requirements change significantly
- New information emerges
- Pain points develop
- Technology evolves

**To Change a Decision:**
1. Document rationale for change
2. Update this log
3. Calculate revert/reimplement cost
4. Get stakeholder buy-in
5. Update dependent documentation

---

**Last Updated:** 2026-03-16
**Next Review:** 2026-04-16

---

**Decision Count:** 19 decisions recorded from git history analysis (2026-01-24 to 2026-03-16)
