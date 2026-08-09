# Zephyr Game Pass VM: Incus Migration

## Current state

Zephyr declares two parallel, dormant Windows VM backends:

| Backend | Name | Role | Storage |
|---|---|---|---|
| libvirt/QEMU | `gamepass-win11` | rollback backend | `/var/lib/libvirt/images/gamepass-win11.qcow2` |
| Incus/QEMU | `gamepass-win11-incus` | migration target | Incus pool `gamepass` |

Both use the RTX 3060 Ti functions `0000:24:00.0` and `0000:24:00.1` when
started. They must never run at the same time. Their disks are intentionally
separate; sharing one writable VM disk would risk filesystem corruption.

The current qcow2 is an empty 200 GiB disk and `win11.iso` is the installer.
No Windows installation is migrated automatically.

## Declarative deployment

The NixOS switch enables Incus, creates the Incus access groups, pre-seeds the
`incusbr-gamepass` network, and declares the `gamepass` storage pool/profile.
It does **not** initialize an Incus VM, import media, start a guest, or bind the
GPU. Those are explicit operator actions.

The state directories are preserved across generation changes:

- `/var/lib/incus`
- `/var/lib/incus-gamepass`
- `/var/lib/libvirt`

## One-time Incus VM creation

After the Zephyr configuration containing Incus has been deployed, confirm the
host is idle and the libvirt VM is off:

```bash
incus-gamepass-vm status
virsh -c qemu:///system domstate gamepass-win11
```

Create the stopped Incus VM and import the existing installer media:

```bash
incus-gamepass-vm create
incus config show gamepass-win11-incus --expanded
```

The command creates a 200 GiB Incus-managed root volume, imports the Windows
and VirtIO ISOs into the `gamepass` pool, attaches both ISO volumes, attaches
the Incus agent CD, and leaves the VM stopped.

## Installation

Start only the Incus backend through the ownership guard:

```bash
incus-gamepass-vm start
incus console gamepass-win11-incus --type=vga
```

Install Windows from the attached `win11-installer` media. During setup, load
VirtIO storage/network drivers from the attached `virtio-win` media if Windows
does not see the root disk. Install the Incus Windows agent from its attached
agent CD after Windows is running.

The initial validation should use the Incus console. GPU/Looking Glass wiring
is validated only after Windows, VirtIO, and the Incus agent are installed.

## Looking Glass

The host-side KVMFR path is declared for both backends. Incus uses its supported
`raw.qemu` escape hatch to add the ivshmem device, while the NixOS module grants
`incus.service` access to `/dev/kvmfr0` through the `kvm` group and a narrow
`DeviceAllow` rule.

Before starting the Incus VM:

```bash
incus-gamepass-vm check-looking-glass
```

After Windows has the Looking Glass host installed and the Incus VM is running:

```bash
looking-glass-gamepass
```

The launcher expands to `looking-glass-client -f /dev/kvmfr0 -F -S`. If it does
not connect, inspect the Incus/QEMU journal before changing GPU bindings:

```bash
journalctl -u incus.service -b --no-pager | tail -100
incus info gamepass-win11-incus --show-log
```

Incus has no first-class Looking Glass device type, so this uses the
Incus `raw.qemu` escape hatch and is intentionally runtime-validated against the
pinned Incus/QEMU build rather than treated as a portable Incus abstraction.
The pre-start check proves host KVMFR availability; it cannot prove the
Incus-launched QEMU child can open the device until the VM is actually started.

## Rollback backend

Stop Incus before starting libvirt:

```bash
incus-gamepass-vm stop
incus-gamepass-vm start-libvirt
```

Return to Incus with:

```bash
incus-gamepass-vm stop-libvirt
incus-gamepass-vm start
```

The systemd units `gamepass-incus-vm.service` and
`gamepass-libvirt-vm.service` conflict with each other, but always use
`incus-gamepass-vm` rather than direct `incus start` or `virsh start` commands.
A direct command can bypass the service-level ownership guard. Stopping a VM
returns the PCI functions to the host drivers; it does not automatically restart
host mining/LLM services that were stopped for the handoff.

## Important limitations

- A NixOS activation does not create or start the VM.
- Incus and libvirt cannot safely share the same writable disk.
- The GPU cannot be assigned to both backends simultaneously.
- The existing libvirt XML has its own Looking Glass path. Incus declares the
  equivalent raw QEMU shared-memory arguments, but Incus-specific `/dev/kvmfr0`
  permissions and Looking Glass behavior require follow-up validation on the
  actual VM after Windows is installed.
- Do not add `vfio-pci.ids` to the kernel command line. Dynamic ownership is
  required so the host can use the card while both VMs are stopped.
