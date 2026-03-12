# Forge Network Failure - Diagnostic Guide
**Date:** 2026-03-12
**Status:** Network unreachable ("No route to host")
**Node:** Forge (10.1.1.130)

---

## Symptoms

- SSH connection fails: "No route to host"
- Ping tests fail
- Complete network isolation

## Root Cause Analysis

### Likely Issue: NetworkManager Conflict

Forge's configuration has a **conflict between two network management approaches**:

1. **New cluster-networking module** uses NetworkManager with manual static IP
2. **Old forge config** explicitly disables DHCP

**Configuration conflict:**
```nix
# From cluster-networking module (NEW):
networking.networkmanager.ensureProfiles.profiles."Wired connection 1" = {
  ipv4.method = "manual";
  ipv4.address1 = "${cfg.ipAddress}/24";
};

# From forge configuration (OLD - CONFLICTS):
networking.dhcpcd.enable = false;  # <-- CONFLICTS
networking.useDHCP = false;        # <-- CONFLICTS
```

**Why this breaks:**
- NetworkManager tries to manage the interface with a static IP
- But dhcpcd and DHCP are explicitly disabled
- This creates a "no man's land" where neither can properly configure the interface

---

## On-Console Diagnostics

Run these commands at forge's physical console:

### 1. Interface Status
```bash
# Check if interface is up and has IP
ip addr show enp0s31f6

# Expected output should show:
# - Interface is UP
# - Has IPv4 address 10.1.1.130/24
```

### 2. Routing Table
```bash
ip route show

# Expected output should show:
# - Default route via 10.1.1.1
# - Direct route to 10.1.1.0/24
```

### 3. NetworkManager Status
```bash
systemctl status NetworkManager

# Check for connection profiles
nmcli connection show

# Look for:
# - "Wired connection 1" (from cluster-networking)
# - Any conflicting old profiles
```

### 4. Recent Errors
```bash
# Network errors
journalctl -xe | tail -100

# NetworkManager-specific errors
journalctl -u NetworkManager --no-pager | tail -50
```

### 5. Connectivity Tests
```bash
# Test gateway
ping -c 3 10.1.1.1

# Test zephyr
ping -c 3 10.1.1.110

# Test DNS
resolvectl status
```

---

## Fix Procedures

### Fix 1: Remove DHCP Disable Lines (RECOMMENDED)

The cluster-networking module **already** configures static IP via NetworkManager, so these lines are redundant and harmful.

**Edit `/etc/nixos/hosts/forge/configuration.nix`:**

Remove lines 49-51:
```nix
# DELETE THESE:
# Disable DHCP completely (static IP only)
networking.dhcpcd.enable = false;
networking.useDHCP = false;
```

**Rebuild:**
```bash
sudo nixos-rebuild test
# If successful:
sudo nixos-rebuild switch
```

**Why this works:**
- NetworkManager handles the static IP configuration
- No conflict with disabled DHCP
- Clean separation of concerns

---

### Fix 2: Clean Up Old NetworkManager Profiles

If there are multiple conflicting connection profiles:

```bash
# List all connections
nmcli connection show

# Delete old connections (keep "Wired connection 1")
sudo nmcli connection delete "Wired connection 2"
sudo nmcli connection delete "old-profile-name"

# Restart NetworkManager
sudo systemctl restart NetworkManager

# Verify connection
nmcli connection show "Wired connection 1"
ip addr show enp0s31f6
```

---

### Fix 3: Emergency Rollback

If the above fixes don't work, revert the networking changes:

**Edit `/etc/nixos/hosts/forge/configuration.nix`:**

Temporarily disable cluster-networking:
```nix
# clusterNetworking = {
#   enable = true;
#   ...
# };

# Use old manual config instead:
networking = {
  hostName = "forge";
  searchDomains = ["lan" "cluster.local" "tigris-ule.ts.net"];
  interfaces.enp0s31f6.ipv4.addresses = [{
    address = "10.1.1.130";
    prefixLength = 24;
  }];
  defaultGateway = "10.1.1.1";
  dhcpcd.enable = false;
  useDHCP = false;
};
```

```bash
sudo nixos-rebuild switch
```

---

## Prevention

After fixing, verify the configuration is consistent:

```bash
# Check final configuration
sudo nixos-rebuild dry-build

# Test network
ping -c 3 10.1.1.1
ping -c 3 10.1.1.110

# Verify DNS
nslookup forge.lan
nslookup zephyr.lan
```

---

## Other Nodes to Check

After fixing forge, verify other nodes don't have similar conflicts:

```bash
# Check nexus
grep -n "dhcpcd\|useDHCP" hosts/nexus/configuration.nix

# Check sentry
grep -n "dhcpcd\|useDHCP" hosts/sentry/configuration.nix

# Check zephyr
grep -n "dhcpcd\|useDHCP" hosts/zephyr/configuration.nix
```

**Only forge has these lines** - other nodes should be fine.

---

## Technical Details

### Why Forge Had These Lines

Forge was the only node configured with **explicit static IP** configuration before the cluster-networking migration:

```nix
# Old forge config (before cluster-networking):
networking = {
  interfaces.enp0s31f6.ipv4.addresses = [...];
  defaultGateway = "10.1.1.1";
  dhcpcd.enable = false;  # Prevent DHCP from interfering
  useDHCP = false;        # Redundant, but explicit
};
```

**Other nodes** (zephyr, nexus, sentry) were using DHCP, so they didn't have these conflicts.

### How cluster-networking Changes Things

The cluster-networking module **centralizes static IP configuration** using NetworkManager:

```nix
# New cluster-networking approach:
networking.networkmanager.ensureProfiles.profiles."Wired connection 1" = {
  ipv4.method = "manual";
  ipv4.address1 = "${cfg.ipAddress}/24";
  ipv4.gateway = "10.1.1.1";
};
```

This is **cleaner and more consistent**, but conflicts with the old dhcpcd-disable approach.

---

**Next Steps:**
1. Run diagnostics at forge console
2. Apply Fix 1 (remove DHCP disable lines)
3. Rebuild and test
4. Report results
5. Update other nodes if needed
