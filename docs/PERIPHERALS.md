# Peripheral Device Configuration

## OpenRazer (Razer Devices)

**Status**: Working via `hardware.openrazer.enable = true`

```bash
systemctl status openrazer-daemon
razer-cli --list
```

## ckb-next (Corsair Devices)

**Status**: Working via ckb-next-daemon

```bash
systemctl status ckb-next-daemon
```

## Troubleshooting

### OpenRazer "Read-only file system"
- Use `hardware.openrazer.enable = true` (built-in module)

### ckb-next USB permission denied
```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
systemctl restart ckb-next-daemon
```

### Devices not detected
1. Ensure user in `openrazer` and `plugdev` groups
2. Reboot or relogin to refresh groups
3. Restart daemons

## Supported Devices

- OpenRazer: https://github.com/openrazer/openrazer/wiki/Supported-devices
- ckb-next: https://github.com/matricali/ckb-next/wiki/Supported-Hardware
