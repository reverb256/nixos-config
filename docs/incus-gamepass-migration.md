# Zephyr Game Pass VM: Incus Migration

## Last verified

2026-08-09 — source and live preseed audit. The Incus network/profile are
present, no Incus VM has been created, and the libvirt rollback VM is stopped.
Re-verify live state before every provisioning or backend switch.

## Design and safety contract

Zephyr declares two parallel, dormant Windows VM backends:

| Backend | Name | Role | Storage |
|---|---|---|---|
| libvirt/QEMU | `gamepass-win11` | rollback backend | `/var/lib/libvirt/images/gamepass-win11.qcow2` |
| Incus/QEMU | `gamepass-win11-incus` | migration target | Incus pool `gamepass` |

Both use the RTX 3060 Ti functions `0000:24:00.0` and `0000:24:00.1` when
started. The handoff script verifies the NVIDIA vendor/device IDs before it
unbinds anything; it refuses unexpected PCI identities. The current topology
addresses are therefore fail-closed rather than silently retargeted if PCI
enumeration changes. Re-check the address and IDs after hardware or firmware
changes before attempting a start. The backends must never run at the same time, and their writable disks are intentionally separate.

The libvirt qcow2 is an empty 200 GiB disk and `win11.iso` is the installer.
No Windows installation is migrated automatically. The VirtIO ISO comes from
the pinned Nix package in the active system closure.

## Declarative deployment

The NixOS switch enables Incus, creates access groups, pre-seeds the
`incusbr-gp` network, and declares the `gamepass` storage pool/profile. It does
**not** initialize an Incus VM, import media, start a guest, bind the GPU, or
mutate Windows state.

Persistent state is preserved across generation changes:

- `/var/lib/incus`
- `/var/lib/incus-gamepass`
- `/var/lib/libvirt`

After deployment, run the read-only readiness checks first:

```bash
incus-gamepass-vm status
incus-gamepass-vm check-media
incus-gamepass-vm check-config
virsh -c qemu:///system domstate gamepass-win11
```

`check-media` prints sizes and SHA-256 hashes for the Windows and VirtIO ISOs.
`check-config` verifies the preseeded network/profile, KVMFR access, that an
existing Incus VM is stopped, and that the libvirt backend is not active. Before
creation it should say:

```text
No Incus VM exists yet; preseed/profile checks passed
```

## One-time stopped VM creation

Only run this after the checks pass and the libvirt VM is off:

```bash
incus-gamepass-vm create
incus config show gamepass-win11-incus --expanded
incus list
```

The helper uses `incus init --empty --vm`, which creates a stopped VM. It then
sets the instance-only `image.os` property, imports each ISO into the `gamepass`
pool using a content-addressed volume name, attaches the installer and VirtIO
media as USB optical devices, and adds the Incus agent CD.

Creation is transactional. If an import or device attachment fails, the helper
removes the VM and only the ISO volumes created by that attempt. ISO volume
names include a short SHA-256 prefix, so changed media cannot silently replace
an older volume; old content-addressed volumes are retained until explicitly
cleaned. It refuses to silently accept an existing partial VM; inspect it with
`check-config` and remove it deliberately only after confirming no data must be
retained.

## Installation workflow

Start only through the ownership guard:

```bash
incus-gamepass-vm start
incus console gamepass-win11-incus --type=vga
```

Install Windows from the installer media. If Setup cannot see the root disk,
load the VirtIO storage driver from the attached VirtIO CD; install the network
driver as well. After Windows boots, install the VirtIO guest tools and the
Incus Windows agent from the attached media.

Do not add a GPU or switch to Looking Glass until the basic VM boots, the
VirtIO drivers work, and the guest can shut down cleanly.

## Looking Glass and GPU handoff

The host-side KVMFR path is declared for both backends. Incus uses the pinned
`raw.qemu` ivshmem configuration and `incus.service` receives only the narrow
`/dev/kvmfr0` permission plus the `kvm` group.

Before a GPU-backed start:

```bash
incus-gamepass-vm check-looking-glass
incus-gamepass-vm check-config
incus-gamepass-vm start
looking-glass-gamepass
```

The launcher expands to `looking-glass-client -f /dev/kvmfr0 -F -S`. The
pre-start check proves host KVMFR access, not guest-side Looking Glass
functionality; guest validation still requires the Windows Looking Glass host.

The handoff uses `/run/lock/gamepass-vfio.lock`, checks that the other backend is
stopped, stops only the known 3060 Ti workloads, and verifies every PCI function
is bound to `vfio-pci` before recording ownership. It never uses boot-time
`vfio-pci.ids`, so the card remains available to the host while both guests are
dormant.

## Safe stop and rollback

The stop helpers wait for a confirmed stopped state. If shutdown does not
complete, they attempt a bounded force/destroy fallback and then fail closed;
the GPU release hook refuses to run while the guest remains active.

```bash
incus-gamepass-vm stop
incus-gamepass-vm start-libvirt
```

Return to Incus with:

```bash
incus-gamepass-vm stop-libvirt
incus-gamepass-vm start
```

The systemd units conflict with each other, but direct `incus start` and
`virsh start` can bypass the ownership guard. Use the helper for all normal
operations. Stopping a VM returns the PCI functions to host drivers; it does
not automatically restart mining/LLM services that were stopped for handoff.

## Recovery and cleanup

If creation fails, first inspect rather than retrying blindly:

```bash
incus-gamepass-vm status
incus-gamepass-vm check-config
incus profile show gamepass-win11
incus storage volume list gamepass
journalctl -u incus.service -b --no-pager | tail -100
```

A partial VM is not automatically deleted on a later run. After confirming it
is safe to discard, stop/delete it and remove only its content-addressed ISO
volumes; do not delete the whole `gamepass` pool or `/var/lib/incus`. Before
removing an old ISO volume, confirm it is not referenced by the VM:

```bash
incus config show gamepass-win11-incus --expanded
incus storage volume list gamepass
incus storage volume delete gamepass win11-installer-<old-hash>
incus storage volume delete gamepass virtio-win-<old-hash>
```

The placeholder `<old-hash>` is intentional: list and verify the exact name;
do not paste it literally.

If a backend stop fails, do not manually unbind PCI devices or restart host GPU
services. Confirm the guest state and inspect the service journal first. A
reboot may be required only if the kernel still holds a VFIO device after the
hypervisor is definitively stopped.

## Research references

- [Incus documentation](https://linuxcontainers.org/incus/docs/latest/)
- [Incus Windows VM discussion](https://discuss.linuxcontainers.org/t/how-to-run-a-windows-virtual-machine-on-incus-on-linux/18884)
- [Incus GPU passthrough discussion](https://discuss.linuxcontainers.org/t/gpu-passthrough-to-windows-11-vm/26993)
- [Looking Glass documentation](https://looking-glass.io/docs/)

Incus has no first-class Looking Glass device type in this design, so the
`raw.qemu` path remains Incus/QEMU-version-specific and must be validated on
the actual guest before treating it as production-ready.
