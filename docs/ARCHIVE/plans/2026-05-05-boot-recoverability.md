# Plan: Boot Recoverability for NixOS Cluster

**Date:** 2026-05-05
**Last Verified**: 2026-05-23 — ⚠️ STALE (18 days old). Verify before following.
**Status:** Draft
**Motivation:** Sentry was down 11+ hours because boot failures required physical USB access. All 4 nodes are headless servers — remote recovery is essential.

---

## Problem Statement

When a node fails to boot (bad fstab, mount failure, nftables crash, broken closure), the only recovery is driving to the machine with a USB stick. This has happened multiple times. We need three layers of defense:

1. **Initrd SSH** — remote shell before root filesystem mounts (highest priority)
2. **Recovery specialisation** — minimal boot entry that skips broken services
3. **Pre-rebuild btrfs snapshots** — instant rollback from boot menu

---

## Layer 1: Initrd SSH (Remote Shell Before Root Mount)

### What

SSH daemon running inside the initrd, accessible at the node's static IP before the root filesystem is mounted. If /home fails to mount, if NFS times out, if nftables crashes — you can SSH in and fix it.

### Why

The sentry incident: /home mount failed because NixOS added "bind" to btrfs subvol options. The node dropped to emergency mode. With initrd SSH, we could have SSH'd in at 10.1.1.140, manually mounted /home with correct options, fixed the config, and rebooted — all in 5 minutes instead of 11 hours.

### Design

**New module:** `modules/system/initrd-ssh-recovery.nix`

```nix
boot.initrd = {
  systemd.enable = true;  # already enabled on all hosts

  network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;  # avoid conflict with main sshd on port 22
      hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
      authorizedKeys = config.users.users.root.openssh.authorizedKeys.keys;
    };
  };
};
```

**Static IP via kernel params** (simplest, most reliable):
```
boot.kernelParams = [ "ip=10.1.1.140::10.1.1.1:255.255.255.0:sentry:enp7s0:none" ];
```

Format: `ip=CLIENT_IP::GATEWAY:NETMASK:HOSTNAME:INTERFACE:NONE`

### Per-Host Config

| Host | IP | Interface | NIC Driver | Kernel Param |
|------|-----|-----------|------------|-------------|
| zephyr | 10.1.1.110 | eth0 | r8169 | `ip=10.1.1.110::10.1.1.1:255.255.255.0:zephyr:eth0:none` |
| nexus | 10.1.1.120 | enp7s0 | r8169 | `ip=10.1.1.120::10.1.1.1:255.255.255.0:nexus:enp7s0:none` |
| forge | 10.1.1.130 | eno1 | r8169 | `ip=10.1.1.130::10.1.1.1:255.255.255.0:forge:eno1:none` |
| sentry | 10.1.1.140 | enp7s0 | r8169 | `ip=10.1.1.140::10.1.1.1:255.255.255.0:sentry:enp7s0:none` |

**NIC driver requirement:** r8169 must be added to boot.initrd.availableKernelModules for all hosts (Realtek RTL8111/8168 is the common NIC). Currently none of the hosts have it.

**Host key management:**
- Generate one ed25519 key pair per host via agenix
- Secret file: secrets/initrd-ssh-host-key-HOST.age
- Path: /etc/secrets/initrd/ssh_host_ed25519_key
- Reference in config: config.age.secrets.initrd-ssh-host-key.path

**Security:**
- Key-based auth only (NixOS hardcodes PasswordAuthentication no)
- SSHd killed before stage-2 starts (unless .keep_sshd exists)
- Separate host keys from normal sshd (don't reuse)
- Port 2222 avoids known_hosts conflict with port 22

### Usage

```bash
ssh -p 2222 root@10.1.1.140
# Inside initrd shell:
systemctl status           # see what failed
dmesg | grep -i mount      # check mount errors
mount /sysroot/home         # try manual mount
touch /.keep_sshd           # keep sshd alive into stage-2
```

### Caveats

1. No firewall in initrd — port 2222 is open on the LAN. Acceptable.
2. Host key differs from normal sshd. Use `-o StrictHostKeyChecking=no` or separate known_hosts.
3. NIC driver must be in initrd — if r8169 is missing, no network.
4. Boot timeout — systemd waits ~90s before dropping to emergency mode. SSH available during this window.
5. NetworkManager not running — initrd uses kernel IP params, not NM.

### Effort

- Module: ~60 lines of Nix
- Agenix secrets: 4 new encrypted files
- Testing: deploy to sentry first, verify SSH in initrd

---

## Layer 2: Recovery Specialisation

### What

A NixOS specialisation named "recovery" that creates an additional boot entry: "NixOS (recovery)". Boots a minimal environment: SSH, no GPU services, no NFS, no K8s.

### Why

Even with initrd SSH, if the root filesystem mounts but nftables crashes, or systemd enters a dependency loop, or a GPU service wedges the machine — you need a clean environment to debug from.

### Design

**New module:** `modules/system/recovery-specialisation.nix`

```nix
specialisation.recovery = {
  inheritParentConfig = true;
  configuration = {
    system.nixos.tags = [ "recovery" ];
    boot.loader.systemd-boot.sortKey = "z_nixos_recovery";

    # Auto-skip all NFS mounts
    fileSystems = lib.mapAttrs (mp: cfg:
      if cfg.fsType == "nfs" || cfg.fsType == "nfs4"
      then lib.mkOverride 900 { options = [ "noauto" "nofail" ]; }
      else cfg
    ) config.fileSystems;

    # Disable heavy services
    services.k3s.enable = lib.mkForce false;
    services.xserver.enable = lib.mkForce false;

    # Ensure SSH
    services.openssh = {
      enable = lib.mkForce true;
      settings.PermitRootLogin = "prohibit-password";
    };

    # Recovery tools
    environment.systemPackages = with pkgs; [
      btrfs-progs parted vim curl htop iperf3 ethtool pciutils
    ];

    # Debug kernel params
    boot.kernelParams = [ "debug" "loglevel=7" ];
  };
};
```

**Boot entry appearance in systemd-boot:**
```
Title:  NixOS Generation 276 (recovery)
File:   nixos-generation-276-specialisation-recovery.conf
```

### Caveats

1. NFS /etc/nixos mount is skipped, but NixOS doesn't need it to boot (uses /nix/store closure).
2. Shared initrd from parent — Layer 1's initrd SSH is available in recovery too.
3. nixos-rebuild switch resets to parent config. To stay in recovery: reboot into the entry.
4. Sort key z_nixos_recovery sorts AFTER normal entries.

### Effort

- Module: ~80 lines of Nix
- No secrets needed
- Testing: build for sentry, verify boot entry, boot into it

---

## Layer 3: Pre-Rebuild Btrfs Snapshots

### What

Before every nixos-rebuild switch, snapshot @ and @home. Create systemd-boot entries for snapshots so they appear in the boot menu.

### Why

NixOS generation rollback only rolls back the system closure — not fstab changes, not /home, not /var. The sentry mount bug would NOT have been fixed by generation rollback. A snapshot of @ before the rebuild would have booted instantly.

### Design

**New module:** `modules/system/btrfs-boot-snapshot.nix`

```
services.btrfs-boot-snapshot = {
  enable = true;
  subvolumes = { "@" = { }; "@home" = { }; };
  retention = 5;
  snapshotSubvol = "@snapshots";
};
```

**Mechanism:**

1. Wrapper script `nixos-rebuild-snap`:
   - Snapshots @ and @home as read-only: @-pre-rebuild-YYYYMMDD-HHMMSS
   - Cleans up snapshots beyond retention count
   - Execs nixos-rebuild with same args
   - Skips on dry-activate, build, rollback

2. Boot entry generator (activation script):
   - Reads kernel/initrd from the PREVIOUS generation (already on ESP)
   - Creates entry: snapshot-YYYYMMDD-HHMMSS.conf
   - Uses rootflags=subvol=@-pre-rebuild-TIMESTAMP

**Key trick:** The kernel/initrd on the ESP are just symlinks into /nix/store. They work regardless of which subvol we boot. The snapshot entry uses the previous generation's kernel path.

### Caveats

1. Boot entry kernel must exist on ESP — only works for generations that have been installed to /boot. Previous generation always works.
2. No native NixOS pre-rebuild hook — requires wrapper script. Must remember to use `nixos-rebuild-snap` instead of `nixos-rebuild`.
3. systemd-boot has no submenu support yet (PR #28084 unmerged). Snapshots will clutter the boot menu. Use sort-key to group them.
4. Snapshot subvolume @snapshots must be created once per host: `btrfs subvolume create /mnt/@snapshots`

### Effort

- Module: ~150 lines
- Wrapper script: ~30 lines
- Boot entry generator: ~40 lines
- Testing: build on zephyr, test snapshot + boot, deploy to all

---

## Implementation Order

| Step | Layer | Task | Risk | Time |
|------|-------|------|------|------|
| 1 | L1 | Create initrd-ssh-recovery.nix module | Low | 1h |
| 2 | L1 | Generate host keys, add agenix secrets | Low | 30m |
| 3 | L1 | Add r8169 to all hosts' availableKernelModules | Low | 15m |
| 4 | L1 | Add static IP kernel params per host | Low | 15m |
| 5 | L1 | Deploy to sentry first, test initrd SSH | Medium | 30m |
| 6 | L1 | Deploy to all hosts | Low | 30m |
| 7 | L2 | Create recovery-specialisation.nix module | Low | 1h |
| 8 | L2 | Deploy to sentry, verify boot entry, boot into it | Medium | 30m |
| 9 | L2 | Deploy to all hosts | Low | 30m |
| 10 | L3 | Create btrfs-boot-snapshot.nix module | Medium | 2h |
| 11 | L3 | Create nixos-rebuild-snap wrapper | Low | 30m |
| 12 | L3 | Boot entry generator for snapshots | Medium | 1h |
| 13 | L3 | Deploy to zephyr, test full flow | Medium | 1h |
| 14 | L3 | Deploy to all hosts | Low | 30m |

**Total: ~8-10 hours**
**Priority:** Initrd SSH first (directly prevents "drive to machine"). Recovery second (simple, powerful). Snapshots last (complex, generation rollback covers most cases).

---

## What This Prevents

| Failure Mode | Initrd SSH | Recovery | Snapshots |
|-------------|-----------|----------|-----------|
| Bad fstab/mount options | SSH + manual mount | Skip NFS entirely | Snapshot rollback |
| Broken nftables | SSH before nftables | No nftables | Snapshot rollback |
| Incomplete closure | — | Parent closure | — |
| GPU driver crash | SSH to diagnose | No GPU | Snapshot rollback |
| NFS timeout | SSH to skip mount | NFS skipped | Snapshot rollback |
| K8s pod storm | SSH to stop pods | No K8s | Snapshot rollback |
| Kernel panic | — | — | Snapshot rollback |

Initrd SSH alone prevents ~80% of "drive to machine" scenarios. All three together make physical access almost never needed.

---

## Dependencies

- All hosts already have boot.initrd.systemd.enable = true
- All hosts use systemd-boot
- All hosts use static IPs via NetworkManager
- Agenix is already set up for secrets
- All hosts use Realtek r8169 NICs
