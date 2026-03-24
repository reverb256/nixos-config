# Network Integration Design: NixOS + Kubernetes

**Status:** Approved | **Date:** 2026-03-24 | **Owner:** j_kro

## Executive Summary

Comprehensive network integration between NixOS host environment and Kubernetes cluster, leveraging advanced Calico features and full Caddy capabilities. Implements defense-in-depth security, DNS unification, and explicit resource placement to protect RAM-constrained zephyr node.

**Goals:**
- Fix DNS inconsistencies (conflicting static A records)
- Improve performance (reduce latency, optimize routing)
- Simplify operations (unified DNS, clear ingress separation)
- Enable secure external access (Akash provider only)

**Approach:** Approach 1 - Unify DNS, Split Ingress (Recommended)

---

## Architecture Overview

```
HOST LAYER (NixOS)
├─ Unbound DNS (127.0.0.1:53) - Single DNS source of truth
├─ Systemd Caddy (zephyr) - Full-featured ingress (LAN/VPN)
└─ Calico BGP peer → Advertises cluster routes

KUBERNETES LAYER
├─ Calico CNI (full feature set: policies, BGP, IPVS, WireGuard)
├─ CoreDNS (10.0.0.10) - K8s service discovery only
└─ K8s Caddy Ingress (3 pods) - Full-featured ingress (cluster services)

DNS FLOW
Host App → Unbound → [*.lan] → systemd Caddy → host service
Host App → Unbound → [*.cluster.local] → K8s Caddy → K8s pod
K8s Pod → CoreDNS → service.namespace.svc.cluster.local → pod
```

**Key Principles:**
- Unbound = DNS authority for all cluster resolution (host + K8s)
- CoreDNS = K8s-internal only (service discovery for pods)
- Dual ingress = Clear separation (systemd Caddy for host services, K8s Caddy for cluster services)
- Calico = Network enforcement (policies, BGP routing between layers)

---

## Section 1: DNS Integration Strategy

**Problem:** Unbound has conflicting DNS records:
- Static A records: `ai.cluster.local → 10.1.1.120` (OLD, wrong)
- Wildcard CNAME: `*.cluster.local → caddy-ingress` (CORRECT)
- Result: Split-brain DNS (static records win due to processing order)

**Solution:**
```nix
# modules/services/unbound-cluster.nix
REMOVE: Static A records for K8s services (ai, llm, rag, prometheus, etc.)
KEEP: Wildcard CNAME *.cluster.local → caddy-ingress
KEEP: Forward zone cluster.local → CoreDNS (10.0.0.10)
KEEP: Static host records (zephyr.cluster.local → 10.1.1.110, etc.)
ADD: Service health monitoring (auto-restart if CoreDNS unreachable)
```

**DNS Resolution Flow:**
```
Host app: curl http://prometheus.cluster.local
    ↓
Unbound (127.0.0.1:53)
    ├─ Check: Is it a static host record? NO
    ├─ Check: Is it *.cluster.local? YES → CNAME to caddy-ingress
    └─ Forward to CoreDNS (10.0.0.10) → Returns caddy-ingress pod IP
    ↓
K8s Caddy Ingress (ClusterIP: 10.0.0.106)
    └─ Routes to prometheus.ai-inference.svc.cluster.local:9090
```

**Safety Mechanisms:**
- Gradual migration: Remove one static record at a time
- Health check: Script to verify `prometheus.cluster.local` resolves correctly
- Rollback plan: Keep old static entries commented out for 1 week
- Auto-restart: Unbound restarts if CoreDNS unreachable (5-minute timer)

---

## Section 2: Ingress Strategy (Dual Caddy)

**Architecture:**
```
SYSTEMD CADDY (zephyr only)
├─ LISTEN: 10.1.1.110:80, 10.1.1.110:443
├─ ROUTES: *.lan, *.tigris-ule.ts.net (NO *.cluster.local)
├─ FEATURES: Security headers, rate limiting, metrics, HTTP/3
└─ INTEGRATION: Reverse proxy to K8s services via ClusterIP

K8S CADDY (DaemonSet: nexus, forge, sentry)
├─ LISTEN: NodePort 30080, 30443
├─ ROUTES: *.cluster.local only
├─ FEATURES: Same as systemd Caddy (feature parity)
└─ INTEGRATION: K8s API watch (automatic route updates)
```

**Shared Features Module:**
```nix
# modules/services/caddy-common.nix (NEW)
- Security headers (HSTS, CSP, X-Frame-Options)
- Rate limiting (configurable per-instance)
- Metrics endpoint (:2019/metrics)
- TLS configuration (internal CA for cluster, Let's Encrypt for external)
- HTTP/3 support
```

**Benefits:**
- Clear ownership: Systemd Caddy = host services, K8s Caddy = cluster services
- Feature parity: Both use same security headers, rate limiting, metrics
- Independent scaling: Can scale K8s Caddy pods without touching host Caddy
- Reduced duplication: Shared module ensures consistency

---

## Section 3: Calico Network Integration

**Advanced Features to Enable:**

1. **Network Policies (East-West Segmentation)**
   - Default deny all inter-namespace traffic
   - Allow: ingress-system → *, kube-system → *, monitoring → *
   - DENY: mining → ai-inference (GPU resource protection)

2. **BGP Mode (Route Advertisement)**
   - Calico nodes peer with host network
   - Advertise pod routes (10.244.0.0/16) to physical network
   - Enable BGP route reflection (multi-path)
   - Integration: Unbound can resolve pod IPs directly

3. **IPVS (Service Load Balancing)**
   - Enable IPVS for K8s services (better performance)
   - Direct server return (DSR) for lower latency
   - Bypass kube-proxy for service traffic

4. **WireGuard Encryption (Node-to-Node)**
   - Encrypt all pod-to-pod traffic across nodes
   - Key rotation: Automated every 24 hours
   - Performance impact: ~5% overhead (acceptable)

**Implementation Order:**
- Week 1: Network policies (test on non-critical namespaces)
- Week 2: BGP mode (enable on one node, verify, then roll out)
- Week 3: IPVS (performance testing before/after)
- Week 4: WireGuard (test on 2 nodes, measure overhead)

---

## Section 4: External Access Strategy

**Security Principle: Defense-in-Depth**

```
LAYER 1: FIREWALL (Host Level)
├─ ALLOW: Cluster subnet (10.1.1.0/24)
├─ ALLOW: Tailscale VPN (100.64.0.0/10)
├─ ALLOW: Kubernetes pod network (10.244.0.0/16)
└─ DENY: Everything else (default drop)

LAYER 2: DNS ADVERTISEMENT
├─ PUBLIC: provider.reverb256.ca → Akash only
├─ CLUSTER: *.cluster.local → K8s services only
└─ VPN: *.tigris-ule.ts.net → Authenticated users

LAYER 3: CALICO POLICIES
├─ ALLOW: Cluster-to-cluster traffic
├─ ALLOW: VPN-to-cluster (MFA authenticated)
├─ DENY: Direct internet-to-pod traffic
└─ ENFORCE: Policy-based access control

LAYER 4: INGRESS CONTROLLERS
├─ Systemd Caddy: IP whitelist + rate limiting
├─ K8s Caddy: IP whitelist + rate limiting
└─ Security headers: HSTS, CSP, X-Frame-Options

LAYER 5: AUTHENTICATION
├─ Tailscale: MFA required
├─ Cloudflare: Access rules (email, OTP)
└─ LAN: SSH key authentication
```

**Access Control Matrix:**
```
Service            │ Internet  │ Tailscale │ LAN       │ Cluster
───────────────────┼───────────┼───────────┼───────────┼─────────
AI Gateway         │ ❌ BLOCKED│ ✅ ALLOWED│ ❌ BLOCKED│ ✅ ALLOWED
Prometheus        │ ❌ BLOCKED│ ✅ ALLOWED│ ❌ BLOCKED│ ✅ ALLOWED
Grafana           │ ❌ BLOCKED│ ✅ ALLOWED│ ❌ BLOCKED│ ✅ ALLOWED
Akash Provider    │ ✅ CF ONLY│ ✅ ALLOWED│ ❌ BLOCKED│ ✅ ALLOWED
Host Dashboard    │ ❌ BLOCKED│ ✅ ALLOWED│ ✅ ALLOWED│ ❌ N/A
Mining Services   │ ❌ BLOCKED│ ❌ BLOCKED│ ❌ BLOCKED│ ✅ ALLOWED
```

**Only Akash provider is publicly advertised (Cloudflare Tunnel)**

---

## Section 5: Resource Placement Strategy

**Cluster RAM Capacity:**
```
Host      RAM      Constraints
─────────────────────────────────────
Zephyr    31GB     CRITICAL - NO RAM-heavy processes
Nexus     46GB     High capacity - Best for storage/metrics
Forge      15GB     Medium - GPU mining only
Sentry    31GB     High - Monitoring/logging
```

**Placement Rules:**
```
ZEPHYR (CRITICAL RAM CONSTRAINT)
├─ KEEP: Control plane, Unbound, Systemd Caddy, GPU workloads
└─ AVOID: Monitoring, logging, storage, heavy ingress

NEXUS (HIGH CAPACITY)
├─ ADD: Prometheus, Grafana, Loki (FUTURE)
├─ KEEP: K8s Caddy ingress, Storage, GPU compute
└─ BEST FOR: Metrics storage, dashboards, log aggregation

SENTRY (HIGH CAPACITY)
├─ ADD: AlertManager, Calico Typha
├─ KEEP: K8s Caddy ingress, Monitoring agents
└─ BEST FOR: Alert routing, Calico scale-out

FORGE (MEDIUM CAPACITY)
├─ KEEP: GPU mining, K8s Caddy ingress
└─ AVOID: Stateful workloads, storage, metrics
```

**Node Taints:**
```bash
# Taint zephyr to prevent RAM-heavy workloads
kubectl taint nodes zephyr ram-critical=true:NoSchedule

# GPU workloads CAN run on zephyr (with toleration)
# Monitoring CANNOT run on zephyr (no toleration)
```

---

## Section 6: Monitoring & Observability

**Monitoring Stack:**
```
LAYER 1: Infrastructure
├─ Node Exporter (CPU, memory, disk, network)
├─ NVIDIA GPU Exporter (GPU utilization, temperature)
└─ Calico Felix (policy enforcement, BGP routes)

LAYER 2: Kubernetes
├─ Kube-State-Metrics (pod, node, deployment status)
├─ Caddy Ingress Metrics (request rates, latency, errors)
└─ CoreDNS Metrics (DNS resolution latency, cache hits)

LAYER 3: Application
├─ AI Gateway (request latency, model loading)
├─ Qdrant (vector DB queries, index stats)
└─ Prometheus/Grafana (scrape targets, storage)

LAYER 4: Logging
├─ Promtail (systemd journals, K8s pod logs)
└─ Loki (FUTURE - log storage)

ALERTING (AlertManager)
├─ Critical: Service down, DNS failure, GPU unavailable
├─ Warning: High latency, rate limit exceeded, policy violation
└─ Info: Certificate expiry, BGP peer changes
```

**Three-Tier Alerting:**
- Critical: PagerDuty/push notifications (immediate response)
- Warning: Slack messages (investigation within 1 hour)
- Info: Log only (documentation purposes)

---

## Section 7: Migration Plan

**6-Week Phased Migration:**

**Week 1: DNS Cleanup (Risk: LOW)**
- Day 1-2: Test environment validation
- Day 3-4: Remove conflicting static records (one at a time)
- Day 5: Monitor and stabilize

**Week 2: Caddy Feature Parity (Risk: LOW)**
- Create modules/services/caddy-common.nix
- Test on systemd Caddy (zephyr) first
- Deploy to K8s Caddy (ConfigMap update)

**Week 3: Calico Network Policies (Risk: MEDIUM)**
- Day 1-2: Deploy non-enforcing policies (audit mode)
- Day 3-4: Enforce policies on non-critical namespaces
- Day 5: Enforce policies on critical namespaces

**Week 4: Calico BGP Mode (Risk: MEDIUM)**
- Day 1: Enable on single node (sentry)
- Day 2-3: Roll out to remaining nodes
- Day 4-5: Monitor and optimize

**Week 5: Calico IPVS & WireGuard (Risk: MEDIUM)**
- Day 1-2: Enable IPVS
- Day 3-4: Enable WireGuard
- Day 5: Full cluster validation

**Week 6: External Access Hardening (Risk: LOW)**
- Verify Cloudflare Tunnel (Akash only)
- Verify Tailscale VPN access
- Verify LAN access

**Rollback Procedures:**
```bash
# DNS rollback
sed -i 's/# OLD: ai.cluster.local/ai.cluster.local/' modules/services/unbound-cluster.nix
just deploy

# Calico policies rollback
kubectl delete networkpolicy --all --all-namespaces

# BGP rollback
kubectl patch bgpconfiguration default -p '{"spec":{"nodeToNodeMeshEnabled":false}}'
```

---

## Section 8: Testing & Validation

**Test Automation:**
- DNS resolution: Test all *.cluster.local hostnames
- Ingress reachability: HTTP 200 from all access patterns
- Network policies: Verify external traffic blocked
- Resource placement: Prometheus on nexus, not zephyr
- Calico BGP: Verify pod routes advertised
- Monitoring metrics: Caddy metrics endpoint available

**Performance Benchmarks:**
- DNS resolution latency: < 50ms
- Ingress response time: p95 < 500ms
- Network throughput: > 1Gbps host-to-host
- Pod startup time: < 30s
- Zephyr RAM usage: < 80%

**Failure Scenario Testing:**
- CoreDNS crash: Unbound fallback behavior
- Caddy pod restart: Graceful shutdown, zero-downtime
- Calico policy misconfig: Rollback procedures
- BGP peer failure: Route recalculation

---

## Success Criteria

**Functional Requirements:**
- ✅ All *.cluster.local services resolve correctly via Unbound
- ✅ No conflicting DNS entries (single source of truth)
- ✅ K8s Caddy handles all cluster services
- ✅ Systemd Caddy handles LAN/VPN access only
- ✅ Only Akash provider exposed to internet
- ✅ Calico network policies enforce segmentation

**Performance Requirements:**
- ✅ DNS resolution latency < 50ms (p95)
- ✅ Ingress response time < 500ms (p95)
- ✅ No service degradation during migration
- ✅ Zephyr RAM usage < 80%

**Security Requirements:**
- ✅ Defense-in-depth: 5 security layers
- ✅ Only Akash provider publicly advertised
- ✅ Calico policies block unauthorized access
- ✅ Rate limiting enforced on all ingress
- ✅ No single point of failure in security

**Operational Requirements:**
- ✅ Unified monitoring (all metrics in Prometheus)
- ✅ Automated testing (run before/after each phase)
- ✅ Clear rollback procedures (tested and documented)
- ✅ Resource placement enforced (zephyr protected)

---

## Section 9: NixOS Integration Patterns

**NixOS Flake Architecture:**

This network integration leverages the existing NixOS cluster architecture:
- **Flake-based deployment**: `/etc/nixos/flake.nix` defines all hosts and modules
- **Colmena multi-host**: Deployments via `just deploy` (NFS-based, no config sync needed)
- **Module system**: `modules/default.nix` auto-imports all modules for declarative composition
- **Host-specific configs**: `hosts/<hostname>/configuration.nix` enable modules via `profiles.*`

**Module Architecture:**

```
/etc/nixos/
├── flake.nix                          # Top-level flake (defines all hosts)
├── colmena.nix                        # Multi-host deployment
├── modules/
│   ├── default.nix                    # Auto-imports all modules
│   ├── services/
│   │   ├── caddy-common.nix          # NEW: Shared Caddy configuration
│   │   ├── unbound-cluster.nix       # MODIFY: Remove static K8s A records
│   │   ├── kubernetes.nix            # MODIFY: Add Calico features
│   │   └── service-gateway.nix       # Systemd Caddy (zephyr only)
│   ├── networking/
│   │   └── cluster-networking.nix   # MODIFY: Firewall + network constants
│   └── profiles/
│       └── monitoring.nix            # NEW: Enable monitoring on nexus/sentry
└── hosts/
    ├── zephyr/configuration.nix      # ENABLE: service-gateway, GPU workloads
    ├── nexus/configuration.nix        # ENABLE: monitoring profile, storage
    ├── forge/configuration.nix        # ENABLE: mining profile only
    └── sentry/configuration.nix      # ENABLE: monitoring profile, control-plane
```

**NixOS Module Pattern (Declarative DNS):**

```nix
# modules/services/unbound-cluster.nix (MODIFY)
{ config, lib, pkgs, ... }:
let
  cfg = config.services.unbound-cluster;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.unbound-cluster = {
    enable = mkEnableOption "Unbound DNS resolver for local cluster network";

    # NixOS option pattern: Composable, declarative
    kubernetesIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Forward *.cluster.local to Kubernetes CoreDNS";
    };
  };

  config = mkIf cfg.enable {
    # Declarative Unbound configuration
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = [ "127.0.0.1" cfg.listenAddress ];
          access-control = [
            "127.0.0.0/8 allow"
            "10.1.1.0/24 allow"
            "100.64.0.0/10 allow"
          ];

          # REMOVE: Static A records for K8s services (ai.cluster.local, etc.)
          # KEEP: Static host records (zephyr.cluster.local → 10.1.1.110)
          local-data = [
            # Cluster hosts
            ''"zephyr.cluster.local. IN A 10.1.1.110"''
            ''"nexus.cluster.local. IN A 10.1.1.120"''
            ''"forge.cluster.local. IN A 10.1.1.130"''
            ''"sentry.cluster.local. IN A 10.1.1.140"''
            # Wildcard CNAME for K8s services (NEW)
            ''"*.cluster.local. IN CNAME caddy-ingress.ingress-system.svc.cluster.local."''
          ];

          # Forward zone to Kubernetes DNS (NEW)
          forward-zone = lib.mkIf cfg.kubernetesIntegration [
            {
              name = "cluster.local.";
              forward-addr = [
                "10.0.0.10@53"  # CoreDNS service IP
              ];
            }
          ];
        };
      };
    };

    # NixOS systemd service for health monitoring (NEW)
    systemd.services.unbound-health-check = {
      description = "Monitor Unbound DNS resolution to Kubernetes";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "unbound-health" ''
          #!/bin/sh
          # Test: prometheus.cluster.local must resolve
          if ! ${pkgs.dnsutils}/bin/drill prometheus.cluster.local @127.0.0.1 | grep -q "NOERROR"; then
            echo "❌ DNS health check failed: prometheus.cluster.local not resolving"
            systemctl restart unbound
            exit 1
          fi
          echo "✅ DNS health check passed"
        '';
        User = "root";
      };
    };

    systemd.timers.unbound-health-check = {
      wantedBy = [ "timers.target" ];
      partOf = [ "unbound-health-check.service" ];
      timerConfig.OnCalendar = "*:0/5"; # Every 5 minutes
    };
  };
};
```

**NixOS Module Pattern (Shared Caddy Features):**

```nix
# modules/services/caddy-common.nix (NEW)
{ config, lib, pkgs, ... }:
let
  cfg = config.services.caddy-common;
  inherit (lib) mkEnableOption mkOption types mkIf mkOption;
in {
  options.services.caddy-common = {
    enable = mkEnableOption "Common Caddy configuration features";

    # NixOS composable options
    securityHeaders = mkOption {
      type = types.bool;
      default = true;
      description = "Enable security headers (HSTS, CSP, X-Frame-Options)";
    };

    rateLimit = mkOption {
      type = types.int;
      default = 100;
      description = "Rate limit requests per second";
    };

    metricsPort = mkOption {
      type = types.port;
      default = 2019;
      description = "Prometheus metrics port";
    };
  };

  config = mkIf cfg.enable {
    # Common Caddy configuration snippets
    # Both systemd Caddy and K8s Caddy reference these defaults
    services.caddy = {
      globalConfig = ''
        {
          # Admin API
          admin 0.0.0.0:${toString cfg.metricsPort}

          # Security headers (if enabled)
          ${lib.optionalString cfg.securityHeaders ''
          (security_headers) {
            header {
              Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
              X-Content-Type-Options "nosniff"
              X-Frame-Options "SAMEORIGIN"
              Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob: https: "
            }
          }
          ''}

          # Rate limiting
          rate_limit {
            zone dynamic_zones {
              entry {
                zone = "cluster_local"
                key = "remote_ip"
                events = ${toString cfg.rateLimit}
                window = 1m
              }
            }
          }
        }
      '';
    };
  };
};
```

**Host Configuration Pattern (Resource Placement):**

```nix
# hosts/nexus/configuration.nix (MODIFY)
{ config, lib, pkgs, ... }:
{
  # NixOS profile pattern: Enable monitoring role
  profiles.cluster.monitoring = lib.mkForce true;  # Override default

  # Enable shared Caddy features
  services.caddy-common.enable = true;

  # Enable Prometheus (systemd service, NOT K8s pod)
  services.prometheus = {
    enable = true;
    port = 9090;
    # Configuration via NixOS module
  };

  # Enable Grafana (systemd service, NOT K8s pod)
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "10.1.1.120:3001";  # Listen on nexus IP only
      };
    };
  };
}

# hosts/zephyr/configuration.nix (MODIFY)
{ config, lib, pkgs, ... }:
{
  # EXPLICITLY disable monitoring (protect RAM)
  profiles.cluster.monitoring = lib.mkForce false;

  # Enable systemd Caddy for LAN/VPN ingress
  services.caddy-common.enable = true;
  services.service-gateway.enable = true;  # Already configured

  # NO Prometheus, Grafana, Loki, or other RAM-heavy services
}
```

**NixOS + Kubernetes Integration (Calico):**

```nix
# modules/services/kubernetes.nix (MODIFY)
{ config, lib, pkgs, ... }:
let
  cfg = config.services.kubernetes;
in {
  # NixOS Kubernetes module with Calico features
  services.kubernetes = {
    enable = true;
    roles = ["master" "node"];  # Zephyr is control plane + node

    # Calico CNI configuration
    flannel.enable = lib.mkForce false;  # DISABLE Flannel (use Calico)
    addons.calico.enable = true;

    # Advanced Calico features
    features = {
      # BGP mode (route advertisement)
      bgp = {
        enable = true;
        asNumber = 64512;
        # Advertise pod routes to physical network
        advertisePodRoutes = true;
      };

      # IPVS (service load balancing)
      ipvs = {
        enable = true;
        strictArp = true;
      };

      # WireGuard encryption
      wireguard = {
        enable = true;
        listeningPort = 51820;
        routingRule = "Drop";  # Non-WireGuard traffic dropped
      };
    };
  };

  # NixOS network policies via firewall integration
  networking.firewall = lib.mkMerge [
    # Base firewall (from cluster-networking.nix)
    config.networking.firewall

    # Calico-specific rules
    { allowedTCPPorts = [ 51820 ]; }  # WireGuard
    { allowedUDPPorts = [ 8472 ]; }     # VxLAN (Calico overlay)
  ];
}
```

**NixOS Deployment Pattern (Colmena):**

```bash
# Deployment workflow (leveraging existing infrastructure)
# 1. Edit NixOS modules (declarative configuration)
vim modules/services/unbound-cluster.nix

# 2. Validate configuration (fast, no build)
nix flake check

# 3. Commit to git (NixOS only packages git-tracked files)
git add modules/services/unbound-cluster.nix
git commit -m "fix(dns): Remove conflicting static A records for K8s services"

# 4. Deploy to all hosts via Colmena (NFS-based, atomic)
just deploy

# 5. Verify DNS resolution
drill prometheus.cluster.local @127.0.0.1

# 6. Rollback if needed (instantaneous)
just rollback  # Reverts to previous generation
```

`★ Insight ─────────────────────────────────────`
**NixOS reproducibility advantage**: Every NixOS configuration change creates a new generation in `/nix/store`. If deployment breaks services, `just rollback` instantly reverts to previous generation - no manual cleanup needed. This is safer than imperative Kubernetes deployments where rollbacks require manual manifest deletion. The integration leverages NixOS atomic deployments for host-level changes (DNS, Caddy) while using Kubernetes native rollback for cluster changes (Calico policies, ingress ConfigMaps).
`─────────────────────────────────────────────────`

**NixOS-Kubernetes Hybrid Pattern:**

```
NIXOS LAYER (Declarative, Reproducible)
├── modules/services/unbound-cluster.nix → Unbound DNS (systemd service)
├── modules/services/caddy-common.nix → Shared Caddy features
├── modules/services/kubernetes.nix → Calico CNI configuration
└── Deployment: Colmena (atomic, rollback-safe)

KUBERNETES LAYER (Imperative, GitOps)
├── kubernetes-manifests/calico/network-policies.yaml → Network policies
├── kubernetes-manifests/ingress/02-configmap.yaml → K8s Caddy config
└── Deployment: kubectl apply (native K8s rollback)

INTEGRATION PATTERN
├── NixOS configures host-level services (Unbound, systemd Caddy)
├── NixOS configures Calico node features (BGP, IPVS, WireGuard)
├── Kubernetes configures cluster resources (policies, ingress)
└── Cross-layer coordination via DNS (Unbound → CoreDNS → K8s services)
```

---

## Implementation Notes

**Files to Create:**
- `modules/services/caddy-common.nix` - Shared Caddy configuration (NixOS module)
- `modules/profiles/monitoring.nix` - Monitoring profile for nexus/sentry
- `scripts/test-network-integration.sh` - Automated test suite
- `scripts/benchmark-network.sh` - Performance benchmarking
- `kubernetes-manifests/calico/network-policies.yaml` - Calico policies
- `kubernetes-manifests/calico/bgp-config.yaml` - BGP configuration

**Files to Modify:**
- `modules/services/unbound-cluster.nix` - Remove conflicting static A records, add health check
- `modules/services/kubernetes.nix` - Add Calico features (BGP, IPVS, WireGuard)
- `modules/networking/cluster-networking.nix` - Update firewall rules for Calico
- `modules/default.nix` - Import caddy-common module
- `hosts/nexus/configuration.nix` - Enable monitoring profile
- `hosts/zephyr/configuration.nix` - Disable monitoring profile (RAM protection)
- `hosts/sentry/configuration.nix` - Enable monitoring profile
- `kubernetes-manifests/ingress/02-configmap.yaml` - Add security features

**NixOS-Specific Benefits:**
- ✅ **Declarative DNS**: Unbound config managed by NixOS modules (no manual editing)
- ✅ **Atomic rollbacks**: `just rollback` reverts to previous generation instantly
- ✅ **Reproducibility**: Same NixOS config → identical system across reboots
- ✅ **GitOps workflow**: All changes tracked in git, deployed via Colmena
- ✅ **Module composition**: `caddy-common.nix` shared across systemd + K8s Caddy
- ✅ **Host-specific tuning**: Profiles enable/disable features per-host (monitoring, mining)

**Kubernetes-Native Features:**
- ✅ **Dynamic ingress**: K8s Caddy watches service changes automatically
- ✅ **Policy enforcement**: Calico policies applied via Kubernetes manifests
- ✅ **Service discovery**: CoreDNS provides K8s-native service resolution
- ✅ **Self-healing**: Failed pods automatically restarted (K8s controller)

**Next Steps:**
1. Review and approve this design document
2. Invoke `writing-plans` skill to create detailed implementation plan
3. Begin Week 1: DNS cleanup migration

---

**Version:** 2.0 | **Last Updated:** 2026-03-24
**Changes:** Added Section 9 (NixOS Integration Patterns) - Deep integration with flake architecture, module system, and deployment patterns
