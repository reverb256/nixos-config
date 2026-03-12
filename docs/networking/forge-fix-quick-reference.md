# Forge Network Fix - Quick Reference
**For use at forge physical console**

---

## The Fix

**What was changed:**
- Removed lines 49-51 from `/etc/nixos/hosts/forge/configuration.nix`
- These lines disabled DHCP and conflicted with NetworkManager's static IP configuration

**Removed:**
```nix
# Disable DHCP completely (static IP only)
networking.dhcpcd.enable = false;
networking.useDHCP = false;
```

**Why:**
- The cluster-networking module uses NetworkManager to configure static IP
- Disabling DHCP explicitly conflicts with NetworkManager's management
- This caused the interface to have no valid IP configuration

---

## Apply the Fix

At forge's console:

```bash
# 1. Navigate to nixos config
cd /etc/nixos

# 2. Verify the changes are present
git diff hosts/forge/configuration.nix

# 3. Test the configuration
sudo nixos-rebuild test

# 4. If test passes, apply
sudo nixos-rebuild switch

# 5. Verify network is up
ip addr show enp0s31f6
ping -c 3 10.1.1.1
ping -c 3 10.1.1.110
```

---

## Expected Results

After rebuild:
- Interface enp0s31f6 should have IP 10.1.1.130/24
- Default route via 10.1.1.1 should be present
- SSH from other nodes should work
- DNS resolution should work

---

## If It Doesn't Work

### Check 1: NetworkManager Profiles
```bash
nmcli connection show
# Look for "Wired connection 1"
```

### Check 2: Interface Status
```bash
ip addr show enp0s31f6
ip route show
```

### Check 3: NetworkManager Logs
```bash
journalctl -u NetworkManager --no-pager | tail -50
```

### Emergency Rollback
```bash
# Revert the change
cd /etc/nixos
git checkout hosts/forge/configuration.nix

# Rebuild
sudo nixos-rebuild switch
```

---

## Verify Other Nodes

After fixing forge, verify other nodes are reachable:

```bash
# From zephyr:
ping -c 3 10.1.1.120  # nexus
ping -c 3 10.1.1.130  # forge (should work now)
ping -c 3 10.1.1.140  # sentry
```

---

## Technical Summary

**Root Cause:** Configuration conflict between:
- New cluster-networking module (NetworkManager-based)
- Old explicit DHCP disable

**Solution:** Remove redundant DHCP disable, let NetworkManager handle static IP

**Impact:** Forge-only issue, other nodes unaffected

**Prevention:** All nodes now use consistent NetworkManager-based static IP config
