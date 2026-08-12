# Zephyr Game Pass VM: Incus-only runbook

## Last verified

2026-08-10 — the Zephyr configuration contains one Windows VM backend: Incus.
No VM is created or started by activation. Re-verify live state before every
provisioning operation.

## Design and safety contract

Incus exclusively owns the Game Pass VM and the RTX 3060 Ti functions
`0000:24:00.0` and `0000:24:00.1` while the VM is running. The RTX 3090 remains
host-owned for desktop, gaming, mining, and AI workloads and is never detached
by this configuration.

The handoff is dynamic and fail-closed. Incus declares the VM GPU with its
physical `gpu` device type; the companion HDMI-audio function is attached as a
raw `pci` device. The host guard is authoritative for preflight: it takes a
lock, stops only the known 3060 Ti workloads, rejects unexpected PCI drivers,
verifies the 3060 Ti vendor/device IDs and shared IOMMU group, verifies the
protected 3090 functions are present and not on `vfio-pci`, and records the
original drivers. Incus then owns the actual `vfio-pci` bind/restore lifecycle
using its `last_state.pci.driver` state. It does not automatically restart
workloads that were stopped for handoff. Host-level IOMMU modules, driver
availability, and workload quiescence remain NixOS responsibilities.

The writable VM state lives in the Incus storage pool `gamepass`, rooted at
`/var/lib/incus-gamepass`. The VirtIO ISO is generated from the pinned Nix
package in the active system closure. No external download or automatic
Windows-state migration occurs.

## Declarative deployment

The NixOS switch enables Incus, creates access groups, pre-seeds the
`incusbr-gp` network, and declares the `gamepass` storage pool/profile. It does
**not** initialize an Incus VM, import media, start a guest, bind the GPU, or
mutate Windows state.

Persistent Incus state is preserved across generation changes:

- `/var/lib/incus`
- `/var/lib/incus-gamepass`

The VM profile is dormant (`boot.autostart = false`). The systemd wrapper is
manual-only and requires the preseed service before a start. The preseed guard skips initialization only when the registered pool has the expected source. An unregistered storage directory or a non-empty expected source is a fail-closed reconciliation state: activation refuses to delete or overwrite it, and the operator must inventory it first.

## Readiness checks

Run these after deployment and before creating or starting the VM:

```bash
incus-gamepass-vm reconcile
incus-gamepass-vm status
incus storage list
incus storage get gamepass source
incus profile show gamepass-win11
incus list
```

`incus-gamepass-vm reconcile` must report either an expected registered pool or a safe empty-source initialization state. If it reports `BLOCKED`, stop and inventory the path; do not delete or overwrite it. The expected initial state is no `gamepass-win11-incus` instance. If an instance exists, confirm it is stopped and inspect its expanded configuration before changing anything.

## One-time stopped VM creation

Only run this after confirming the Incus pool/profile and installer media are
ready:

```bash
incus-gamepass-vm create
incus config show gamepass-win11-incus --expanded
incus list
```

The helper uses `incus init --empty --vm`, which creates a stopped VM. It sets
the instance OS metadata, imports the Windows and VirtIO media into the
`gamepass` pool, attaches the installer media and Incus agent CD, and leaves the
VM stopped for review. It does not start the guest or claim the GPU.

If creation fails, inspect the partial state before retrying. Do not delete the
whole pool or `/var/lib/incus`; remove only a deliberately confirmed partial
instance or unused media volume.

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

The VM must remain stopped until the basic guest boots, VirtIO drivers work,
and Windows can shut down cleanly. Do not troubleshoot GPU handoff and guest
installation at the same time.

## Looking Glass and GPU handoff

The host-side KVMFR path is declared for Incus. The profile uses Incus' physical `gpu` device for the 3060 Ti, a raw `pci`
device for HDMI audio, and the pinned `raw.qemu` ivshmem configuration.
The host guard remains the single host-side preflight owner; Incus remains the
single VFIO bind/restore owner. `incus.service` receives only the narrow
`/dev/kvmfr0` permission plus the `kvm` group.

Before a GPU-backed start:

```bash
incus-gamepass-vm check-looking-glass
incus-gamepass-vm status
incus-gamepass-vm start
looking-glass-gamepass
```

The launcher expands to `looking-glass-client -f /dev/kvmfr0 -F -S`. The
pre-start check proves host KVMFR access, not guest-side Looking Glass
functionality; guest validation still requires the Windows Looking Glass host.

The Incus service is the sole VM start path. Do not manually bind or unbind PCI
devices, and do not start an alternate hypervisor. Incus must report both 3060
Ti functions successfully passed through; if it fails, leave the guest stopped
and inspect the service journal. If Incus does not restore the recorded host
drivers after a failed start or stop, leave `/run/gamepass-vfio/*` intact and
treat it as a manual-recovery incident rather than attempting a second binder.

## Safe stop and recovery

```bash
incus-gamepass-vm stop
incus-gamepass-vm status
incus list
```

If a stop fails, do not manually unbind devices or restart host GPU services.
Confirm the guest state and inspect the journal first:

```bash
incus-gamepass-vm status
journalctl -u gamepass-incus-vm.service -u incus.service -b --no-pager | tail -100
incus config show gamepass-win11-incus --expanded
```

A reboot is a last resort and should be considered only after the guest is
definitively stopped and the kernel still holds a VFIO device. The RTX 3090
must remain available throughout recovery.

## Cleanup

Before removing any state, verify the exact instance and volume names:

```bash
incus list
incus config show gamepass-win11-incus --expanded
incus storage volume list gamepass
```

The placeholder `<volume-name>` below is intentional; list and verify the exact
name before using it:

```bash
incus storage volume delete gamepass <volume-name>
```

Never delete the entire `gamepass` pool or `/var/lib/incus` as a cleanup shortcut.

## Research references

- [Incus documentation](https://linuxcontainers.org/incus/docs/latest/)
- [Incus Windows VM discussion](https://discuss.linuxcontainers.org/t/how-to-run-a-windows-virtual-machine-on-incus-on-linux/18884)
- [Incus GPU passthrough discussion](https://discuss.linuxcontainers.org/t/gpu-passthrough-to-windows-11-vm/26993)
- [Looking Glass documentation](https://looking-glass.io/docs/)

Incus has no first-class Looking Glass device type in this design, so the
`raw.qemu` path remains Incus/QEMU-version-specific and must be validated on
the actual guest before treating it as production-ready.
