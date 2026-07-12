# krash3-vm — Resizable BAR (ReBAR) Readiness

> Status: PREP ONLY. No XML/config change possible or needed. ReBAR is
> transparent passthrough in libvirt/QEMU — the only lever is the HOST BIOS.
> Author: Hermes | Date: 2026-07-11

## What ReBAR does
Lets the guest OS map the GPU's FULL VRAM as one contiguous BAR instead of the
legacy 256 MB window. For an 8 GB card this removes CPU windowing overhead on
large asset streams → smoother/more stable frame times in modern titles.

## Verified evidence (read-only, this session)
- GPU: 0000:08:00.0 (RTX 4060, 10de:2882), vfio-pci bound, passed to VM.
- BAR1 (VRAM aperture): 0x7c00000000–0x7dffffffff = 8 GiB, 64-bit prefetchable.
  For an 8 GB card, 8 GiB IS the maximum ReBAR size → physical aperture optimal.
- /sys/bus/pci/devices/0000:08:00.0/resource1_resize EXISTS → kernel sees the
  Resizable BAR capability. (File is read-only while device is in use by VM.)
- libvirt schemas on host (12.2.0 and 12.4.0): `hostdevDriver` allows only
  `<driver name='vfio'/>` (+model/iommufd) and `<empty/>`. NO `xresizableBar` /
  `resizableBar` attribute exists. Adding one FAILS schema validation on deploy.

## CONCLUSION
No libvirt XML change enables ReBAR. It is passed through automatically when the
host firmware exposes a resizable BAR. The GPU hostdev stays as-is
(`<driver name='vfio'/>` + rom) — already correct.

## Maintenance-window action (the REAL lever)
1. HOST BIOS (krash3 motherboard firmware): ensure BOTH are ENABLED:
     - "Above 4G Decoding" (aka "Above 4G MMIO")
     - "Resizable BAR" / "ReBAR Support" (on some boards: "Smart Access Memory"
       is the AMD term; on Intel boards it's "ReBAR"; on this board check both)
   If either is Off, the guest sees a fixed/legacy BAR → ReBAR = No in Windows.
2. Reboot host (this also activates the already-committed pcie_aspm=off +
   kvm_amd.msr_filter=0 + isolcpus=1-8,13-20).
3. POST-WINDOW VERIFY (inside Windows, non-disruptive):
     - GPU-Z → "Resizable BAR: Enabled", OR
     - NVIDIA Control Panel → System Information → "Resizable BAR: Yes"
   If it says NO after the BIOS change + reboot, re-check the BIOS setting
   (Above 4G Decoding is the usual missing piece).

## Rollback
None needed — no config was changed. If ReBAR proves unstable, disable it in
BIOS only.
