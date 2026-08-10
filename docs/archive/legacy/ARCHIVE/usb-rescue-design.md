# NixOS USB Rescue Disk - Robust Design

**Status:** Draft | **Created:** 2026-04-28

## Inspiration from Community

- [Restoring Broken Filesystem with Btrfs, NixOS and Restic](https://tbx.at/posts/filesystem-restore/) - Btrfs recovery patterns
- [Btrfs - Official NixOS Wiki](https://wiki.nixos.org/wiki/Btrfs) - Copy-on-write features, repair tools
- [Persistent Btrfs Subvolume Mounting - NixOS Discourse](https://discourse.nixos.org/t/persistent-btrfs-subvolume-mounting/30021) - Subvolume handling
- [NixOS rebuild failing while chrooted - Help](https://discourse.nixos.org/t/nixos-rebuild-failing-while-chrooted/40176) - Chroot rebuild patterns

## Design Principles

1. **Self-Contained** - Works without network if possible
2. **Cluster-Aware** - Knows about all hosts, can mount NFS from Zephyr
3. **Tool-Rich** - Includes btrfs-progs, cryptsetup, mdadm, lvm2, network tools
4. **AI-Assisted** - Hermes integration for guided recovery
5. **Stateless** - All config from NFS, no local state to manage

## Core Components

### 1. Enhanced USB Rescue Configuration

```nix
# hosts/usb-rescue/configuration.nix
{
  # Recovery tools
  environment.systemPackages = with pkgs; [
    btrfs-progs           # Btrfs recovery
    cryptsetup            # LUKS encryption
    mdadm                 # RAID arrays
    lvm2                  # LVM volumes
    nfs-utils             # NFS mounting
    openssh               # Remote access
    tmux                  # Multi-pane recovery sessions
    htop                  # System monitoring
    iotop                 # I/O monitoring
    pciutils              # Hardware detection
    usbutils              # USB device info
    parted                # Partition management
    gdisk                 # GPT partitions
    dosfstools            # FAT filesystem tools
    xfsprogs              # XFS filesystem
    e2fsprogs             # ext4 filesystem
    reiserfsprogs        # ReiserFS
    jfsutils              # JFS
    nilfs-utils          # Nilfs
    f2fs-tools           # F2FS
    zfs                   # ZFS (if needed)

    # Network debugging
    tcpdump
    netcat
    mtr
    dnsutils              # dig, nslookup
    wireguard-tools       # VPN access

    # AI assistance
    hermes-chat           # Local AI agent
  ];

  # Hermes integration for guided recovery
  services.hermes-agent.enable = true;
  services.hermes-agent.config = {
    providers = {
      gateway = {
        base_url = "http://10.15.67.242:8080/v1";
        model = "auto";
      };
    };
    default_provider = "gateway";
  };
}
```

### 2. Automated Recovery Scripts

Location: `/etc/nixos/scripts/rescue/`

#### `detect-hosts.nix` - Auto-discover cluster hosts

```bash
#!/usr/bin/env bash
# Scan local network for known cluster hosts
# Uses ARP ping and SSH host key detection

HOSTS=(
  "zephyr:10.1.1.110"
  "nexus:10.1.1.120"
  "forge:10.1.1.130"
  "sentry:10.1.1.140"
)

for host in "${HOSTS[@]}"; do
  name="${host%:*}"
  ip="${host#*:}"
  if ping -c 1 -W 1 "$ip" &>/dev/null; then
    echo "✓ $name ($ip) is UP"
  else
    echo "✗ $name ($ip) is DOWN"
  fi
done
```

#### `mount-cluster.sh` - Mount all available cluster filesystems

```bash
#!/usr/bin/env bash
# Auto-mount NFS shares and local btrfs volumes
# Detects subvolumes and mounts appropriately

detect_btrfs() {
  for dev in /dev/nvme* /dev/sd*; do
    if blkid "$dev" | grep -q "TYPE=\"btrfs\""; then
      echo "Found btrfs: $dev"
      btrfs filesystem show "$dev"
      btrfs subvolume list "$dev"
    fi
  done
}

mount_nfs() {
  local host="$1"
  local mount="/mnt/nfs-$host"
  mkdir -p "$mount"
  if timeout 5 mount -t nfs -o ro,soft "$host:/etc/nixos" "$mount" 2>/dev/null; then
    echo "✓ Mounted $host:/etc/nixos at $mount"
    return 0
  else
    echo "✗ Failed to mount $host:/etc/nixos"
    return 1
  fi
}
```

#### `rebuild-host.sh` - Rebuild a host from scratch

```bash
#!/usr/bin/env bash
# Usage: rebuild-host.sh <hostname>
# Mounts NFS, detects root device, rebuilds using nixos-enter

set -e

HOSTNAME="$1"
ZEPHYR_IP="10.1.1.110"
MOUNT_NFS="/mnt/nixos-shared"
MOUNT_ROOT="/mnt/target-root"

# Source cluster config
source "$MOUNT_NFS/modules/network-constants.nix"

# Get root device for host
case "$HOSTNAME" in
  nexus)  ROOT_DEV="/dev/nvme1n1p2" ;;
  zephyr) ROOT_DEV="/dev/nvme0n1p2" ;;
  forge)  ROOT_DEV="/dev/nvme0n1p2" ;;
  sentry) ROOT_DEV="/dev/nvme0n1p2" ;;
  *) echo "Unknown host: $HOSTNAME"; exit 1 ;;
esac

# Mount and rebuild
mkdir -p "$MOUNT_ROOT"
mount -o subvol=@ "$ROOT_DEV" "$MOUNT_ROOT"

NIXOS_CONFIG="$MOUNT_NFS" nixos-enter --root "$MOUNT_ROOT" -- \
  nixos-rebuild switch --flake "$MOUNT_NFS#$HOSTNAME"
```

### 3. Interactive Recovery Menu

```bash
#!/usr/bin/env bash
# rescue-menu.sh - TUI-based recovery interface

while true; do
  clear
  cat <<'EOF'
╔═══════════════════════════════════════════════════════════╗
║         NixOS Cluster Rescue Disk v1.0                    ║
╠═══════════════════════════════════════════════════════════╣
║ 1) Detect hosts and scan network                          ║
║ 2) Mount NFS share from Zephyr                            ║
║ 3) Mount local btrfs volumes                              ║
║ 4) Rebuild a host system                                  ║
║ 5) Access shell (with nixos-enter)                        ║
║ 6) Run diagnostics                                        ║
║ 7) Launch Hermes AI assistant                             ║
║ 8) View system logs                                       ║
║ 0) Reboot                                                 ║
╚═══════════════════════════════════════════════════════════╝
EOF

  read -p "Select option: " choice

  case "$choice" in
    1) ./detect-hosts.sh; read -p "Press Enter";;
    2) ./mount-nfs.sh; read -p "Press Enter";;
    3) ./mount-btrfs.sh; read -p "Press Enter";;
    4) ./rebuild-host.sh; read -p "Press Enter";;
    5) ./shell.sh; read -p "Press Enter";;
    6) ./diagnostics.sh; read -p "Press Enter";;
    7) hermes; read -p "Press Enter";;
    8) journalctl -e; read -p "Press Enter";;
    0) systemctl reboot;;
  esac
done
```

### 4. Diagnostic Tools

#### `hardware-scan.sh` - Comprehensive hardware detection

```bash
#!/usr/bin/env bash
echo "=== Hardware Inventory ==="
echo "CPU:"
lscpu | grep -E "Model name|CPU\(s\)|Thread"
echo ""
echo "Memory:"
free -h
echo ""
echo "Storage:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL
echo ""
echo "NVMe devices:"
nvme list 2>/dev/null || echo "No nvme command"
echo ""
echo "Block devices:"
blkid
echo ""
echo "Network interfaces:"
ip -br addr
echo ""
echo "PCI devices:"
lspci | grep -E "VGA|Network|NVMe|Storage"
```

#### `boot-diagnostics.sh` - Boot troubleshooting

```bash
#!/usr/bin/env bash
echo "=== Boot Diagnostics ==="

echo "Checking bootloader..."
if [ -d /sys/firmware/efi ]; then
  echo "UEFI mode detected"
  efibootmgr -v
else
  echo "Legacy BIOS mode"
  cat /proc/cmdline
fi

echo ""
echo "Checking fstab entries..."
if [ -f /etc/fstab ]; then
  cat /etc/fstab
else
  echo "No /etc/fstab found (or not in chroot)"
fi

echo ""
echo "Checking btrfs subvolumes..."
for mount in $(mount | grep btrfs | awk '{print $3}'); do
  echo "Subvolumes under $mount:"
  btrfs subvolume list "$mount" 2>/dev/null || echo "  (cannot list)"
done

echo ""
echo "Default subvolume:"
for dev in $(lsblk -no NAME,MOUNTPOINT -l | grep btrfs | awk '{print $1}' | sort -u); do
  echo "/dev/$dev:"
  btrfs subvolume get-default "/dev/$dev" 2>/dev/null || echo "  (cannot get default)"
done
```

### 5. Emergency Boot Fixes

#### `fix-btrfs-default.sh` - Reset btrfs default subvolume

```bash
#!/usr/bin/env bash
# Usage: fix-btrfs-default.sh <device> <subvol_id>
# Resets the default subvolume for btrfs filesystem

DEVICE="$1"
SUBVOL_ID="${2:-256}"  # 256 is usually @ (root)

if [ -z "$DEVICE" ]; then
  echo "Usage: $0 <device> [subvol_id]"
  echo "Example: $0 /dev/nvme1n1p2 256"
  exit 1
fi

echo "Current default subvolume:"
btrfs subvolume get-default "$DEVICE"

echo ""
echo "Setting default subvolume to $SUBVOL_ID..."
sudo btrfs subvolume set-default "$SUBVOL_ID" "$DEVICE"

echo ""
echo "New default subvolume:"
btrfs subvolume get-default "$DEVICE"
```

#### `regenerate-fstab.sh` - Fix corrupted fstab

```bash
#!/usr/bin/env bash
# Regenerates /etc/fstab from NixOS configuration
# Usage: regenerate-fstab.sh <root_mount>

MOUNT="$1"

if [ -z "$MOUNT" ]; then
  echo "Usage: $0 <root_mount>"
  exit 1
fi

echo "Generating new fstab in $MOUNT/etc/fstab..."
# This will be overwritten by nixos-rebuild, but gets us bootable
cat > "$MOUNT/etc/fstab" <<EOF
# Generated by USB rescue - will be replaced by NixOS
$(genfstab -U "$MOUNT" | grep -v 'swap')
EOF

echo "Contents:"
cat "$MOUNT/etc/fstab"
```

## Integration with Cluster Config

### Module: `modules/profiles/usb-rescue.nix`

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Rescue-specific profile
  environment.systemPackages = with pkgs; [
    btrfs-progs cryptsetup mdadm lvm2
    nfs-utils openssh tmux htop iotop
  ];

  # Hermes pre-configured with cluster endpoints
  services.hermes-agent = {
    enable = true;
    config = {
      providers.gateway.base_url = "http://10.15.67.242:8080/v1";
      default_provider = "gateway";
    };
  };

  # Rescue scripts in /etc/nixos/scripts/rescue/
  environment.etc."rescue-menu".source = pkgs.writeShellScriptBin "rescue-menu" ''
    # Interactive TUI menu
  '';

  # Auto-start rescue menu on login
  programs.bash.loginShellInit = ''
    if [ "$TERM" != "linux" ]; then
      rescue-menu
    fi
  '';
}
```

## Recovery Scenarios

### Scenario 1: Host won't boot (emergency mode)

1. Boot from USB rescue
2. Run `rescue-menu`
3. Select "Detect hosts" → confirm network
4. Select "Mount NFS" → get config
5. Select "Rebuild host" → choose target
6. Reboot from fixed disk

### Scenario 2: Btrfs corruption

1. Boot from USB rescue
2. Run `btrfs check /dev/nvmeXnY` (read-only first)
3. If repair needed: `btrfs check --repair /dev/nvmeXnY`
4. Reset default subvolume: `fix-btrfs-default.sh /dev/nvmeXnYp2 256`
5. Rebuild system

### Scenario 3: Lost root password

1. Boot from USB rescue
2. Mount root: `mount -o subvol=@ /dev/nvmeXnYp2 /mnt/root`
3. Enter chroot: `nixos-enter /mnt/root`
4. Reset password: `passwd root`
5. Exit and reboot

### Scenario 4: Network-only recovery (remote hands)

1. Remote operator boots USB rescue
2. Enables SSH: `systemctl start sshd`
3. You SSH in and guide via Hermes
4. Run diagnostics, fix config, rebuild

## Implementation Checklist

- [ ] Add `modules/profiles/usb-rescue.nix` with all recovery tools
- [ ] Create `/etc/nixos/scripts/rescue/` directory structure
- [ ] Implement `detect-hosts.sh` - network scanner
- [ ] Implement `mount-cluster.sh` - auto-mount script
- [ ] Implement `rebuild-host.sh` - automated rebuild
- [ ] Implement `rescue-menu.sh` - TUI interface
- [ ] Implement `hardware-scan.sh` - diagnostics
- [ ] Implement `boot-diagnostics.sh` - boot troubleshooting
- [ ] Implement `fix-btrfs-default.sh` - btrfs repair
- [ ] Configure Hermes with cluster endpoints
- [ ] Test on all 4 hosts
- [ ] Document in AGENTS.md

## Future Enhancements

1. **Persistent USB state** - Keep recovery logs, known hosts
2. **Auto-discovery** - mDNS/Bonjour for zero-config network detection
3. **Remote recovery** - SSH server pre-configured, keys from Zephyr
4. **Rollback helper** - List and select from previous generations
5. **Backup integration** - Restic backup/restore from rescue
6. **Network boot** - PXE/iPXE boot for diskless recovery
7. **ZFS tools** - If cluster adopts ZFS for storage
8. **Container recovery** - kubectl/tools for K8s troubleshooting

## References

- [NixOS Discourse - Persistent Btrfs Subvolume Mounting](https://discourse.nixos.org/t/persistent-btrfs-subvolume-mounting/30021)
- [NixOS Wiki - Btrfs](https://wiki.nixos.org/wiki/Btrfs)
- [NixOS Discourse - NixOS rebuild failing while chrooted](https://discourse.nixos.org/t/nixos-rebuild-failing-while-chrooted/40176)
- [Restoring Broken Filesystem with Btrfs, NixOS and Restic](https://tbx.at/posts/filesystem-restore/)
