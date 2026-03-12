# Forge Network Fix - Why Rebuild is Required
**Date:** 2026-03-12

---

## The Problem

Forge's network interface is currently **lan0**, but the cluster-networking module expects **enp0s31f6**.

### Why This Happened

1. **Old Configuration:** Used `interface-naming.nix` module to rename all interfaces to `lan0`
   ```nix
   # modules/system/interface-naming.nix
   "10-lan0-forge" = {
     matchConfig.MACAddress = "30:9c:23:ad:98:d1";
     linkConfig.Name = "lan0";
   };
   ```

2. **Configuration Change (2026-03-12):** Disabled `interface-naming.nix` to use native kernel names
   ```nix
   # ./system/interface-naming.nix  # DISABLED: Using native enp*s* naming
   ```

3. **Zephyr was rebuilt** → Interface reverted from `lan0` to `enp38s0` ✓

4. **Forge was NOT rebuilt** → Interface still `lan0` ✗

5. **cluster-networking module** created → Expects `enp0s31f6` (kernel name)

---

## Why The First Attempt Failed

When you tried to apply the new configuration:
1. cluster-networking created NetworkManager profile for **enp0s31f6**
2. But the interface is still named **lan0** (from old systemd link)
3. NetworkManager couldn't find `enp0s31f6`
4. Result: No network configuration applied ❌

---

## The Solution: Rebuild Forge

When you rebuild forge with the new configuration:

```bash
cd /etc/nixos
sudo nixos-rebuild switch
```

### What Happens During Rebuild

1. **NixOS evaluates new configuration**
   - `interface-naming.nix` is **disabled** (commented out in default.nix)
   - No systemd link file created for forge
   - Old systemd link file (`/etc/systemd/network/10-lan0-forge.link`) is **removed**

2. **System boots with new configuration**
   - No systemd link to rename interface
   - System uses kernel native name: **enp0s31f6**
   - Interface appears as `enp0s31f6` instead of `lan0`

3. **NetworkManager applies cluster-networking profile**
   - Finds interface `enp0s31f6` ✓
   - Applies static IP: 10.1.1.130/24
   - Sets gateway: 10.1.1.1
   - Configures DNS: 127.0.0.1 (Unbound)

4. **Network is up!** ✓

---

## Verification Steps

After rebuild, verify:

```bash
# 1. Check interface name changed
ip link show | grep -E '^[0-9]+:'

# Expected output:
# 2: enp0s31f6: <BROADCAST,MULTICAST,UP,LOWER_UP> ...

# 2. Check IP address assigned
ip addr show enp0s31f6

# Expected output:
# inet 10.1.1.130/24 brd 10.1.1.255 scope global enp0s31f6

# 3. Check default route
ip route show

# Expected output:
# default via 10.1.1.1 dev enp0s31f6

# 4. Test connectivity
ping -c 3 10.1.1.1    # Gateway
ping -c 3 10.1.1.110  # Zephyr

# 5. Check NetworkManager profile
nmcli connection show "Wired connection 1"

# Expected output:
# ipv4.addresses: 10.1.1.130/24
# ipv4.gateway: 10.1.1.1
# ipv4.method: manual
```

---

## Why This Is Safe

1. **Rollback available:** If it doesn't work, boot into old generation
2. **Physical access:** You're at the console, can fix issues
3. **Tested on zephyr:** Same change worked there
4. **No data loss:** Configuration change only

---

## Temporary Access During Rebuild

If network goes down during rebuild:

```bash
# Still have TTY console access
# Can edit configuration files
# Can rebuild again
```

---

## Summary

**Problem:** Interface name drift (lan0 vs enp0s31f6)
**Cause:** Forge not rebuilt after disabling interface-naming module
**Solution:** Rebuild with new configuration
**Result:** Interface reverts to enp0s31f6, cluster-networking works

**Status:** Ready to rebuild at forge console
