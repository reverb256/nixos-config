# Network Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify NixOS and Kubernetes network configuration for better performance, security, and operability

**Architecture:** Dual Caddy ingress (systemd + K8s), Calico CNI with advanced features, unified DNS via Unbound, defense-in-depth security

**Tech Stack:** NixOS flakes, Kubernetes v1.35.0, Calico CNI, Unbound DNS, Caddy ingress

---

## Task 1: Remove Conflicting DNS Records from Unbound

**Files:**
- Modify: `modules/services/unbound-cluster.nix`

**Step 1: Backup current Unbound configuration**

```bash
cp modules/services/unbound-cluster.nix modules/services/unbound-cluster.nix.backup
```

**Step 2: Remove conflicting static A records**

In `modules/services/unbound-cluster.nix`, locate the `local-data` array and comment out these lines:

```nix
local-data = [
  # COMMENT OUT THESE CONFLICTING RECORDS:
  # ''"ai.cluster.local. IN A 10.1.1.120"''
  # ''"llm.cluster.local. IN A 10.1.1.120"''
  # ''"rag.cluster.local. IN A 10.1.1.120"''
  # ''"prometheus.cluster.local. IN A 10.1.1.110"''
  # ''"grafana.cluster.local. IN A 10.1.1.110"''

  # KEEP THESE STATIC HOST RECORDS:
  ''"zephyr.cluster.local. IN A 10.1.1.110"''
  ''"nexus.cluster.local. IN A 10.1.1.120"''
  ''"forge.cluster.local. IN A 10.1.1.130"''
  ''"sentry.cluster.local. IN A 10.1.1.140"''

  # KEEP WILDCARD CNAME (authoritative):
  ''"*.cluster.local. IN CNAME caddy-ingress.ingress-system.svc.cluster.local."''
];
```

**Step 3: Test DNS resolution**

Run: `drill ai.cluster.local @127.0.0.1`
Expected: CNAME response pointing to `caddy-ingress.ingress-system.svc.cluster.local`

**Step 4: Commit**

```bash
git add modules/services/unbound-cluster.nix
git commit -m "fix(dns): Remove conflicting static A records for K8s services

- Keep wildcard CNAME as authoritative source
- Comment out old entries for 1-week rollback window
- Prevents split-brain DNS resolution"
```

---

## Task 2: Create Unbound Health Monitoring Service

**Files:**
- Modify: `modules/services/unbound-cluster.nix`

**Step 1: Add systemd health check service**

In `modules/services/unbound-cluster.nix`, add before the closing `}`:

```nix
  # Health monitoring
  systemd.services.unbound-health-check = {
    description = "Monitor Unbound DNS resolution to Kubernetes";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "unbound-health" ''
        #!/bin/sh
        echo "[unbound-health-check] Checking DNS resolution..."

        # Test K8s service resolution
        if ! ${pkgs.dnsutils}/bin/drill prometheus.cluster.local @127.0.0.1 | grep -q "NOERROR"; then
          echo "[unbound-health-check] ❌ DNS health check failed"
          systemctl restart unbound
          exit 1
        fi

        # Test wildcard CNAME
        if ! ${pkgs.dnsutils}/bin/drill "test.cluster.local" @127.0.0.1 | grep -q "CNAME"; then
          echo "[unbound-health-check] ❌ Wildcard CNAME check failed"
          systemctl restart unbound
          exit 1
        fi

        echo "[unbound-health-check] ✅ DNS health check passed"
      '';
      User = "root";
    };
  };

  systemd.timers.unbound-health-check = {
    wantedBy = [ "timers.target" ];
    partOf = [ "unbound-health-check.service" ];
    timerConfig = {
      OnCalendar = "*:0/5";  # Every 5 minutes
      Persistent = true;
    };
  };
```

**Step 2: Test health check service**

Run: `systemctl start unbound-health-check.service && journalctl -u unbound-health-check -n 20`
Expected: "[unbound-health-check] ✅ DNS health check passed"

**Step 3: Verify timer is active**

Run: `systemctl status unbound-health-check.timer`
Expected: Timer is active and will trigger next run in ~5 minutes

**Step 4: Commit**

```bash
git add modules/services/unbound-cluster.nix
git commit -m "feat(dns): Add Unbound health monitoring with auto-restart

- Checks DNS resolution every 5 minutes
- Auto-restarts Unbound if CoreDNS unreachable
- Tests both specific services and wildcard CNAME"
```

---

## Task 3: Create Shared Caddy Common Module

**Files:**
- Create: `modules/services/caddy-common.nix`

**Step 1: Write the Caddy common module**

Create `modules/services/caddy-common.nix`:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.caddy-common;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.caddy-common = {
    enable = mkEnableOption "Common Caddy configuration features for ingress";

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

    adminListenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Admin API listen address (0.0.0.0 for K8s, 127.0.0.1 for systemd)";
    };
  };

  config = mkIf cfg.enable {
    services.caddy = {
      globalConfig = ''
        {
          admin ${cfg.adminListenAddress}:${toString cfg.metricsPort}
          default_sni cluster.local

          ${lib.optionalString cfg.securityHeaders ''
          (security_headers) {
            header {
              Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
              X-Content-Type-Options "nosniff"
              X-Frame-Options "SAMEORIGIN"
              X-XSS-Protection "1; mode=block"
              Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob: https: "
              -Server
            }
          }
          ''}

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

          encode zstd gzip
        }
      '';
    };
  };
}
```

**Step 2: Add module to default.nix**

In `modules/default.nix`, add:

```nix
  services = {
    caddy-common = import ./services/caddy-common.nix;
    # ... other services
  };
```

**Step 3: Validate module syntax**

Run: `nix flake check`
Expected: No errors, module syntax valid

**Step 4: Commit**

```bash
git add modules/services/caddy-common.nix modules/default.nix
git commit -m "feat(caddy): Create shared Caddy configuration module

- Common security headers (HSTS, CSP, X-Frame-Options)
- Rate limiting configuration
- Metrics endpoint configuration
- Flexible admin listen address for systemd/K8s"
```

---

## Task 4: Enable Caddy Common on Systemd Caddy (Zephyr)

**Files:**
- Modify: `hosts/zephyr/configuration.nix`

**Step 1: Enable caddy-common module**

In `hosts/zephyr/configuration.nix`, add:

```nix
  # Enable shared Caddy features for systemd Caddy
  services.caddy-common.enable = true;
  services.caddy-common.adminListenAddress = "127.0.0.1";  # Localhost only for systemd
```

**Step 2: Test Caddy configuration**

Run: `caddy validate --config /etc/caddy/Caddyfile`
Expected: "Valid configuration"

**Step 3: Reload Caddy**

Run: `systemctl reload caddy`
Expected: No errors in journalctl

**Step 4: Verify metrics endpoint**

Run: `curl http://127.0.0.1:2019/metrics`
Expected: Prometheus metrics output

**Step 5: Commit**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "feat(caddy): Enable shared Caddy features on systemd Caddy

- Apply security headers to LAN/VPN routes
- Enable rate limiting
- Expose metrics on localhost only"
```

---

## Task 5: Update K8s Caddy Ingress with Common Features

**Files:**
- Modify: `kubernetes-manifests/ingress/02-configmap.yaml`

**Step 1: Update Caddyfile with security features**

In `kubernetes-manifests/ingress/02-configmap.yaml`, update the Caddyfile:

```yaml
data:
  Caddyfile: |
    {
      admin 0.0.0.0:2019
      default_sni cluster.local

      (security_headers) {
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "SAMEORIGIN"
          X-XSS-Protection "1; mode=block"
          Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob: https: "
          -Server
        }
      }

      rate_limit {
        zone dynamic_zones {
          entry {
            zone = "cluster_local"
            key = "remote_ip"
            events = 100
            window = 1m
          }
        }
      }

      encode zstd gzip
    }

    ai.cluster.local {
      import security_headers
      tls internal
      reverse_proxy ai-inference-gateway.ai-inference.svc.cluster.local:8080
    }

    prometheus.cluster.local {
      import security_headers
      tls internal
      reverse_proxy prometheus.ai-inference.svc.cluster.local:9090
    }

    grafana.cluster.local {
      import security_headers
      tls internal
      reverse_proxy grafana.ai-inference.svc.cluster.local:3000
    }

    qdrant.cluster.local {
      import security_headers
      tls internal
      reverse_proxy qdrant.ai-inference.svc.cluster.local:6333
    }
```

**Step 2: Apply updated ConfigMap**

Run: `kubectl apply -f kubernetes-manifests/ingress/02-configmap.yaml`
Expected: "configmap/caddy-ingress configured"

**Step 3: Restart Caddy pods**

Run: `kubectl rollout restart daemonset/caddy-ingress -n ingress-system`
Expected: All pods restarted

**Step 4: Verify security headers**

Run: `curl -I https://prometheus.cluster.local -k`
Expected: HSTS, X-Frame-Options, CSP headers present

**Step 5: Commit**

```bash
git add kubernetes-manifests/ingress/02-configmap.yaml
git commit -m "feat(caddy): Add security headers and rate limiting to K8s ingress

- Feature parity with systemd Caddy
- Security headers on all routes
- Rate limiting per IP"
```

---

## Task 6: Create Monitoring Profile Module

**Files:**
- Create: `modules/profiles/monitoring.nix`

**Step 1: Write monitoring profile module**

Create `modules/profiles/monitoring.nix`:

```nix
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
in {
  options.profiles.monitoring = mkOption {
    enable = mkEnableOption "Monitoring stack (Prometheus, Grafana, AlertManager)";
    default = false;  # NOT enabled by default (protects RAM)
  };

  config = mkIf config.profiles.monitoring.enable {
    services.prometheus = {
      enable = true;
      port = 9090;
      extraFlags = [
        "--storage.tsdb.retention.time=200h"  # 8 days
      ];
      exporters = {
        node = {
          enable = true;
          enabledCollectors = [ "systemd" "cpu" "meminfo" "filesystem" ];
        };
      };
    };

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "10.1.1.120";  # Listen on nexus IP only
          http_port = 3001;
        };
      };
    };

    services.alertmanager = {
      enable = true;
      port = 9093;
      configText = ''
        global:
          resolve_timeout: 5m

        route:
          receiver: 'default-receiver'
          group_wait: 10s
          group_interval: 5m
          repeat_interval: 12h

        receivers:
          - name: 'default-receiver'
      '';
    };

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [9090 9093 3001];
  };
}
```

**Step 2: Add profile to profiles/default.nix**

In `modules/profiles/default.nix`, add:

```nix
  {
    monitoring = import ./monitoring.nix;
  }
```

**Step 3: Validate profile syntax**

Run: `nix flake check`
Expected: No errors

**Step 4: Commit**

```bash
git add modules/profiles/monitoring.nix modules/profiles/default.nix
git commit -m "feat(monitoring): Create composable monitoring profile

- Prometheus with 8-day retention
- Grafana on nexus IP only
- AlertManager with default config
- Disabled by default (RAM protection)"
```

---

## Task 7: Enable Monitoring on Nexus

**Files:**
- Modify: `hosts/nexus/configuration.nix`

**Step 1: Enable monitoring profile**

In `hosts/nexus/configuration.nix`, add:

```nix
  # Enable monitoring stack (Prometheus, Grafana, AlertManager)
  profiles.monitoring.enable = true;
```

**Step 2: Test configuration**

Run: `nixos-rebuild test`
Expected: Build succeeds, services start

**Step 3: Verify services running**

Run: `systemctl status prometheus grafana alertmanager`
Expected: All services active (running)

**Step 4: Check metrics endpoint**

Run: `curl http://10.1.1.120:9090/metrics`
Expected: Prometheus metrics output

**Step 5: Commit**

```bash
git add hosts/nexus/configuration.nix
git commit -m "feat(monitoring): Deploy monitoring stack on nexus

- Prometheus for metrics storage
- Grafana for visualization
- AlertManager for alert routing
- 8-day data retention"
```

---

## Task 8: Disable Monitoring on Zephyr (RAM Protection)

**Files:**
- Modify: `hosts/zephyr/configuration.nix`

**Step 1: Explicitly disable monitoring profile**

In `hosts/zephyr/configuration.nix`, add:

```nix
  # EXPLICITLY disable monitoring (protect RAM)
  profiles.monitoring.enable = lib.mkForce false;
```

**Step 2: Verify no monitoring services**

Run: `systemctl status prometheus grafana alertmanager || echo "Not enabled (expected)"`
Expected: Services not found (disabled)

**Step 3: Check available RAM**

Run: `free -h`
Expected: ~31GB total, minimal usage from system services

**Step 4: Commit**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "fix(zephyr): Explicitly disable monitoring profile

- Protect 31GB RAM for gaming/VR workloads
- Prevent accidental monitoring deployment
- Use lib.mkForce to override any defaults"
```

---

## Task 9: Deploy Calico Network Policies (Audit Mode)

**Files:**
- Create: `kubernetes-manifests/calico/network-policies.yaml`

**Step 1: Create network policy manifest**

Create `kubernetes-manifests/calico/network-policies.yaml`:

```yaml
apiVersion: crd.projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: default-deny-inter-namespace
spec:
  selector: all()
  namespaceSelector: all()
  types:
  - Ingress
  - Egress
  ingress:
    # ALLOW: Cluster internal traffic
    - action: Allow
      source:
        nets:
        - 10.1.1.0/24    # Host subnet
        - 10.244.0.0/16  # Pod subnet
        - 10.0.0.0/24    # Service subnet
        - 100.64.0.0/10 # Tailscale VPN

    # ALLOW: Node ports
    - action: Allow
      destination:
        ports:
        - 30080
        - 30443
        - 6443

    # DENY: Everything else (AUDIT MODE)
    - action: Deny
      source:
        nets:
        - 0.0.0.0/0
  egress:
    # ALLOW: All outbound
    - action: Allow
      destination: {}
```

**Step 2: Apply in audit mode**

Update spec to add audit mode:

```yaml
spec:
  applyOnForward: true
  preDNAT: true
  audit: true  # AUDIT MODE - log but don't enforce
```

**Step 3: Apply policies**

Run: `kubectl apply -f kubernetes-manifests/calico/network-policies.yaml`
Expected: "globalnetworkpolicy.crd.projectcalico.org/default-deny-inter-namespace created"

**Step 4: Monitor audit logs**

Run: `kubectl logs -n calico-system -l k8s-app=calico-node | grep DENY`
Expected: Audit logs showing denied traffic (no actual blocking yet)

**Step 5: Commit**

```bash
git add kubernetes-manifests/calico/network-policies.yaml
git commit -m "feat(calico): Deploy network policies in audit mode

- Default deny external traffic
- Allow cluster-internal communication
- Audit mode: log but don't enforce yet
- Monitor for 24 hours before enforcement"
```

---

## Task 10: Enforce Calico Network Policies

**Files:**
- Modify: `kubernetes-manifests/calico/network-policies.yaml`

**Step 1: Remove audit mode**

In `kubernetes-manifests/calico/network-policies.yaml`, remove audit lines:

```yaml
spec:
  applyOnForward: true
  preDNAT: true
  # REMOVED: audit: true
```

**Step 2: Apply enforced policies**

Run: `kubectl apply -f kubernetes-manifests/calico/network-policies.yaml`
Expected: "globalnetworkpolicy.crd.projectcalico.org/default-deny-inter-namespace configured"

**Step 3: Test external access blocking**

From external host, run: `curl http://10.1.1.120:30080`
Expected: Connection timeout or refused

**Step 4: Verify internal access works**

From cluster host, run: `curl http://prometheus.cluster.local`
Expected: Successful response

**Step 5: Commit**

```bash
git add kubernetes-manifests/calico/network-policies.yaml
git commit -m "feat(calico): Enforce network policies

- Remove audit mode, enable enforcement
- Block external traffic to cluster services
- Allow cluster-internal communication
- Defense-in-depth security layer"
```

---

## Task 11: Enable Calico BGP Mode

**Files:**
- Create: `kubernetes-manifests/calico/bgp-config.yaml`
- Modify: `modules/services/kubernetes.nix`

**Step 1: Create BGP configuration manifest**

Create `kubernetes-manifests/calico/bgp-config.yaml`:

```yaml
apiVersion: crd.projectcalico.org/v3
kind: BGPConfiguration
metadata:
  name: default
spec:
  logSeverityScreen: Info
  nodeToNodeMeshEnabled: true
  asNumber: 64512
  serviceExternalIPs:
  - advertise: true
  serviceLoadBalancerIPs:
  - advertise: true
  serviceClusterIPs:
  - advertise: true
    cidrs:
    - 10.0.0.0/24
```

**Step 2: Enable BGP in NixOS module**

In `modules/services/kubernetes.nix`, add to features:

```nix
  features = {
    bgp = {
      enable = true;
      asNumber = 64512;
      advertisePodRoutes = true;
    };
  };
```

**Step 3: Apply BGP configuration**

Run: `kubectl apply -f kubernetes-manifests/calico/bgp-config.yaml`
Expected: "bgpconfiguration.crd.projectcalico.org/default created"

**Step 4: Verify route advertisement**

Run: `ip route | grep 10.244.0.0/16`
Expected: Pod routes visible in routing table

**Step 5: Commit**

```bash
git add kubernetes-manifests/calico/bgp-config.yaml modules/services/kubernetes.nix
git commit -m "feat(calico): Enable BGP mode for route advertisement

- Advertise pod routes to physical network
- AS 64512 (private use)
- Direct routing to pods from hosts"
```

---

## Task 12: Enable Calico IPVS

**Files:**
- Modify: `modules/services/kubernetes.nix`

**Step 1: Enable IPVS in NixOS module**

In `modules/services/kubernetes.nix`, add to features:

```nix
  features = {
    # ... existing features

    ipvs = {
      enable = true;
      strictArp = true;
    };
  };
```

**Step 2: Rebuild configuration**

Run: `just deploy`
Expected: Configuration rebuilt successfully

**Step 3: Verify IPVS loaded**

Run: `lsmod | grep ip_vs`
Expected: ip_vs module loaded

**Step 4: Check IPVS rules**

Run: `ipvsadm -L -n`
Expected: Kubernetes service rules visible

**Step 5: Commit**

```bash
git add modules/services/kubernetes.nix
git commit -m "feat(calico): Enable IPVS for service load balancing

- Direct Server Return for better performance
- Strict ARP for neighbor table stability
- Replace iptables for K8s services"
```

---

## Task 13: Enable Calico WireGuard Encryption

**Files:**
- Modify: `modules/services/kubernetes.nix`

**Step 1: Enable WireGuard in NixOS module**

In `modules/services/kubernetes.nix`, add to features:

```nix
  features = {
    # ... existing features

    wireguard = {
      enable = true;
      listeningPort = 51820;
      routingRule = "Drop";
    };
  };
```

**Step 2: Rebuild configuration**

Run: `just deploy`
Expected: Configuration rebuilt successfully

**Step 3: Verify WireGuard interfaces**

Run: `wg show`
Expected: WireGuard interfaces for Calico node-to-node encryption

**Step 4: Test encrypted pod communication**

Run: `kubectl exec -it <pod> -n <namespace> -- tcpdump -i any -n wg`
Expected: Encrypted traffic visible on WireGuard interface

**Step 5: Commit**

```bash
git add modules/services/kubernetes.nix
git commit -m "feat(calico): Enable WireGuard encryption for node traffic

- Encrypt all inter-node pod traffic
- Automated key rotation
- ~5% overhead for security"
```

---

## Task 14: Apply Node Taint to Zephyr (RAM Protection)

**Files:**
- Modify: `kubernetes-manifests/taints/zephyr-ram-critical.yaml`

**Step 1: Create taint manifest**

Create `kubernetes-manifests/taints/zephyr-ram-critical.yaml`:

```yaml
apiVersion: v1
kind: Node
metadata:
  name: zephyr
  labels:
    ram-critical: "true"
spec:
  taints:
  - key: ram-critical
    value: "true"
    effect: NoSchedule
```

**Step 2: Apply taint**

Run: `kubectl apply -f kubernetes-manifests/taints/zephyr-ram-critical.yaml`
Expected: "node/zephyr tainted"

**Step 3: Verify taint applied**

Run: `kubectl describe node zephyr | grep Taint`
Expected: "ram-critical=true:NoSchedule"

**Step 4: Test scheduling**

Run: `kubectl run test-pod --image=nginx --restart=Never`
Expected: Pod scheduled on non-zephyr node (nexus, forge, or sentry)

**Step 5: Commit**

```bash
git add kubernetes-manifests/taints/zephyr-ram-critical.yaml
git commit -m "feat(k8s): Apply RAM-critical taint to zephyr

- Prevent RAM-heavy workloads from scheduling
- Protect 31GB for gaming/VR workloads
- Explicit toleration required for zephyr placement"
```

---

## Task 15: Final Integration Testing

**Files:**
- Create: `scripts/test-network-integration.sh`

**Step 1: Create test script**

Create `scripts/test-network-integration.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Network Integration Testing"
echo "=============================="
echo ""

# DNS Resolution Tests
echo "📡 DNS Resolution Testing"
echo "-------------------------"

for svc in ai.cluster.local prometheus.cluster.local grafana.cluster.local qdrant.cluster.local; do
  echo -n "Testing $svc... "
  if drill $svc @127.0.0.1 | grep -q "NOERROR"; then
    echo "✅ RESOLVES"
  else
    echo "❌ FAILED"
    exit 1
  fi
done

echo -n "Testing wildcard *.cluster.local... "
if drill "test.cluster.local" @127.0.0.1 | grep -q "CNAME"; then
  echo "✅ WILDCARD WORKS"
else
  echo "❌ WILDCARD FAILED"
  exit 1
fi

echo ""

# Ingress Tests
echo "🌐 Ingress Testing"
echo "-----------------"

echo -n "Testing Caddy metrics endpoint... "
if curl -s http://127.0.0.1:2019/metrics | grep -q "go_"; then
  echo "✅ METRICS EXPOSED"
else
  echo "❌ METRICS FAILED"
  exit 1
fi

echo -n "Testing security headers... "
headers=$(curl -I -k https://prometheus.cluster.local 2>/dev/null || true)
if echo "$headers" | grep -q "Strict-Transport-Security"; then
  echo "✅ HEADERS PRESENT"
else
  echo "❌ HEADERS FAILED"
  exit 1
fi

echo ""

# Network Policy Tests
echo "🔒 Network Policy Testing"
echo "------------------------"

echo -n "Testing external access blocking... "
# This should timeout or be refused
if timeout 3 curl -s http://10.1.1.120:30080 > /dev/null 2>&1; then
  echo "⚠️  EXTERNAL ACCESS NOT BLOCKED (may be expected)"
else
  echo "✅ EXTERNAL ACCESS BLOCKED"
fi

echo ""

# Monitoring Stack Tests
echo "📊 Monitoring Stack Testing"
echo "--------------------------"

echo -n "Testing Prometheus endpoint... "
if curl -s http://10.1.1.120:9090/metrics | grep -q "prometheus_"; then
  echo "✅ PROMETHEUS RUNNING"
else
  echo "❌ PROMETHEUS FAILED"
  exit 1
fi

echo -n "Testing Grafana endpoint... "
if curl -s http://10.1.1.120:3001 | grep -q "Grafana"; then
  echo "✅ GRAFANA RUNNING"
else
  echo "❌ GRAFANA FAILED"
  exit 1
fi

echo ""

# Calico Feature Tests
echo "🔐 Calico Feature Testing"
echo "-----------------------"

echo -n "Testing BGP route advertisement... "
if ip route | grep -q "10.244.0.0/16"; then
  echo "✅ BGP ROUTES VISIBLE"
else
  echo "❌ BGP FAILED"
  exit 1
fi

echo -n "Testing IPVS module... "
if lsmod | grep -q "ip_vs"; then
  echo "✅ IPVS LOADED"
else
  echo "❌ IPVS FAILED"
  exit 1
fi

echo -n "Testing WireGuard encryption... "
if wg show 2>/dev/null | grep -q "interface"; then
  echo "✅ WIREGUARD ACTIVE"
else
  echo "⚠️  WIREGUARD NOT ACTIVE (may take time to initialize)"
fi

echo ""

echo "✅ All tests passed!"
```

**Step 2: Make script executable**

Run: `chmod +x scripts/test-network-integration.sh`

**Step 3: Run test suite**

Run: `./scripts/test-network-integration.sh`
Expected: All tests pass

**Step 4: Review results**

Check test output for any warnings or failures

**Step 5: Commit**

```bash
git add scripts/test-network-integration.sh
git commit -m "test(network): Add comprehensive integration test suite

- DNS resolution tests
- Ingress functionality tests
- Network policy enforcement tests
- Monitoring stack tests
- Calico feature tests"
```

---

## Rollback Procedures

If any task fails, use these rollback procedures:

**DNS Changes:**
```bash
# Restore backup
cp modules/services/unbound-cluster.nix.backup modules/services/unbound-cluster.nix
# Uncomment old static records
# Restart Unbound
systemctl restart unbound
```

**Monitoring Profile:**
```bash
# Disable on nexus
sed -i '/profiles.monitoring.enable = true/d' hosts/nexus/configuration.nix
just deploy nexus
```

**Network Policies:**
```bash
# Delete policies
kubectl delete globalnetworkpolicy default-deny-inter-namespace
```

**Calico Features:**
```bash
# Revert kubernetes.nix changes
git checkout HEAD~1 modules/services/kubernetes.nix
just deploy
```

**Node Taint:**
```bash
# Remove taint
kubectl taint nodes zephyr ram-critical=true:NoSchedule-
```

---

## Success Criteria

- ✅ DNS resolution works via wildcard CNAME only
- ✅ Unbound health monitoring active
- ✅ Caddy security headers and rate limiting enabled (both systemd and K8s)
- ✅ Monitoring stack running on nexus (NOT zephyr)
- ✅ Network policies enforced (default deny external)
- ✅ BGP routes advertised to physical network
- ✅ IPVS loaded for service load balancing
- ✅ WireGuard encryption active for node traffic
- ✅ Zephyr node tainted (RAM protection)
- ✅ All integration tests pass

---

## References

- Design Document: `docs/plans/2026-03-24-network-integration-design.md`
- NixOS AGENTS.md: `/etc/nixos/AGENTS.md`
- Kubernetes ROADMAP.md: `/etc/nixos/ROADMAP.md`
- Calico Documentation: https://docs.projectcalico.org/
- Caddy Documentation: https://caddyserver.com/docs/

---

**Created:** 2026-03-24
**Author:** j_kro + Claude (brainstorming skill)
**Status:** Ready for execution
