# NixOS Cluster USB-Rescue Runbook

**Status:** Canonical operator runbook  
**Scope:** Zephyr, Nexus, Forge, Sentry, and future hosts with an explicit profile  
**Last verified:** 2026-08-12
**Owner:** Cluster operations

This runbook repairs an existing NixOS installation from a NixOS USB/rescue
system without reinstalling or formatting the target. It builds a desired
NixOS closure on the configured builder, transfers the complete closure to the
installed target store, prepares a boot entry, and verifies the next boot.

## Safety contract

The rescue toolkit is deliberately conservative:

- Never run `nixos-anywhere`, `disko`, `mkfs`, `parted`, `sfdisk`, or `dd` from
  this recovery workflow.
- Never delete a NixOS generation, run garbage collection, or reset a Btrfs
  default subvolume as a first response.
- Never trust `/dev/nvme*`, `/dev/sd*`, a root subvolume name, or an EFI device
  without discovery and operator confirmation.
- Never accept a changed rescue SSH host key automatically. Use a separate,
  verified known-hosts file.
- Never confuse the USB store `/nix/store` with the installed target store
  mounted below `/mnt/<host>-root/nix/store`.
- Never mutate the target without both `--apply` and `--confirm-target`.
- Never run the boot activation script outside `nixos-enter --root <target>`.
- Never treat a build-start message as success. Require exit status zero, an
  existing toplevel, verified closure metadata, and a verified target import.
- Keep the last known-good generation until the repaired host completes a
  normal boot and post-boot verification.

If a command proposes a device or target that does not match discovery, stop.
Do not “try the other disk.” Re-run discovery and explicitly override the
profile after confirming the console state.

## Toolkit

All commands are in `scripts/rescue/`; invoke them from the repository root or
copy the complete directory to the rescue environment:

```text
rescue-cli.sh                 phase dispatcher
rescue-common.sh              shared safety/profile helpers
rescue-discover.sh            read-only device and filesystem inventory
rescue-mount-target.sh        explicit target mounts; dry-run by default
rescue-diagnose.sh            read-only journal/profile/boot diagnosis
rescue-build-closure.sh       builder-side toplevel build and verification
rescue-transfer-closure.sh    closure import into installed target store
rescue-prepare-boot.sh        profile update + boot entry generation
rescue-verify.sh              pre- and post-reboot verification
rescue-unmount-target.sh      ordered normal unmount
```

The toolkit supports four current profiles:

| Host | Root profile label | Root subvolume | Nix subvolume | Persistent | EFI profile label |
|---|---|---|---|---|---|
| Zephyr | `disk-samsung-root` | `@` | `disk-xpg-nix:@nix` | none | `disk-samsung-boot` |
| Nexus | `disk-nvme1n1-root` | `@root` | `@nix` | `@persistent` | `disk-nvme1n1-ESP` |
| Forge | `disk-sdb-root` | `@root` | `@nix` | `@persistent` | `disk-sdb-boot` |
| Sentry | `disk-sdb-root` | `@root` | `@nix` | `@persistent` | `disk-sdb-boot` |

The profile is a starting point, not proof. `rescue-discover.sh` is mandatory
before mounting. The profile mounts the filesystems required to enter and boot
the system; optional data filesystems may remain unmounted unless the target's
service role requires them. If discovery differs, stop and use explicit
`rescue-mount-target.sh` overrides rather than editing the profile ad hoc.

## Phase 0: establish operator context

Record:

- host and IP;
- console-confirmed rescue mode;
- rescue SSH fingerprint and isolated known-hosts path;
- rescue session start time;
- source Git revision to build;
- known-good generation to preserve;
- target root mount path;
- closure path and SHA-256/checkpoint files.

Use a durable state directory when possible:

```bash
export RESCUE_STATE_DIR=/var/tmp/nixos-rescue-$(date -u +%Y%m%dT%H%M%SZ)
sudo mkdir -p "$RESCUE_STATE_DIR"
sudo chmod 700 "$RESCUE_STATE_DIR"
```

## Phase 1: discover, do not mutate

At the rescue console:

```bash
sudo scripts/rescue/rescue-cli.sh discover --host HOST
```

Or directly:

```bash
sudo scripts/rescue/rescue-discover.sh --host HOST
```

Confirm all of the following from `lsblk`, `blkid`, `findmnt`, and Btrfs
subvolume output:

- boot mode: UEFI or BIOS;
- target root filesystem and expected subvolume;
- target Nix filesystem and expected subvolume;
- persistent filesystem, if present;
- EFI filesystem;
- no target partition is already mounted at an unexpected location;
- the target is the intended physical host.

## Phase 2: verify rescue SSH identity

The rescue image normally has a temporary host key. Verify it through the
local console, then use an isolated file:

```bash
RESCUE_KNOWN_HOSTS="$HOME/.ssh/known_hosts-HOST-rescue"
touch "$RESCUE_KNOWN_HOSTS"
chmod 600 "$RESCUE_KNOWN_HOSTS"
ssh-keyscan -H HOST_IP | tee /tmp/HOST-rescue.keys
ssh-keygen -lf /tmp/HOST-rescue.keys
# Compare with the console-confirmed fingerprint before this step:
cat /tmp/HOST-rescue.keys >> "$RESCUE_KNOWN_HOSTS"
```

The transfer and boot phases require this file and strict checking:

```bash
--known-hosts "$RESCUE_KNOWN_HOSTS"
```

Do not use `StrictHostKeyChecking=no` or `/dev/null` for rescue recovery.

## Phase 3: mount the installed target

First dry-run the profile:

```bash
sudo scripts/rescue/rescue-cli.sh mount \
  --host HOST \
  --target-root /mnt/HOST-root
```

The dry-run must show the correct labels, subvolumes, and target path. Then
apply only after reviewing it:

```bash
sudo scripts/rescue/rescue-cli.sh mount \
  --host HOST \
  --target-root /mnt/HOST-root \
  --apply \
  --confirm-target
```

For a layout not represented by a profile, use explicit overrides for every
ambiguous filesystem:

```bash
sudo scripts/rescue/rescue-mount-target.sh \
  --host HOST \
  --root-device /dev/disk/by-partlabel/EXACT-ROOT \
  --root-subvol @root \
  --nix-device /dev/disk/by-partlabel/EXACT-NIX \
  --nix-subvol @nix \
  --persistent-device /dev/disk/by-partlabel/EXACT-ROOT \
  --persistent-subvol @persistent \
  --efi-device /dev/disk/by-partlabel/EXACT-EFI \
  --apply --confirm-target
```

Verify target mounts:

```bash
findmnt -R /mnt/HOST-root
findmnt /mnt/HOST-root/nix
findmnt /mnt/HOST-root/boot
find /mnt/HOST-root/nix/store -maxdepth 1 -type d | head
```

## Phase 4: diagnose the installed system

```bash
sudo scripts/rescue/rescue-cli.sh diagnose \
  --host HOST \
  --target-root /mnt/HOST-root
```

Review:

```bash
cat /mnt/HOST-root/etc/fstab
readlink -f /mnt/HOST-root/nix/var/nix/profiles/system
sudo nix-env --store "local?root=/mnt/HOST-root" \
  -p /nix/var/nix/profiles/system \
  --list-generations
find /mnt/HOST-root/boot/loader/entries -maxdepth 1 -type f -print
sudo journalctl --root=/mnt/HOST-root --list-boots
```

Preserve the known-good generation. A generation with missing store paths must
not be selected merely because it has the highest number.

## Phase 5: build on the designated builder

Build on the cluster’s designated builder/dispatcher, currently Nexus. Do not
build a system closure inside USB rescue. On the builder, from the canonical
source checkout:

```bash
scripts/rescue/rescue-cli.sh build --host HOST
```

The build tool:

- evaluates the host first;
- uses explicit temporary substituters;
- disables accidental local remote-builder recursion;
- captures a full log and exact exit status;
- records the toplevel path, path metadata, closure list, and verification.

Use environment overrides for a different builder/cache policy:

```bash
RESCUE_SUBSTITUTERS='http://10.1.1.110:50000 https://cache.nixos.org' \
RESCUE_MAX_JOBS=12 RESCUE_CORES=12 \
scripts/rescue/rescue-build-closure.sh --host HOST
```

A successful build must produce a path matching:

```text
/nix/store/<hash>-nixos-system-HOST-...
```

Do not proceed if only a `.drv` exists or if the command was interrupted.

## Phase 6: transfer and verify the closure

Use the strict rescue known-hosts file and the exact verified toplevel:

```bash
sudo scripts/rescue/rescue-cli.sh transfer \
  --host HOST \
  --closure /nix/store/<hash>-nixos-system-HOST-... \
  --target-root /mnt/HOST-root \
  --known-hosts "$RESCUE_KNOWN_HOSTS" \
  --apply --confirm-target
```

The transfer exports the complete `nix-store -qR` closure and imports it into
the target's alternate local store:

```text
local?root=/mnt/HOST-root
```

The target store still uses `/nix/store` and `/nix/var/...` paths internally;
the `local?root` URI is what prevents the rescue store and target store from
being confused.

It does not import into the rescue `/nix` store. It verifies the toplevel in
the target store before returning success.

## Phase 7: prepare profile and boot entry

This is the first phase that changes the target system profile and boot files:

```bash
sudo scripts/rescue/rescue-cli.sh prepare-boot \
  --host HOST \
  --closure /nix/store/<hash>-nixos-system-HOST-... \
  --target-root /mnt/HOST-root \
  --known-hosts "$RESCUE_KNOWN_HOSTS" \
  --apply --confirm-target
```

The phase:

1. records the old profile;
2. confirms the new toplevel exists in the installed target store;
3. sets the installed system profile;
4. invokes `switch-to-configuration boot` from `nixos-enter`;
5. confirms the new profile and boot artifacts.

`switch` is not used from the rescue environment because it attempts live
service management against the rescue runtime. `boot` is used to prepare the
next installed boot. After the host is running normally, ordinary `switch`
semantics apply.

## Phase 8: pre-reboot gate

```bash
sudo scripts/rescue/rescue-cli.sh verify \
  --host HOST \
  --mode pre \
  --closure /nix/store/<hash>-nixos-system-HOST-... \
  --target-root /mnt/HOST-root
```

Do not reboot unless:

- root, Nix, and EFI are mounted at the target path;
- the target profile resolves to the requested toplevel;
- the complete toplevel exists in the target store;
- boot entries exist;
- the known-good generation remains present;
- `/etc/fstab` is a NixOS-managed link/configuration, not an ISO artifact.

## Phase 9: unmount and reboot

```bash
sudo scripts/rescue/rescue-cli.sh unmount \
  --host HOST \
  --target-root /mnt/HOST-root
```

Review the planned child-first unmount. Then:

```bash
sudo scripts/rescue/rescue-cli.sh unmount \
  --host HOST \
  --target-root /mnt/HOST-root \
  --apply --confirm-target
sync
sudo reboot
```

No lazy or forced unmount is used by the toolkit. If mounts remain, inspect
`findmnt -R /mnt/HOST-root` and resolve the child mount explicitly.

## Phase 10: post-reboot verification

Once the installed host is back, verify its normal SSH identity—not the rescue
known-hosts file—and run:

```bash
scripts/rescue/rescue-cli.sh verify \
  --host HOST \
  --mode post \
  --known-hosts "$HOME/.ssh/known_hosts"
```

Also verify:

```bash
hostname -s
readlink -f /run/booted-system
readlink -f /nix/var/nix/profiles/system
nixos-rebuild list-generations
systemctl is-system-running
systemctl --failed --no-legend
findmnt /
findmnt /nix
```

Then check host-role services. For example, Kubernetes hosts should have the
expected k3s state; storage hosts should have their storage mounts; monitoring
hosts should have node exporter/monitoring services; desktop hosts should not
be evaluated by a headless rescue procedure as if they were servers.

## Compatibility files and legacy procedures

`RESCUE-GUIDE.md` and `RESCUE-AGENT.md` are compatibility pointers only. The
older scripts under `scripts/rescue/` that guess block devices are not part of
this workflow. Use `rescue-cli.sh`; archived procedures are historical and
must not be copied into an active incident.

## Rollback

If the new system fails to boot:

1. Select the known-good boot entry from the bootloader.
2. If necessary, return to rescue and run `rescue-diagnose.sh`.
3. Point the installed profile to a verified existing known-good generation
   link or closure.
4. Re-run `rescue-prepare-boot.sh` against that known-good closure.
5. Do not delete the failed generation until the incident is closed.

Never infer validity from generation number alone; verify that every referenced
store path exists in the installed target store.

## Official references

- [NixOS Wiki: Change root](https://wiki.nixos.org/wiki/Change_root)
- [NixOS Wiki: Btrfs](https://wiki.nixos.org/wiki/Btrfs)
- [NixOS Wiki: nixos-rebuild](https://wiki.nixos.org/wiki/Nixos-rebuild)
- [Nix manual: Remote builds](https://nix.dev/manual/nix/2.18/advanced-topics/distributed-builds)
- [Nix manual: nix copy](https://nix.dev/manual/nix/2.18/command-ref/new-cli/nix3-copy)
- [Nix manual: nix-store --export](https://nix.dev/manual/nix/2.26/command-ref/nix-store/export)
