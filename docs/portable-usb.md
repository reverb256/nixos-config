# Portable USB Stick — NixOS Rescue / Pinch / Remote

> **Status:** Active reference (shipped in `ad11d129`, 2026-08-09)
> **Last Verified:** 2026-08-09
> **Owner:** j_kro

A single bootable NixOS USB stick that:
1. **Rescues** any cluster host without formatting — embeds the validated
   `scripts/rescue/*` toolkit (closures into the target's real `@nix`, boot-entry
   repair via `nixos-enter`).
2. **Installs / fresh-provisions** targets.
3. **Works standalone** as a Niri desktop with dev tooling in a pinch, or over SSH.
4. **Drives every GPU** on the machine it's plugged into (NVIDIA + AMD/ROCm + Mesa)
   via `hardware.gpu-compute.nix` modalias autoload.

Persistent by design: the image is a GPT disk with an ESP + an ext4 root that carries
its own Nix store, so rescue closures survive reboots and the stick is self-contained
(no NFS needed).

> **Source of truth:** `modules/profiles/portable-usb.nix` (wired as
> `nixosConfigurations.portable` + `packages.portable-image` in `flake.nix`).
> NOT part of the cluster hive — it deliberately excludes sops-nix / peakminer / mcp /
> caddy.

---

## Build

Built on the **nexus** builder (never zephyr-local — OOM guard). The flake reads the
local tree; the build is offloaded.

```bash
# From /etc/nixos on any node with the flake checked out:
nix build .#portable-image --no-link --print-out-paths
# or explicitly offload to nexus:
nix build --builders 'ssh-ng://j_kro@nexus' .#portable-image --no-link --print-out-paths
```

Output: a raw disk image at `/nix/store/<hash>-portable/portable.raw`
(~9.4 GB; fits a 32 GB stick with ~19 GB free for persistence).

The image layout (systemd-repart):
- `esp` (vfat, 100 MB) — systemd-boot at the **removable fallback**
  `EFI/BOOT/BOOTX64.EFI` + the UKI at `EFI/Linux/nixos.efi`. `canTouchEfiVariables=false`
  so the stick never mutates the host's NVRAM.
- `root` (ext4, label `nixos`) — carries `config.system.build.toplevel` inline
  (self-contained store).

---

## Flash to a USB stick

```bash
# Identify the stick (DO NOT guess — this is destructive):
ls -la /dev/disk/by-id/ | grep -i usb

# Flash (wipes the stick):
sudo dd if=/nix/store/<hash>-portable/portable.raw \
  of=/dev/disk/by-id/usb-<vendor>-<serial>-0:0 \
  bs=4M status=progress oflag=sync

# After flashing, the stick boots on any UEFI host. Persists across reboots.
```

On a 32 GB stick the 9.4 GB image leaves ~19 GB of free space on the root partition
for logs, generated configs, and rescue artifacts.

---

## Boot

- Plug into the target host, select the USB from the firmware boot menu (UEFI).
- The stick boots to `nixos login:` on `ttyS0` (serial) **and** to the SDDM login
  (graphical, autologin as `j_kro`).
- `j_kro` and `root` accept SSH via the public keys from `mesh-keys.nix`
  (pubkey-only; password auth disabled).

Booted verified in QEMU (KVM) reaching a login prompt; initrd carries storage drivers
for virtio / USB / NVMe / AHCI so it sees its root disk on any hardware.

---

## Rescue workflow (embedded toolkit)

The `scripts/rescue/*` toolkit is embedded on the stick at `/etc/rescue/` (via
`environment.etc`). Phases are independently rerunnable and **never format disks,
run disko, delete generations, run GC, or accept changed SSH keys**.

```bash
# From a shell on the booted stick:
rescue-cli.sh <phase> [options]

Phases:
  discover       Read-only hardware/filesystem discovery
  mount          Mount an existing target (dry-run unless --apply --confirm-target)
  diagnose       Read-only installed-target diagnosis
  build          Build/verify a host toplevel on the builder
  transfer       Import a verified closure into a mounted target store
  prepare-boot   Set target profile and generate boot entry from nixos-enter
  verify         Verify pre-reboot target or post-reboot running host
  unmount        Ordered normal unmount
```

Full guide: `docs/runbooks/nixos-usb-rescue.md` and the embedded `RESCUE-GUIDE.md`.
Key rule from that guide: when you SSH to a cluster IP while booted from the stick,
you land on the **USB rescue** (`/`), and the broken host's filesystem is mounted at
`/mnt/<host>-root/`. Every fix targets the mount point, not `/`.

### Common scenarios

**Host won't boot (emergency mode):**
1. Boot the stick → `rescue-cli.sh discover`
2. `rescue-cli.sh mount --apply --confirm-target <dev>`
3. `rescue-cli.sh diagnose`
4. `rescue-cli.sh build` then `transfer` then `prepare-boot`
5. `rescue-cli.sh verify` → reboot from the fixed disk

**Btrfs default-subvolume lost:** `fix-btrfs-default.sh <device> <subvol_id>`

**Lost root password:** mount the target root, `nixos-enter`, `passwd root`.

**Remote hands:** enable SSH on the stick, operator boots it, you SSH in (your
`mesh-keys.nix` key is authorized) and drive `rescue-cli.sh`.

---

## GPU support

`hardware.gpu-compute.nix` is imported — NVIDIA (CUDA), AMD (ROCm), and Mesa/Vulkan
load via modalias and are inert on absent hardware. On a box with all 7 cluster GPUs
the stick can drive whichever are present. CUDA/ROCm user libraries are enabled via the
module's `cuda.enable` / `rocm.enable` flags if the 32 GB budget allows; default is
drivers-only (modalias) to keep the closure small.

---

## Known limitations / next steps

- No `just portable-build` / `just portable-flash` recipe yet (build is `nix build
  .#portable-image`; flash is the `dd` above).
- Tailscale mesh on the stick is not wired; SSH uses `mesh-keys.nix` only.
- QEMU smoke test is ad-hoc; formalize as a CI/`just` check (see #427).
- The original 2026-04-28 design draft (`docs/archive/legacy/ARCHIVE/usb-rescue-design.md`)
  described an NFS-dependent `usb-rescue.nix` profile with hardcoded cluster IPs and a
  Hermes TUI menu — that design was superseded by this systemd-repart image. This
  document is the current reference.

---

## Provenance

| Item | Value |
|------|-------|
| Decision map | #421 |
| Artifact research | #422 (systemd-repart chosen) |
| GPU research | #423 (gpu-compute modalias) |
| Prototype | #424 (this, `ad11d129`) |
| Contract | #425 (A-persistent / minimal / keys / systemd-boot fallback) |
| Rot inventory | #426 |
| VM-boot test | #427 |
