# Mining Troubleshooting Guide

## Quick Diagnosis

If lolminer-nvidia service fails to start or crashes:

```bash
# Check service status
systemctl status lolminer-nvidia --no-pager

# Check recent logs  
journalctl -u lolminer-nvidia --no-pager -n 20

# Test GPU detection
nvidia-smi

# Check API endpoint
curl -s http://localhost:4068/summary
```

## Common Issues and Solutions

### Issue 1: "sudo: command not found"
**Symptoms**: Service logs show `sudo: command not found` errors
**Cause**: ExecStartPre commands use sudo but PATH doesn't include system binaries
**Solution**: Fixed in mining module - now uses direct nvidia-smi path

### Issue 2: "No Cuda driver or GPUs detected"
**Symptoms**: lolMiner exits immediately with GPU detection failure
**Cause**: Steam-run sandbox too restrictive (NoNewPrivileges=true, PrivateDevices=true)
**Solution**: Set NoNewPrivileges=false, PrivateDevices=false for GPU access

### Issue 3: Service segfaults (status 139)
**Symptoms**: Service exits with segmentation fault
**Cause**: Missing GPU libraries or incorrect permissions
**Solution**: Ensure proper device access and library paths

### Issue 4: "Failed to initialize NVML: Driver/library version mismatch"
**Symptoms**: nvidia-smi commands fail with version mismatch
**Cause**: NVIDIA driver version incompatible with NVML library
**Solution**: Update NVIDIA drivers or use compatible driver version

## Node-Specific Configuration

### Zephyr (RTX 3090)
```nix
services.mining.lolminer.nvidia = {
  enable = true;
  devices = "0";  # Single RTX 3090
  powerLimit = 250; # High power limit for RTX 3090
};
```

### Nexus (RTX 3060 Ti)
```nix
services.mining.lolminer.nvidia = {
  enable = true;
  devices = "0";  # Use only first RTX 3060 Ti
  powerLimit = 130; # Optimized for RTX 3060 Ti
};
```

### Forge (2x RTX 4060)
```nix
services.mining.lolminer.nvidia = {
  enable = true;
  devices = "0,1";  # Both RTX 4060 GPUs
  powerLimit = 90;   # Lower power limit for RTX 4060
};
```

## Power Limit Recommendations

| GPU Model | Optimal Power Limit | Notes |
|------------|-------------------|-------|
| RTX 3090 | 220-250W | High performance card |
| RTX 3060 Ti | 120-140W | Mid-range card |
| RTX 4060 | 80-120W | Efficiency-focused card |

## Testing and Validation

```bash
# Test mining module locally before deployment
sudo nixos-rebuild test --flake .#hostname

# Deploy to specific node
just deploy <hostname>

# Monitor mining performance
curl -s http://localhost:4068/summary | jq .

# Check mining logs in real-time
journalctl -u lolminer-nvidia -f
```

## Performance Monitoring

API endpoints (localhost only):
- `http://localhost:4068/summary` - Mining statistics
- `http://localhost:4068/workerstatus` - Worker details

Expected metrics:
- **Hashrate**: 4-6 g/s per RTX 3060 Ti (CR29 algorithm)
- **Power Usage**: 130W per GPU
- **Temperature**: 60-70°C under load
- **Shares**: Accept/reject ratio should be > 95%

## Security Notes

- Mining user has NO sudo access by design
- Services bind to localhost only (127.0.0.1)
- API ports accessible from localhost only
- All secrets encrypted with agenix
- GPU device access via video/render groups

## Getting Help

If issues persist after applying fixes:

1. Check GPU drivers: `nvidia-smi`
2. Verify NVIDIA kernel modules: `lsmod | grep nvidia`
3. Test mining manually: Run lolMiner directly as mining user
4. Check system resources: `htop`, `free -h`
5. Review logs: `journalctl -u lolminer-nvidia -b`

## Related Documentation

- Mining configuration: `modules/mining.nix`
- GPU setup: `modules/nvidia-wayland.nix`
- Security policy: `modules/users.nix`
- Service logs: `journalctl -u lolminer-nvidia`
- GPU monitoring: `nvidia-smi dmon`