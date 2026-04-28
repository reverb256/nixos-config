#!/usr/bin/env bash
# hardware-scan.sh - Comprehensive hardware detection
# Usage: hardware-scan.sh

echo "=== Hardware Inventory ==="
echo ""

echo "==> CPU"
lscpu | grep -E "Model name|CPU\(s\)|Thread|Core|Socket"
echo ""

echo "==> Memory"
free -h
echo ""

echo "==> Storage (lsblk)"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,TRAN
echo ""

echo "==> Block devices (blkid)"
blkid | sort
echo ""

echo "==> NVMe devices"
if command -v nvme &>/dev/null; then
  nvme list 2>/dev/null || echo "No NVMe devices or nvme command failed"
else
  echo "nvme command not available"
fi
echo ""

echo "==> Network interfaces"
ip -br addr
echo ""

echo "==> PCI devices (relevant)"
lspci | grep -E "VGA|3D|Network|Ethernet|NVMe|Storage|USB"
echo ""

echo "==> USB controllers"
lsusb | head -10
echo ""

echo "==> Kernel"
uname -a
echo ""

echo "==> Kernel parameters"
cat /proc/cmdline
echo ""

echo "==> UEFI vs BIOS"
if [ -d /sys/firmware/efi ]; then
  echo "Boot mode: UEFI"
  if command -v efibootmgr &>/dev/null; then
    echo "EFI boot entries:"
    efibootmgr | head -20
  fi
else
  echo "Boot mode: Legacy BIOS"
fi
echo ""

echo "==> Temperature sensors (if available)"
if command -v sensors &>/dev/null; then
  sensors 2>/dev/null || echo "No sensors detected"
else
  echo "lm-sensors not available"
fi
