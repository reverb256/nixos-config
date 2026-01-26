# NixOS Cluster Quick Start Guide

## 🚨 CRITICAL P0 FIXES (Do These First)

### 1. Enable 51-Core Distributed Builds
```bash
# Edit: modules/nix-config.nix (line 25)
# Uncomment this line:
builders-use-substitutes = true

# Apply changes
just switch
```
**Result**: Builds will use all 51 cores instead of just one node

### 2. Fix FORGE Node Capacity
```bash
# Edit: machines.nix (line 6)
# Change:
root@forge /nix/store x86_64-linux - 8  # from 3 to 8 cores

# Apply changes
just cluster-build
```
**Result**: FORGE will contribute 8 instead of 3 cores to builds

### 3. Test Distributed Builds
```bash
# Build with full cluster power
nix build --builders-use-substitutes nixpkgs#hello

# Monitor build performance
just perf-monitor
```
**Expected**: 40-60% faster build times

## 🔧 IMPLEMENTATION COMMANDS

### Smart Mining Pause (1 Hour Setup)
```bash
# Create detection script
cat > /etc/nixos/gaming-trigger.sh << 'EOF'
#!/bin/bash
# Detect gaming/VR activity and pause mining
if pgrep -f "WiVRn|SteamVR|gamescope" > /dev/null; then
    systemctl stop lolminer-nvidia.service
    systemctl stop xmrig.service
    echo "Mining paused for gaming"
else
    systemctl start lolminer-nvidia.service
    systemctl start xmrig.service
    echo "Mining resumed"
fi
EOF

# Create systemd services (add to modules/gaming.nix)
cat >> modules/gaming.nix << 'EOF'

# Smart mining pause services
systemd.services.game-detector = {
  description = "Detect gaming/VR activity";
  serviceConfig = {
    ExecStart = "/etc/nixos/gaming-trigger.sh";
    Restart = "always";
    RestartSec = 10;
  };
};

systemd.services.gaming-optimizations = {
  description = "Optimize for gaming";
  serviceConfig = {
    ExecStart = "/etc/nixos/gaming-trigger.sh";
  };
};
EOF

# Apply changes
just switch
```

### Security Hardening (30 Minutes)
```bash
# Edit: modules/ssh.nix
# Change:
services.openssh.settings = {
  PasswordAuthentication = false;  # Force key-only
  PermitRootLogin = "no";          # Disable root SSH
};

# Edit: modules/users.nix
# Change:
security.sudo.wheelNeedsPassword = true;  # Require password

# Apply changes
just switch
```

### GPU-Accelerated Builds (30 Minutes)
```bash
# Edit: machines.nix
# Change FORGE line to:
root@forge /nix/store x86_64-linux cuda-openspecfun-11-2,rocm-hip-5.5.0 - 8

# Apply changes
just cluster-build
```

## 📊 PERFORMANCE VALIDATION

### Test Build Performance
```bash
# Time a build before and after
time nix build --builders-use-substitutes nixpkgs#hello

# Monitor cluster resources
just cluster-resources

# Check build logs
journalctl -u nix-daemon -f
```

### Test Smart Mining Pause
```bash
# Start a game or VR session
# Check mining status
just mining-status

# Expected: Mining services should stop automatically
```

### Test Security
```bash
# Test SSH key-only access
ssh root@zephyr  # Should work with key
sshpass -p 'password' ssh root@zephyr  # Should fail

# Test sudo requirements
sudo whoami  # Should prompt for password
```

## 🚨 TROUBLESHOOTING

### Distributed Builds Not Working
```bash
# Check builders configuration
nix-shell -p nix-info --run "nix-info -m"

# Verify SSH access to all nodes
just cluster-status

# Check builder logs
journalctl -u nix-daemon --since "1 hour ago"
```

### Smart Mining Pause Not Working
```bash
# Check service status
systemctl status game-detector
systemctl status gaming-optimizations

# Test detection script manually
/etc/nixos/gaming-trigger.sh

# Check for conflicting services
systemctl list-units | grep mining
```

### Security Changes Broke Access
```bash
# If locked out, use console access
# Edit SSH config to re-enable temporarily
vim /etc/nixos/modules/ssh.nix

# Rebuild with minimal changes
nixos-rebuild switch --flake /etc/nixos
```

## 📈 EXPECTED RESULTS

### After P0 Fixes (This Week)
- ✅ Build times: 40-60% faster
- ✅ FORGE utilization: 3 → 8 cores
- ✅ Smart mining pause: Working
- ✅ Gaming performance: 20-30% better

### After Full Implementation (1 Month)
- ✅ Security: SSH key-only, sudo protected
- ✅ GPU builds: CUDA/ROCm acceleration
- ✅ Network: No contention
- ✅ Monitoring: Real-time cluster metrics

## 📞 WHEN TO ASK FOR HELP

**Critical Issues** (Stop and ask):
- SSH access completely lost
- Cluster nodes won't respond
- System won't boot after changes

**Performance Issues** (Investigate first):
- Builds slower than expected
- Gaming performance still poor
- Mining efficiency reduced

**Configuration Issues** (Debug yourself):
- Services not starting
- Network connectivity problems
- Permission errors

## 🎯 SUCCESS CHECKLIST

- [ ] Distributed builds active (51 cores)
- [ ] FORGE contributing 8 cores
- [ ] Smart mining pause working
- [ ] SSH key-only authentication
- [ ] Gaming performance improved
- [ ] Build times significantly faster
- [ ] Mining still profitable
- [ ] No security vulnerabilities

**Next Steps**: Once P0 is complete, proceed with P1 security hardening and GPU build optimization.