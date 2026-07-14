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
      virsh define /etc/libvirt/qemu/krash3-vm.xml 2>/dev/null || true
      virsh start krash3-vm 2>/dev/null || true
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  # ── Guest-agent self-healing ───────────────────────────
  # Liveness is determined by `guest-ping` (synchronous QMP — always reliable).
  # The qemu-guest-agent on Windows has a known defect: `guest-exec` (async
  # process spawn) can wedge its internal exec mutex when a child's stdio pipe
  # isn't drained, leaving guest-exec permanently unresponsive while ping still
  # works. That wedge can only be cleared by restarting the qemu-ga process,
  # which on the host means a graceful VM reset (libvirt `reset`).
  #
  # Strategy:
  #   1. ping OK  + exec probe OK   -> healthy, do nothing.
  #   2. ping OK  + exec probe HANG -> exec wedged -> `virsh reset` to clear it.
  #   3. ping FAIL                  -> qemu-ga not up -> try guest-exec restart
  #                                     once; if still down, `virsh reset`.
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
      # Trivial exec probe with a hard wall-clock timeout. Returns 0 if exec
      # completes, 1 if it hangs/fails. Uses `timeout` so a wedged exec can't
      # block the whole service.
      exec_ok() {
        timeout 12 virsh qemu-agent-command "$DOM" \
          '{"execute":"guest-exec","arguments":{"path":"C:\\Windows\\System32\\cmd.exe","arg":["/c","echo ga-probe"],"capture-output":true}}' \
          >/dev/null 2>&1
      }
      # Graceful VM reset — the only host lever that restores a wedged qemu-ga.
      reset_guest() {
        echo "guest-agent: wedge/down — graceful VM reset to restore qemu-ga"
        virsh reset "$DOM" >/dev/null 2>&1 || virsh destroy "$DOM" >/dev/null 2>&1
        sleep 8
        virsh start "$DOM" >/dev/null 2>&1 || true
        sleep 20
      }
      # Only act if the domain is actually running.
      virsh domstate "$DOM" 2>/dev/null | grep -q running || { echo "guest not running, skip"; exit 0; }
      if ping_agent && exec_ok; then
        echo "guest-agent: healthy (ping + exec)"
        exit 0
      fi
      if ping_agent && ! exec_ok; then
        echo "guest-agent: ping OK but exec wedged"
        reset_guest
        ping_agent && echo "guest-agent: recovered after reset" || echo "guest-agent: still down after reset"
        exit 0
      fi
      # ping failed entirely
      echo "guest-agent: down — attempt in-guest qemu-ga restart"
      virsh qemu-agent-command "$DOM" "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"C:\\Windows\\System32\\cmd.exe\",\"arg\":[\"/c\",\"net stop qemu-guest-agent & net start qemu-guest-agent\"],\"capture-output\":true}}" >/dev/null 2>&1 || true
      sleep 10
      if ping_agent; then
        echo "guest-agent: recovered"
      else
        echo "guest-agent: still down — graceful reset"
        reset_guest
        ping_agent && echo "guest-agent: recovered after reset" || echo "guest-agent: STILL down"
      fi
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
