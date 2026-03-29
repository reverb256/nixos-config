# Networking Security Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remediate all 16 findings from the networking security audit across the 4-host NixOS cluster.

**Architecture:** Changes target the centralized networking modules (`cluster-networking.nix`, `unbound-common.nix`, `keepalived-vip.nix`, `kubernetes.nix`) plus host-specific firewall rules. Each task is an independent commit that can be deployed incrementally. All changes follow the NixOS declarative model — edit config, `nix flake check`, `nixos-rebuild test`, then `just deploy`.

**Tech Stack:** NixOS, nftables/iptables firewall, Unbound DNS, Keepalived VRRP, Kubernetes v1.35.0, Calico CNI, Agenix secrets

---

## Pre-Requisites

- Current branch: `feature/x86-64-v3-migration`
- All changes must pass `nix flake check` before committing
- Use `nixos-rebuild test` to apply without boot persistence (safer)
- Use `just deploy` for multi-host rollout after local verification
- **CRITICAL**: Do NOT background nixos-rebuild commands

---

## Task 1: Remove Plaintext Akash Mnemonic (CRITICAL)

**Files:**
- Modify: `hosts/zephyr/configuration.nix` (line ~248)

**Step 1: Remove the mnemonic comment**

In `hosts/zephyr/configuration.nix`, find and remove the line:
```
      # Mnemonic: zebra unknown capital train decide glue sphere acid actual focus lounge green ancient never visual either glimpse vault verb athlete tiger lamp catch jewel
```

Replace it with:
```
      # Mnemonic: stored in agenix (secrets/akash-provider-mnemonic.age)
```

**Step 2: Verify no other plaintext secrets in the file**

Run: `grep -n 'mnemonic\|Mnemonic\|zebra.*capital' hosts/zephyr/configuration.nix`
Expected: Only the reference to agenix, no actual mnemonic words.

**Step 3: Commit**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "security: remove plaintext Akash mnemonic from config"
```

---

## Task 2: Move Garage S3 Access Key to Agenix (CRITICAL)

**Files:**
- Modify: `hosts/zephyr/configuration.nix` (line ~385)
- Modify: `secrets/secrets.nix` (add new secret entry)

**Step 1: Create the agenix secret file**

```bash
echo "GKac91d924fc76a30b9bcf6c3e" | agenix -e secrets/garage-s3-access-key.age
```

**Step 2: Register in secrets.nix**

Add to `secrets/secrets.nix`:
```nix
"garage-s3-access-key.age".publicKeys = [ zephyr nexus ];
```

**Step 3: Replace plaintext key in zephyr config**

In `hosts/zephyr/configuration.nix`, change:
```nix
accessKey = "GKac91d924fc76a30b9bcf6c3e";
```
To:
```nix
accessKeyFile = "/run/agenix/garage-s3-access-key";
```

**Step 4: Verify build**

Run: `nix flake check`
Expected: Passes

**Step 5: Commit**

```bash
git add secrets/garage-s3-access-key.age secrets/secrets.nix hosts/zephyr/configuration.nix
git commit -m "security: move Garage S3 access key to agenix"
```

---

## Task 3: Add VRRP Authentication to Keepalived (CRITICAL)

**Files:**
- Modify: `modules/services/keepalived-vip.nix` (line ~50-65)
- Create: agenix secret for VRRP password

**Step 1: Add authentication option to keepalived-vip module**

In `modules/services/keepalived-vip.nix`, add a new option after `enableHealthCheck`:

```nix
    authPassword = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "VRRP authentication password (use agenix secret path)";
    };
```

**Step 2: Add authentication block to vrrpInstances**

In the same file, inside `vrrpInstances.kubernetes-api`, add after `virtualIps`:

```nix
        authentication = lib.mkIf (cfg.authPassword != null) {
          authType = "PASS";
          authPass = cfg.authPassword;
        };
```

**Step 3: Create VRRP password secret**

```bash
head -c 16 /dev/urandom | base64 | agenix -e secrets/vrrp-auth-password.age
```

**Step 4: Register in secrets.nix**

```nix
"vrrp-auth-password.age".publicKeys = [ zephyr nexus sentry ];
```

**Step 5: Set password on all VRRP-enabled hosts**

In `hosts/zephyr/configuration.nix`, add to `services.keepalived-vip`:
```nix
authPassword = "REPLACE_WITH_GENERATED_PASSWORD";  # TODO: use agenix path
```

In `hosts/nexus/configuration.nix` and `hosts/sentry/configuration.nix`, add the same password.

**Step 6: Verify build**

Run: `nix flake check`
Expected: Passes

**Step 7: Commit**

```bash
git add modules/services/keepalived-vip.nix secrets/vrrp-auth-password.age secrets/secrets.nix hosts/*/configuration.nix
git commit -m "security: add VRRP authentication to Keepalived VIP failover"
```

---

## Task 4: Restrict K8s API Port 6443 (HIGH)

**Files:**
- Modify: `modules/networking/cluster-networking.nix` (lines 220-241)

**Step 1: Remove 6443 from base allowedTCPPorts**

In `modules/networking/cluster-networking.nix`, change the firewall section:

```nix
    networking.firewall = {
      enable = true;
      allowedTCPPorts = lib.mkOptionDefault [
        53    # DNS (Unbound)
        22    # SSH
        10250 # Kubelet API (required for kubectl exec/logs, Calico health checks)
        # NOTE: 6443 removed from base — restricted to cluster LAN + Tailscale below
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        53    # DNS (Unbound)
        41641 # Tailscale coordination server
      ];
      # Allow Kubernetes pod network to reach Unbound DNS
      extraCommands = ''
        iptables -A nixos-fw -s 10.244.0.0/16 -p udp --dport 53 -j nixos-fw-accept
        iptables -A nixos-fw -s 10.244.0.0/16 -p tcp --dport 53 -j nixos-fw-accept
      '';
      # K8s API: accessible via Tailscale VPN AND cluster LAN
      interfaces."tailscale0".allowedTCPPorts = [ 6443 ];
      # Allow K8s API from cluster subnet (nodes need it for etcd/apiserver communication)
      extraInputRules = ''
        # K8s API server - cluster LAN only
        ip46 saddr 10.1.1.0/24 tcp dport 6443 accept
        # K8s API server - pod network (for in-cluster access)
        ip46 saddr 10.244.0.0/16 tcp dport 6443 accept
      '';
    };
```

**Step 2: Verify all hosts still build**

Run: `nix flake check`
Expected: Passes

**Step 3: Commit**

```bash
git add modules/networking/cluster-networking.nix
git commit -m "security: restrict K8s API (6443) to Tailscale + cluster LAN only"
```

---

## Task 5: Restrict Kubelet API (10250) to Cluster LAN (MEDIUM)

**Files:**
- Modify: `modules/networking/cluster-networking.nix`

**Step 1: Remove 10250 from base allowedTCPPorts**

In the same `cluster-networking.nix` firewall section, change:
```nix
      allowedTCPPorts = lib.mkOptionDefault [
        53    # DNS (Unbound)
        22    # SSH
        # NOTE: 10250 removed — restricted to cluster LAN below
      ];
```

**Step 2: Add kubelet access rule to extraInputRules**

Append to the `extraInputRules` string:
```nix
        # Kubelet API - cluster LAN + pod network only
        ip46 saddr 10.1.1.0/24 tcp dport 10250 accept
        ip46 saddr 10.244.0.0/16 tcp dport 10250 accept
```

**Step 3: Verify build**

Run: `nix flake check`
Expected: Passes

**Step 4: Commit**

```bash
git add modules/networking/cluster-networking.nix
git commit -m "security: restrict Kubelet API (10250) to cluster LAN + pod network"
```

---

## Task 6: Restrict Zephyr Internal Services to Localhost/Cluster (HIGH)

**Files:**
- Modify: `hosts/zephyr/configuration.nix` (firewall section, lines 88-131)

**Step 1: Move internal services off the all-interfaces port list**

Replace the Zephyr firewall section:

```nix
    firewall = {
      allowedTCPPorts = [
        9757  # WiVRn main port
        53317 # LocalSend (file sharing)
        # NOTE: Internal services moved to interface-specific rules below
      ];
      allowedUDPPorts = [
        9757 # WiVRn
        9758 # WiVRn
        9759 # WiVRn
        27031 # Steam UDP
        27036 # Steam UDP
        5353 # mDNS
        9947 # WiVRn
        53317 # LocalSend (multicast discovery)
      ];
      interfaces = {
        "tailscale0".allowedTCPPorts = [
          18789  # Steam Remote Play
          18790  # Steam Remote Play (secondary)
          8080   # AI Inference Gateway (Tailscale only)
        ];
        # NFS server - allow local network only
        "enp38s0".allowedTCPPorts = [
          111    # rpcbind
          2049   # nfs
          20048  # mountd
          8080   # AI Gateway (LAN access for Kubernetes nodes)
          50000  # Nix binary cache (cluster builds)
        ];
        "enp38s0".allowedUDPPorts = [
          111
          2049
          20048
        ];
      };
    };
```

Services now restricted:
- `8080` (AI Gateway): Tailscale + LAN only (was: all interfaces)
- `3333` (XMRig proxy): Removed from public — bind to 127.0.0.1 in xmrig-proxy config
- `8888` (CFSSL CA): Removed — bind to 127.0.0.1 or disable
- `3900/3901` (Garage S3): Removed — bind to cluster IP only
- `50000` (Nix cache): LAN interface only
- `19898` (Spacebot): Removed — bind to 127.0.0.1

**Step 2: Bind XMRig proxy to localhost**

Find the xmrig-proxy config in `hosts/zephyr/configuration.nix` and ensure the bind address is localhost. The proxy is for internal cluster miners only — they connect via the stratum protocol to `10.1.1.110:3333`, which should now use the LAN interface rule instead of a global port.

If 3333 is still needed for LAN miners, add to `enp38s0.allowedTCPPorts` instead of global.

**Step 3: Verify build**

Run: `nix flake check`
Expected: Passes

**Step 4: Commit**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "security: restrict Zephyr internal services to localhost/LAN/Tailscale"
```

---

## Task 7: Restrict Nexus Internal Services (HIGH)

**Files:**
- Modify: `hosts/nexus/configuration.nix` (firewall section)

**Step 1: Restrict Nexus ports to cluster interface**

Replace the Nexus firewall section:

```nix
    firewall = {
      allowedTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472 # VXLAN overlay (Calico IPIP)
      ];
      # Internal services on LAN interface only
      interfaces."enp7s0".allowedTCPPorts = [
        3900  # Garage S3 API
        3901  # Garage RPC
        8080  # AI inference (LAN for K8s nodes)
      ];
    };
```

Remove 10250 from the Nexus base ports — it's now handled cluster-wide in Task 5.

**Step 2: Verify build**

Run: `nix flake check`

**Step 3: Commit**

```bash
git add hosts/nexus/configuration.nix
git commit -m "security: restrict Nexus internal services to LAN interface"
```

---

## Task 8: Restrict Forge Internal Services (HIGH)

**Files:**
- Modify: `hosts/forge/configuration.nix` (firewall section)

**Step 1: Restrict Forge ports**

Replace the Forge firewall section:

```nix
    firewall = {
      allowedTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472 # VXLAN overlay
      ];
      # Internal services on LAN interface only
      interfaces."eno1".allowedTCPPorts = [
        3334  # gpu-proxy-cpp
        3900  # Garage S3 API (if needed)
        3901  # Garage RPC (if needed)
      ];
    };
```

**Step 2: Verify build**

Run: `nix flake check`

**Step 3: Commit**

```bash
git add hosts/forge/configuration.nix
git commit -m "security: restrict Forge internal services to LAN interface"
```

---

## Task 9: Restrict Sentry Internal Services (HIGH)

**Files:**
- Modify: `hosts/sentry/configuration.nix` (firewall section)

**Step 1: Restrict Sentry ports**

```nix
    firewall = {
      allowedTCPPortRanges = lib.mkOptionDefault [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472 # VXLAN overlay
      ];
      # Internal services on LAN interface only
      interfaces."enp7s0".allowedTCPPorts = [
        3100  # Loki
        3900  # Garage S3 API
        3901  # Garage RPC
      ];
    };
```

**Step 2: Verify build**

Run: `nix flake check`

**Step 3: Commit**

```bash
git add hosts/sentry/configuration.nix
git commit -m "security: restrict Sentry internal services to LAN interface"
```

---

## Task 10: Enable DNS-over-TLS in Unbound (HIGH)

**Files:**
- Modify: `modules/services/unbound-common.nix` (lines 50-78)

**Step 1: Enable TLS upstream and use DoT port 853**

In `modules/services/unbound-common.nix`, change the server section:

```nix
          # TLS settings for DNS-over-TLS
          tls-cert-bundle = "/etc/ssl/certs/ca-bundle.crt";
          tls-upstream = true;  # ENABLED: DNS-over-TLS to upstream resolvers
```

Change the `forward-zone` to use port 853:

```nix
        forward-zone = [
          {
            name = ".";
            forward-addr = [
              "1.1.1.1@853"           # Cloudflare DNS-over-TLS
              "1.0.0.1@853"           # Cloudflare DNS-over-TLS secondary
              "8.8.8.8@853"           # Google DNS-over-TLS
              "8.8.4.4@853"           # Google DNS-over-TLS secondary
              "9.9.9.9@853"           # Quad9 DNS-over-TLS
              "149.112.112.112@853"   # Quad9 DNS-over-TLS secondary
            ];
            forward-tls-upstream = true;
          }
        ];
```

**Step 2: Test on Zephyr first**

Run: `nixos-rebuild test --flake .#zephyr`
Then verify DNS works: `dig @127.0.0.1 google.com`

**Step 3: Deploy to all hosts**

Run: `just deploy`

**Step 4: Commit**

```bash
git add modules/services/unbound-common.nix
git commit -m "security: enable DNS-over-TLS for all upstream DNS resolvers"
```

---

## Task 11: Disable Unbound Debug Logging (MEDIUM)

**Files:**
- Modify: `modules/services/unbound-common.nix` (lines 48-52)

**Step 1: Reduce logging verbosity**

Change the logging section:

```nix
          # Privacy (production logging)
          logfile = "/var/log/unbound.log";
          use-syslog = true;
          log-queries = false;
          log-replies = false;
          verbosity = 1;
```

**Step 2: Verify build**

Run: `nix flake check`

**Step 3: Commit**

```bash
git add modules/services/unbound-common.nix
git commit -m "security: disable Unbound debug logging for production"
```

---

## Task 12: Restrict K8s API Server Bind Address (CRITICAL)

**Files:**
- Modify: `modules/services/kubernetes.nix` (apiserverBindAddress default)

**Step 1: Change default bind address**

In `modules/services/kubernetes.nix`, change:

```nix
    apiserverBindAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "API server bind address. Use cluster IP + VIP for security.";
    };
```

To:

```nix
    apiserverBindAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";  # Keep 0.0.0.0 for VIP compatibility (firewall restricts access)
      description = "API server bind address. Firewall rules restrict to Tailscale + cluster LAN.";
    };
```

**NOTE:** The K8s API server MUST bind to `0.0.0.0` for the Keepalived VIP (10.1.1.100) to work. The VIP is a floating address that appears on any master node. Binding to a specific IP would break VIP failover.

**Instead, the firewall rules from Task 4 restrict access to 6443.** This is the correct approach for VIP-based HA.

No code change needed for this task — the firewall restrictions in Task 4 are the actual fix.

**Step 2: Verify (no-op, documented for completeness)**

Mark as addressed by Task 4.

---

## Task 13: Enable Calico WireGuard for Pod Traffic Encryption (MEDIUM)

**Files:**
- Modify: `modules/services/kubernetes.nix` (calicoWireguard default)

**Step 1: Enable WireGuard by default**

Find the `calicoWireguard` option and change:

```nix
      enable = mkOption {
        type = types.bool;
        default = true;  # ENABLED: Encrypt inter-node pod traffic
        description = "Enable WireGuard encryption for inter-node pod traffic";
      };
```

**Step 2: Test on one node first**

Run: `nixos-rebuild test --flake .#zephyr`
Then verify: `kubectl get nodes` (all should still be Ready)

**Step 3: Deploy to all nodes**

Run: `just deploy`

**Step 4: Commit**

```bash
git add modules/services/kubernetes.nix
git commit -m "security: enable Calico WireGuard for encrypted pod traffic"
```

---

## Task 14: Restrict Avahi/mDNS on Headless Nodes (LOW)

**Files:**
- Modify: `modules/networking/cluster-networking.nix` (lines 199-207)

**Step 1: Add option to control Avahi publishing**

Add an option to `clusterNetworking`:

```nix
    avahi = {
      publishAddresses = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to publish addresses via Avahi/mDNS";
      };
    };
```

**Step 2: Use the option in the Avahi config**

Change the avahi section:

```nix
      avahi = {
        enable = true;
        nssmdns4 = true;
        publish = {
          enable = true;
          addresses = cfg.avahi.publishAddresses;
          workstation = true;
        };
      };
```

**Step 3: Disable on headless nodes**

In `hosts/forge/configuration.nix`:
```nix
  clusterNetworking.avahi.publishAddresses = false;
```

In `hosts/sentry/configuration.nix`:
```nix
  clusterNetworking.avahi.publishAddresses = false;
```

**Step 4: Verify build**

Run: `nix flake check`

**Step 5: Commit**

```bash
git add modules/networking/cluster-networking.nix hosts/forge/configuration.nix hosts/sentry/configuration.nix
git commit -m "security: disable Avahi address publishing on headless nodes"
```

---

## Task 15: Fix Duplicate Tailscale Route Advertisements (LOW)

**Files:**
- Modify: `modules/network-constants.nix` (lines 59-72)

**Step 1: Remove route advertisements from Forge and Sentry**

In `modules/network-constants.nix`, change:

```nix
        forge = {
          ...
          # Only Zephyr advertises subnet routes (prevents routing conflicts)
          advertiseRoutes = [];
        };

        sentry = {
          ...
          # Only Zephyr advertises subnet routes (prevents routing conflicts)
          advertiseRoutes = [];
        };
```

Keep Zephyr as the sole route advertiser and Nexus as backup if desired.

**Step 2: Verify build**

Run: `nix flake check`

**Step 3: Commit**

```bash
git add modules/network-constants.nix
git commit -m "fix: remove duplicate Tailscale route advertisements from forge/sentry"
```

---

## Task 16: Enable etcd TLS (CRITICAL — DEFERRED)

**Risk:** Enabling etcd TLS on a running cluster requires coordinated restart of all etcd members. If done incorrectly, the cluster loses quorum and becomes unrecoverable.

**Recommendation:** Defer to a dedicated maintenance window. This requires:
1. Generating TLS certificates for all 3 etcd members
2. Updating `etcdClusterMembers` URLs from `http://` to `https://`
3. Rolling restart of etcd on each member (one at a time)
4. Verifying quorum after each restart

**This should be a separate plan with rollback procedures documented.**

For now, the LAN isolation (10.1.1.0/24 network, no WiFi access to LAN) provides some mitigation.

---

## Task Summary

| Task | Severity | Risk | Hosts Affected |
|------|----------|------|----------------|
| 1. Remove mnemonic | CRITICAL | Low | zephyr |
| 2. S3 key to agenix | CRITICAL | Low | zephyr |
| 3. VRRP auth | CRITICAL | Medium | zephyr, nexus, sentry |
| 4. Restrict K8s API | HIGH | Medium | all |
| 5. Restrict kubelet | MEDIUM | Medium | all |
| 6. Zephyr services | HIGH | Medium | zephyr |
| 7. Nexus services | HIGH | Low | nexus |
| 8. Forge services | HIGH | Low | forge |
| 9. Sentry services | HIGH | Low | sentry |
| 10. DNS-over-TLS | HIGH | Low | all |
| 11. Debug logging | MEDIUM | Low | all |
| 12. API bind address | CRITICAL | N/A | Addressed by Task 4 |
| 13. Calico WireGuard | MEDIUM | Medium | all |
| 14. Avahi restriction | LOW | Low | forge, sentry |
| 15. Tailscale routes | LOW | Low | forge, sentry |
| 16. etcd TLS | CRITICAL | HIGH | DEFERRED |

**Execution order:** Tasks 1-3 (critical) → Tasks 4-6 (high, core infra) → Tasks 7-10 (high, host-specific + DNS) → Tasks 11, 13 (medium) → Tasks 14-15 (low)

**Verification after each task:**
1. `nix flake check` — must pass
2. `nixos-rebuild test --flake .#zephyr` — test on zephyr first
3. `just deploy` — roll out to all hosts
4. `just cluster-status` — verify cluster health
