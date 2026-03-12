# DNS Configuration - Cluster Nodes
**Date:** 2026-03-12
**Status:** Active and Configured

---

## Executive Summary

All 4 cluster nodes run **local Unbound recursive DNS resolvers** that completely bypass the Rogers ISP DNS servers. Queries are encrypted using DNS-over-TLS (DoT) to privacy-focused upstream providers.

**Key Points:**
- ✅ **Rogers DNS NOT used** - completely bypassed
- ✅ **Encrypted DNS queries** via DNS-over-TLS (port 853)
- ✅ **Local hostname resolution** for cluster nodes
- ✅ **Search domains**: `.lan`, `.cluster.local`, `.tigris-ule.ts.net`
- ✅ **Security features**: DNSSEC validation, private address filtering

---

## Architecture

### DNS Query Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     DNS Resolution Path                      │
└─────────────────────────────────────────────────────────────┘

Cluster Node Application
    ↓
    Query: "google.com"
    ↓
┌─────────────────────────────────────────────────────────────┐
│  Local DNS Configuration                                    │
│  - /etc/resolv.conf: nameserver 127.0.0.1                  │
│  - Search domains: lan, cluster.local, tigris-ule.ts.net    │
└─────────────────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────────────────┐
│  Unbound DNS Resolver (localhost:127.0.0.1:53)              │
│  - Checks local zones (.lan, .cluster.local)               │
│  - Checks cache                                            │
│  - If not found: forward to upstream                       │
└─────────────────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────────────────┐
│  DNS-over-TLS Encryption (port 853)                         │
│  - Queries encrypted with TLS                              │
│  - Rogers sees only TLS traffic, not DNS queries           │
└─────────────────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────────────────┐
│  Upstream DNS Providers (in order):                         │
│  1. Quad9 (9.9.9.9@853) - Security-focused                │
│  2. Cloudflare (1.1.1.1@853) - Privacy-focused             │
│  3. Google (8.8.8.8@853) - Global reach                    │
│  4. Tailscale DNS (100.100.100.100) - VPN hostnames        │
└─────────────────────────────────────────────────────────────┘
```

---

## Per-Node Configuration

### All 4 Cluster Nodes

| Node | IP Address | Unbound Running | DNS Config | Search Domains |
|------|------------|-----------------|------------|----------------|
| **zephyr** | 10.1.1.110 | ✅ Active | 127.0.0.1, ::1 | lan, cluster.local, tigris-ule.ts.net |
| **nexus** | 10.1.1.120 | ✅ Active | 127.0.0.1, ::1 | lan, cluster.local, tigris-ule.ts.net |
| **forge** | 10.1.1.130 | ✅ Active | 127.0.0.1, ::1 | lan, cluster.local, tigris-ule.ts.net |
| **sentry** | 10.1.1.140 | ✅ Active | 127.0.0.1, ::1 | lan, cluster.local, tigris-ule.ts.net |

### DNS Configuration Files

**Module:** `/etc/nixos/modules/services/unbound-cluster.nix`

**Enabled on all nodes via:**
```nix
# In each node's configuration.nix
services.unbound-cluster.enable = true;
```

**Search domains configured:**
```nix
# In each node's configuration.nix
networking.searchDomains = ["lan" "cluster.local" "tigris-ule.ts.net"];
```

---

## Unbound DNS Resolver Configuration

### Upstream DNS Servers

**Non-TLS (Fallback):**
- `100.100.100.100` - Tailscale DNS (for VPN hostnames)

**DNS-over-TLS (Primary):**
- `9.9.9.9@853` - Quad9 (security-focused, blocks malicious domains)
- `1.1.1.1@853` - Cloudflare (privacy-focused)
- `8.8.8.8@853` - Google DNS (global reach)

**Port 853 indicates DNS-over-TLS encryption**

### Local DNS Zones

Unbound serves these zones locally (never forwarded to upstream DNS):

| Zone | Purpose | Records |
|------|---------|---------|
| **cluster.local** | Cluster internal domain | zephyr, nexus, forge, sentry |
| **lan** | Local network domain | zephyr, nexus, forge, sentry |
| **tigris-ule.ts.net** | Tailscale VPN domain | VPN hostnames |
| **10.in-addr.arpa** | 10.0.0.0/8 reverse DNS | Private network |
| **168.192.in-addr.arpa** | 192.168.0.0/16 reverse DNS | Private network |
| **16.172.in-addr.arpa** | 172.16.0.0/12 reverse DNS | Private network |

### Local Hostname Records

**Full domain names:**
```
zephyr.cluster.local. → 10.1.1.110
nexus.cluster.local. → 10.1.1.120
forge.cluster.local. → 10.1.1.130
sentry.cluster.local. → 10.1.1.140
```

**Short domain names (via .lan zone):**
```
zephyr.lan. → 10.1.1.110
nexus.lan. → 10.1.1.120
forge.lan. → 10.1.1.130
sentry.lan. → 10.1.1.140
```

**Single-label hostnames (for local queries):**
```
zephyr → 10.1.1.110
nexus → 10.1.1.120
forge → 10.1.1.130
sentry → 10.1.1.140
```

### Security Features

**Enabled:**
- ✅ **DNSSEC validation** - Ensures DNS responses are authentic
- ✅ **Query caching** - Improves performance, reduces upstream queries
- ✅ **Query prefetching** - Pre-fetches likely future queries
- ✅ **Private address filtering** - Prevents leaking internal queries
- ✅ **EDNS buffer size** (1232 bytes) - Optimizes packet size
- ✅ **Hardened against DNS attacks** - glue protection, ID randomness

**Privacy Features:**
- ✅ **Hide identity** - Doesn't expose server version
- ✅ **Hide version** - Doesn't expose Unbound version
- ✅ **No query logging** - Queries not logged by default

---

## Search Domains

### What Search Domains Do

Search domains allow short hostnames to be resolved by automatically appending the domain.

**Example with search domains configured:**
```bash
# These are equivalent:
ping zephyr
ping zephyr.lan
ping zephyr.cluster.local

# All resolve to: zephyr.lan. → 10.1.1.110
```

**Search order (checked in sequence):**
1. `.lan` (local network)
2. `.cluster.local` (cluster internal)
3. `.tigris-ule.ts.net` (Tailscale VPN)

### Usage Examples

**From zephyr:**
```bash
# Short hostnames work with search domains
ping nexus           # Resolves to nexus.lan. → 10.1.1.120
ssh forge.lan       # Resolves to forge.lan. → 10.1.1.130
curl sentry.cluster.local:9090  # Resolves to 10.1.1.140

# Kubernetes service discovery
ping kubernetes.default.svc.cluster.local.  # → 10.0.0.1
```

---

## What Rogers CAN vs CANNOT See

### Rogers ISP (Modem/Gateway)

**✅ What Rogers CAN see:**
- Encrypted TLS traffic to port 853 (Quad9, Cloudflare, Google IPs)
- Connection destinations (IP addresses of DNS servers)
- Volume of traffic (amount of data transferred)
- Connection timing (when queries are made)

**❌ What Rogers CANNOT see:**
- Your actual DNS queries (domain names you're looking up)
- DNS responses (IP addresses you're accessing)
- Your cluster internal hostname queries (zephyr, nexus, etc.)
- The content of your DNS traffic (encrypted with TLS)

### Privacy Analogy

```
WITHOUT DNS-over-TLS:
You → Rogers → Google
      [DNS query visible: "google.com"]

WITH DNS-over-TLS:
You → Encrypted Tunnel → Cloudflare → Google
      [Rogers sees only encrypted traffic to Cloudflare IP]
      [Cannot tell which domains you're visiting]
```

---

## Verification Commands

### Check DNS Configuration on Any Node

```bash
# Verify DNS is set to localhost
cat /etc/resolv.conf
# Expected: nameserver 127.0.0.1

# Check Unbound is running
systemctl status unbound.service
# Expected: Active: active (running)

# Test DNS resolution
dig @127.0.0.1 google.com +short
# Expected: Returns IP addresses

# Test local hostname resolution
dig @127.0.0.1 zephyr.lan +short
# Expected: 10.1.1.110

# Test cluster.local domain
dig @127.0.0.1 nexus.cluster.local +short
# Expected: 10.1.1.120

# Test search domains
ping zephyr
# Expected: Resolves to 10.1.1.110 (searches zephyr.lan, zephyr.cluster.local)
```

### Verify Rogers DNS is NOT Being Used

```bash
# This should work (using local Unbound)
dig @127.0.0.1 example.com

# This would use Rogers DNS directly (not recommended)
dig @64.59.176.16 example.com

# Check what DNS servers the node is actually using
resolvectl status
# Look for "DNS Servers: 127.0.0.1"
```

### Verify DNS-over-TLS is Working

```bash
# Check if Unbound is using TLS
# (Look for connections to port 853)
ss -tn 'sport = :53' | head -5
# Should show local connections on port 53 (DNS)

# Monitor DNS queries
journalctl -u unbound -f
# Shows DNS resolution activity
```

---

## Configuration Files

### Module Configuration

**File:** `/etc/nixos/modules/services/unbound-cluster.nix`

**Key settings:**
```nix
{
  services.unbound-cluster = {
    enable = true;
    upstream = ["100.100.100.100"];  # Tailscale DNS
    upstreamTls = [
      "9.9.9.9@853"    # Quad9
      "1.1.1.1@853"    # Cloudflare
      "8.8.8.8@853"    # Google
    ];
    listenAddress = "10.1.1.110";  # Node-specific IP
    port = 53;
  };

  networking.searchDomains = ["lan" "cluster.local" "tigris-ule.ts.net"];
  networking.nameservers = ["127.0.0.1" "::1"];
}
```

### Node-Specific Files

Each node enables the module:
- `/etc/nixos/hosts/zephyr/configuration.nix`
- `/etc/nixos/hosts/nexus/configuration.nix`
- `/etc/nixos/hosts/forge/configuration.nix`
- `/etc/nixos/hosts/sentry/configuration.nix`

---

## Troubleshooting

### DNS Not Working

**Symptoms:**
- Cannot resolve domain names
- "Temporary failure in name resolution"

**Solutions:**
```bash
# 1. Check Unbound is running
systemctl status unbound.service

# 2. Restart Unbound if needed
sudo systemctl restart unbound.service

# 3. Check DNS configuration
cat /etc/resolv.conf

# 4. Test with explicit DNS server
dig @9.9.9.9 google.com  # Test upstream directly
dig @127.0.0.1 google.com  # Test local Unbound

# 5. Check firewall
sudo ufw status
# Ensure ports 53/tcp and 53/udp are allowed
```

### Local Hostnames Not Resolving

**Symptoms:**
- `ping zephyr` fails
- `ping nexus.lan` fails

**Solutions:**
```bash
# 1. Check Unbound local zones
dig @127.0.0.1 zephyr.lan
dig @127.0.0.1 zephyr.cluster.local

# 2. Check search domains
resolvectl status | grep "Search Domains"

# 3. Test full domain names
ping zephyr.lan.
ping zephyr.cluster.local.

# 4. Check Unbound configuration
cat /etc/unbound/unbound.conf | grep "local-data:"
```

### Slow DNS Resolution

**Symptoms:**
- DNS queries take several seconds
- "dig" commands timeout

**Solutions:**
```bash
# 1. Check if upstream DNS is reachable
ping 9.9.9.9
ping 1.1.1.1

# 2. Test DNS-over-TLS connectivity
openssl s_client -connect 9.9.9.9:853

# 3. Check Unbound cache
unbound-control stats  # (if control interface enabled)

# 4. Restart Unbound
sudo systemctl restart unbound.service
```

---

## Comparison with Rogers DNS

### Rogers ISP DNS (What We DON'T Use)

| Feature | Rogers DNS | Unbound (Our Setup) |
|---------|-----------|-------------------|
| **Servers** | 64.59.176.16, 64.59.176.228 | 127.0.0.1 (local) |
| **Privacy** | ❌ Queries visible to Rogers | ✅ Encrypted with TLS |
| **Control** | ❌ Configured by Rogers | ✅ Full control |
| **Blocking** | ❌ No ad/malware blocking | ✅ Quad9 blocks threats |
| **Local DNS** | ❌ No local hostname resolution | ✅ Full cluster hostname support |
| **DNSSEC** | ❓ Unknown (Rogers-controlled) | ✅ Validated locally |

### Why We Bypass Rogers DNS

**1. Privacy:**
- Rogers cannot see which domains you visit
- Queries encrypted with TLS
- No ISP-level DNS tracking

**2. Security:**
- Quad9 blocks known malicious domains
- DNSSEC validation prevents DNS spoofing
- No ISP DNS hijacking or redirects

**3. Control:**
- Choose your own upstream providers
- Configure local hostnames
- Implement custom DNS policies

**4. Performance:**
- Local caching reduces upstream queries
- Prefetching speeds up repeated queries
- Reduced latency for local hostnames

---

## Future Enhancements

### Potential Improvements

**1. Ad-Blocking DNS (Optional):**
- Replace Quad9 with AdGuard Home on cluster
- Block ads, trackers, malware domains
- Custom whitelist/blacklist

**2. DNS Query Logging (If Desired):**
- Enable unbound-control interface
- Monitor query patterns
- Identify suspicious activity

**3. High Availability:**
- Run multiple Unbound instances
- Configure DNS failover
- Load balance across nodes

**4. Conditional Forwarding:**
- Forward specific domains to different resolvers
- Split-horizon DNS (internal vs external views)
- Per-VLAN DNS policies

### Not Currently Implemented

**❌ Ad-blocking** (Would require AdGuard Home or Pi-hole)
**❌ Per-client DNS policies** (Would need more sophisticated setup)
**❌ DNS query logging** (Privacy-focused, not enabled by default)

---

## Related Documentation

- `/etc/nixos/docs/networking/modem-topology-dual-port-config-20260312.md` - Modem/gateway architecture
- `/etc/nixos/docs/networking/pvid-configuration-plan-20260312.md` - VLAN PVID configuration
- `/etc/nixos/modules/services/unbound-cluster.nix` - Unbound DNS module
- Unbound documentation: https://nlnetlabs.nl/projects/unbound/about/

---

**Status:** ✅ Active and operational on all 4 cluster nodes
**Privacy:** ✅ Rogers cannot see DNS queries (encrypted with TLS)
**Performance:** ✅ Local caching and prefetching enabled
**Security:** ✅ DNSSEC validation and threat blocking (Quad9)

**Last Updated:** 2026-03-12
**Configuration Verified:** Yes - all nodes using 127.0.0.1 (local Unbound)
