{ config, pkgs, lib, ... }:
let
  params = import ./params.nix;
  inherit (params) vm;
in {
  # ── Unbound DNS ─────────────────────────────────────────
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "127.0.0.1" "::1" "10.1.1.150" ];
        access-control = [ "127.0.0.0/8 allow" "10.1.1.0/24 allow" "::1 allow" ];
        private-domain = "lan";
        local-zone = [ "lan. static" ];
        local-data = [
          # Services (Caddy-proxied via VIP 10.1.1.100 for HA)
          ''"maplespike.lan. A 10.1.1.100"''
          ''"api.maplespike.lan. A 10.1.1.100"''
          ''"searxng.lan. A 10.1.1.100"''
          ''"search.lan. A 10.1.1.100"''
          ''"vane.lan. A 10.1.1.100"''
          ''"haven.lan. A 10.1.1.100"''
          ''"ai-inference.lan. A 10.1.1.100"''
          ''"auth.lan. A 10.1.1.100"''
          ''"grafana.lan. A 10.1.1.100"''
          ''"n8n.lan. A 10.1.1.100"''
          ''"gitea.lan. A 10.1.1.100"''
          # Host records (direct IPs)
          ''"nexus.lan. A 10.1.1.120"''
          ''"zephyr.lan. A 10.1.1.110"''
          ''"forge.lan. A 10.1.1.130"''
          ''"sentry.lan. A 10.1.1.140"''
          # Infrastructure
          ''"k3s-api.lan. A 10.1.1.100"''
        ];
      };
      forward-zone = [{
        name = ".";
        forward-addr = [ "10.1.1.100" ];
      }];
    };
  };

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
    tokenFile = "/run/secrets/k3s-cluster-token";
    nodeIP = config.networking.cluster.hosts.krash3.ip;
    flannelIface = "enp7s0";
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
    "f /var/lib/libvirt/images/c.raw 0640 root kvm - -"
    "L+ /run/secrets/k3s-cluster-token - - - - /persistent/etc/k3s-cluster-token"
  ];

  # ── E: drive watchdog ───────────────────────────────────
  # Verifies from INSIDE the guest that E: is Healthy. Disk source is /dev/md0
  # (GPT RAID with one NTFS data partition). Self-heals:
  #   (a) missing vdb → re-attach /dev/md0
  #   (b) letter drift (often D:) → diskpart assign letter=E
  # guest-exec returns only a pid — always poll guest-exec-status + decode
  # out-data. Bounded timeouts; never fail the unit hard.
  systemd.services.e-drive-watchdog = {
    # NOT in wantedBy — timer only (avoids switch-abort if VM isn't ready).
    after = [ "libvirtd.service" "assemble-games-raid.service" ];
    path = [ pkgs.libvirt pkgs.qemu pkgs.jq pkgs.coreutils pkgs.gnugrep ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 90;
    };
    script = ''
      export LIBVIRT_URI=qemu:///system
      DOM="krash3-vm"
      if ! virsh domstate "$DOM" 2>/dev/null | grep -q running; then
        virsh start "$DOM" 2>/dev/null || true
        sleep 20
      fi

      # guest_ps: run PowerShell, poll status, print decoded stdout (or empty).
      guest_ps() {
        local ps_cmd="$1" raw pid i st b64
        raw=$(timeout 12 virsh qemu-agent-command "$DOM" \
          "$(${pkgs.jq}/bin/jq -nc --arg p "$ps_cmd" \
            '{execute:"guest-exec",arguments:{path:"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",arg:["-NoProfile","-Command",$p],"capture-output":true}}')" \
          2>/dev/null) || true
        pid=$(echo "$raw" | ${pkgs.jq}/bin/jq -r '.return.pid // empty' 2>/dev/null) || true
        [ -n "$pid" ] || return 0
        for i in $(seq 1 20); do
          st=$(timeout 8 virsh qemu-agent-command "$DOM" \
            "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}" 2>/dev/null) || true
          if echo "$st" | ${pkgs.jq}/bin/jq -e '.return.exited == true' >/dev/null 2>&1; then
            b64=$(echo "$st" | ${pkgs.jq}/bin/jq -r '.return["out-data"] // empty' 2>/dev/null) || true
            if [ -n "$b64" ]; then
              echo "$b64" | base64 -d 2>/dev/null || true
            fi
            return 0
          fi
          sleep 0.5
        done
        return 0
      }

      OUT=$(guest_ps "try { (Get-Volume -DriveLetter E -ErrorAction Stop).HealthStatus } catch { 'MISSING' }")
      if echo "$OUT" | grep -qi "Healthy"; then
        echo "E: healthy — no action needed"
        exit 0
      fi
      # Empty/garbled result = transient guest-agent wedge, NOT a real
      # drive fault. Don't thrash the VM (re-attach vdb / run diskpart) on a
      # wedge — just skip this pass and let the next tick re-check.
      if [ -z "$(echo "$OUT" | tr -d '\r\n[:space:]')" ]; then
        echo "E: agent returned no data (likely transient wedge) — skipping this pass"
        exit 0
      fi
      echo "E: NOT healthy (got: $OUT) — attempting recovery"

      if ! virsh dumpxml "$DOM" 2>/dev/null | grep -q "vdb"; then
        virsh attach-disk "$DOM" --type block --source /dev/md0 --target vdb --persistent 2>&1 || true
        sleep 5
      fi

      GAMES=$(guest_ps "\$v = Get-Volume | Where-Object { \$_.DriveLetter -and \$_.DriveLetter -ne [char]67 -and \$_.DriveLetter -ne [char]69 -and \$_.FileSystem -eq 'NTFS' -and \$_.Size -gt 500GB } | Select-Object -First 1; if (\$v) { [string]\$v.DriveLetter }")
      GAMES=$(echo "$GAMES" | tr -d '\r\n[:space:]')
      if [ -n "$GAMES" ] && [ "$GAMES" != "E" ]; then
        echo "Games volume found on $GAMES — reassigning to E:"
        guest_ps "\$s = @\"
select volume $GAMES
assign letter=E noerr
\"@; \$s | Out-File -Encoding ascii C:\\dk.txt; diskpart /s C:\\dk.txt | Out-String" >/dev/null || true
        sleep 3
      fi

      OUT2=$(guest_ps "try { (Get-Volume -DriveLetter E -ErrorAction Stop).HealthStatus } catch { 'MISSING' }")
      if echo "$OUT2" | grep -qi "Healthy"; then
        echo "E: recovered — healthy"
        exit 0
      fi
      echo "E: not confirmed healthy this pass (agent may be wedged or volume still binding): $OUT2"
      exit 0
    '';
  };

  systemd.timers.e-drive-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "60s";
      OnUnitActiveSec = "300s";
      Unit = "e-drive-watchdog.service";
    };
  };

  # ── Packages ─────────────────────────────────────────────
  environment.systemPackages = with pkgs; [ virt-manager git libvirt virtio-win swtpm jq ];
}
