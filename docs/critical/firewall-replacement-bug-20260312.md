# Firewall Configuration Bug Explained
**Why SSH (port 22) was removed from nexus and sentry**

---

## The Bug: NixOS Option Assignment

**In NixOS module system, setting an option REPLACES the previous value, it doesn't merge.**

### Before Fix (BROKEN)

**modules/networking/cluster-networking.nix:**
```nix
networking.firewall.allowedTCPPorts = [
  53    # DNS (Unbound)
  22    # SSH
  6443  # Kubernetes API
];
```

**hosts/nexus/configuration.nix:**
```nix
networking.firewall.allowedTCPPorts = [
  10250  # Kubelet API
];
```

**What NixOS does:**
1. Reads cluster-networking module → sets ports to `[53, 22, 6443]`
2. Reads nexus configuration → **REPLACES** ports with `[10250]`
3. **Result:** nexus only has port 10250, **SSH PORT 22 IS COMPLETELY GONE**

---

## The Fix: mkOptionDefault

**After fix (modules/networking/cluster-networking.nix):**
```nix
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
  53    # DNS (Unbound)
  22    # SSH
  6443  # Kubernetes API
];
```

**What mkOptionDefault does:**
- Tells NixOS: "This is a default value"
- When nexus sets its own ports, they **MERGE** with defaults instead of replacing
- **Result:** nexus gets `[53, 22, 6443, 10250]` - **SSH IS PRESERVED**

---

## Why This Affected Nexus/Sentry but Not Zephyr/Forge

**Zephyr and Forge:** Haven't rebuilt yet with cluster-networking module, so they still have their old working configs.

**Nexus and Sentry:** Rebuilt with cluster-networking module, which **REPLACED** their firewall rules with just the cluster defaults, but then their node-specific configs **REPLACED** the cluster defaults, creating a mutual annihilation where only node-specific ports remained.

---

## Verification

Check what ports are actually open:

```bash
# On zephyr (working):
sudo firewall-cmd --list-ports
# Or: iptables -L -n | grep -E "dpt:22|dpt:10250"

# Once you access nexus console:
sudo firewall-cmd --list-ports
# Should show: 10250/tcp only (SSH is missing!)

# After rebuild:
sudo firewall-cmd --list-ports
# Should show: 53/tcp, 22/tcp, 6443/tcp, 10250/tcp
```

---

## Fix Applied

**File:** `/etc/nixos/modules/networking/cluster-networking.nix`
**Commit:** `e58839e fix(networking): use mkOptionDefault for firewall ports to allow merging`
**Status:** ✅ Fixed in codebase
**Action Required:** Rebuild nexus and sentry to apply fix

---

## Immediate Action

**Physical console access required for nexus and sentry:**

```bash
cd /etc/nixos
sudo nixos-rebuild switch
```

After reboot, SSH will work because port 22 will be preserved in the merged firewall configuration.
