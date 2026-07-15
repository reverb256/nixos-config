{ config, pkgs, lib, ... }:
let
  params = import ./params.nix;
  inherit (params) vm;
in {
  # ── DNS ─────────────────────────────────────────────────
  # DNS is owned by cluster-dns.nix (enabled via clusterNetworking.unbound in
  # configuration.nix). It forwards "." to the DoT upstreams and "cluster.local."
  # to CoreDNS, and serves the .lan records defined centrally. The previous
  # standalone services.unbound block here forwarded "." -> 10.1.1.100 (the
  # VIP, hosted on zephyr) which looped and broke all external resolution on
  # krash3. Removed in favor of the cluster-wide SSOT.

  # ── E: drive ────────────────────────────────────────────
  # E: is a DIRECT virtio-blk disk on /dev/md0 (whole GPT RAID with one NTFS
  # data partition; see params.nix). Not iSCSI. assemble-games-raid still
  # builds /dev/md0 (+ md0p1 for host tooling).

  # ── Samba ────────────────────────────────────────────────
  services.samba = {
    enable = true; openFirewall = lib.mkForce false;
    settings = {
      global = {
        workgroup = "WORKGROUP"; "server string" = "krash3"; "netbios name" = "krash3";
        security = "user"; "map to guest" = "Bad User"; "guest account" = "nobody";
      };
    };
  };

  # ── k3s cluster agent ────────────────────────────────────
  services.k3s-cluster = {
    enable = true;
    nvidia.enable = true;
    role = "agent";
    nodeName = "krash3";
    serverAddr = "https://${config.networking.cluster.kubernetes.vip}:${toString config.networking.cluster.kubernetes.apiPort}";
    tokenFile = "/persistent/etc/k3s-cluster-token";
    nodeIP = config.networking.cluster.hosts.krash3.ip;
    flannelIface = "eth0";
  };
  services.k3s-pod-affinity.enable = lib.mkForce false;

  # ── VM autostart ─────────────────────────────────────────
  # Define the domain from the declarative XML FIRST (so the running domain
  # always matches config), then start it. `virsh define` is idempotent.
  systemd.services.libvirt-autostart-windows = {
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" "assemble-games-raid.service" ];
    path = [ pkgs.libvirt ];
    script = ''
      virsh define --validate /etc/libvirt/qemu/krash3-vm.xml
      virsh start krash3-vm || true
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  # ── Guest-agent self-healing ───────────────────────────
  # Liveness check only — NEVER hard-resets the VM.
  # The qemu-guest-agent on Windows can wedge its exec mutex (async process
  # spawn). That is NOT a data-loss condition — guest-ping still works, the
  # VM runs fine. A `virsh destroy` during an in-flight disk write corrupts
  # the NTFS on D: (proven root cause of the recurring `00 XX 01 XX...`
  # counting-byte pattern in the MFT). This service only logs the wedge and
  # exits 0 so it never blocks or kills.
  #
  # Strategy:
  #   1. ping OK  + exec probe OK   -> healthy, do nothing.
  #   2. ping OK  + exec probe HANG -> log WARNING, do NOT reset.
  #   3. ping FAIL                  -> log WARNING, do NOT reset.
  # Must NEVER block host deploys: bounded timeouts, exits 0 either way.
  systemd.services.krash3-vm-agent-health = {
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirt-autostart-windows.service" ];
    path = [ pkgs.libvirt pkgs.jq pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 90;
    };
    script = ''
      export LIBVIRT_URI=qemu:///system
      DOM="krash3-vm"
      ping_agent() {
        out=$(virsh qemu-agent-command "$DOM" '{"execute":"guest-ping"}' 2>/dev/null)
        echo "$out" | grep -q '"return"'
      }
      # Only act if the domain is actually running.
      virsh domstate "$DOM" 2>/dev/null | grep -q running || { echo "guest not running, skip"; exit 0; }
      if ping_agent; then
        echo "guest-agent: healthy"
        exit 0
      fi
      # ping failed — guest agent is down or disconnected.
      # This is NOT a data-loss condition. Log the issue and exit.
      # NEVER `virsh destroy` here — that has caused NTFS corruption.
      echo "guest-agent: NOT RESPONDING (ping failed) — manual recovery may be needed"
      exit 0
    '';
  };

  # ── Runtime files ────────────────────────────────────────
  systemd.tmpfiles.rules = [
    # NOTE: c.raw image creation moved to ensure-images-subvolume (NOCOW subvol).
    "L+ /run/secrets/k3s-cluster-token - - - - /persistent/etc/k3s-cluster-token"
  ];

  # ── VM images dir: NOCOW btrfs subvolume ─────────────────
  # /var/lib/libvirt/images becomes a subvolume with inherited NOCOW so any
  # future VM image file skips btrfs copy-on-write. Existing c.raw keeps its
  # current allocation (Track B may re-seed it onto the RAID later).
  #
  # Conversion to a subvolume requires moving c.raw aside; that is unsafe while
  # the VM holds the image open, so this unit does the SAFE part now (set NOCOW
  # on the existing dir + ensure it exists) and only does the full dir→subvolume
  # conversion when it can move files without error. If it can't (VM running),
  # it best-effort sets chattr +C on the dir and exits 0 — the full subvolume
  # conversion is completed during the next VM-off maintenance window.
  systemd.services.ensure-images-subvolume = {
    wantedBy = [ "multi-user.target" ];
    before = [ "libvirtd.service" "virtlogd.service" ];
    path = [ pkgs.btrfs-progs pkgs.coreutils pkgs.e2fsprogs ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      D=/var/lib/libvirt/images
      mkdir -p "$(dirname "$D")"
      [ -d "$D" ] || mkdir -p "$D"

      # Already a subvolume? just ensure NOCOW and done.
      if btrfs subvolume show "$D" >/dev/null 2>&1; then
        btrfs property set "$D" compression "" 2>/dev/null || true
        chattr +C "$D" 2>/dev/null || true
        exit 0
      fi

      # Try a clean conversion (move contents aside, make subvolume, move back).
      # This only succeeds if nothing holds files open (e.g. VM stopped).
      if T="$(mktemp -d "$D/.seed.XXXXXX" 2>/dev/null)"; then
        if mv "$D"/* "$T"/ 2>/dev/null; then
          if rmdir "$D" 2>/dev/null && btrfs subvolume create "$D" 2>/dev/null; then
            chown root:kvm "$D"; chmod 0750 "$D"
            mv "$T"/* "$D"/ 2>/dev/null || true
            rmdir "$T" 2>/dev/null || true
            btrfs property set "$D" compression "" 2>/dev/null || true
            chattr +C "$D" 2>/dev/null || true
            echo "converted $D to NOCOW subvolume"
            exit 0
          fi
        fi
        # conversion failed (likely open files) — restore and fall through
        mv "$T"/* "$D"/ 2>/dev/null || true
        rmdir "$T" 2>/dev/null || true
      fi

      # Best-effort: set NOCOW on the existing plain dir; full conversion deferred
      # to the next VM-off maintenance window.
      chattr +C "$D" 2>/dev/null || true
      echo "deferred full subvolume conversion (VM likely holds c.raw open); set NOCOW on dir"
      exit 0
    '';
  };

  # ── Packages ─────────────────────────────────────────────
  environment.systemPackages = with pkgs; [ virt-manager git libvirt virtio-win swtpm jq e2fsprogs ];
}
