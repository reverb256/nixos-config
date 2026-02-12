# Mining Configuration

## Cluster Mining Status (2026-02-12)

| Host | CPU Mining | GPU Mining | Power Limit |
|------|------------|------------|-------------|
| zephyr | 16 threads @ 50% | RTX 3090 @ 250W | Conservative |
| nexus | - | 2x RTX 3060 Ti @ 130W | High capacity |
| forge | 95% CPU | 2x RTX 4060 @ 90W + 2x RX 5700 XT @ 140W | Very limited |
| sentry | 8 threads | - | Moderate |

## Services

- **lolminer-nvidia**: GPU mining (NVIDIA)
- **lolminer-amd**: GPU mining (AMD)
- **xmrig**: CPU mining

## API Endpoints (localhost only)

- `http://localhost:4068/summary` - NVIDIA mining stats
- `http://localhost:4069/summary` - AMD mining stats
- `http://localhost:18088` - XMRig API

## Troubleshooting

### Service won't start
```bash
systemctl status lolminer-nvidia
journalctl -u lolminer-nvidia -n 50
nvidia-smi  # Check GPU detection
```

### Common Issues

1. **"sudo: command not found"** - Fixed in current module
2. **"No Cuda driver detected"** - Check `NoNewPrivileges=false` in service config
3. **Segfault (status 139)** - Missing GPU libraries, check LD_LIBRARY_PATH
4. **NVML version mismatch** - Update NVIDIA drivers

### Power Limits

| GPU | Optimal Power |
|-----|---------------|
| RTX 3090 | 220-250W |
| RTX 3060 Ti | 120-140W |
| RTX 4060 | 80-120W |
| RX 5700 XT | 130-150W |

## Security

- Mining user has NO sudo access
- API binds to localhost only
- GPU access via video/render groups
