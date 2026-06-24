{ config, pkgs, lib, ... }:
{
  # ── Unbound DNS ─────────────────────────────────────────
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "127.0.0.1" "::1" "10.1.1.150" ];
        access-control = [ "127.0.0.0/8 allow" "10.1.1.0/24 allow" "::1 allow" ];
        private-domain = "lan";
        local-zone = "\"lan.\" static";
        local-data = [
          "\"maplespike.lan. A 10.1.1.110\""
          "\"api.maplespike.lan. A 10.1.1.110\""
          "\"searxng.lan. A 10.1.1.110\""
          "\"search.lan. A 10.1.1.110\""
          "\"haven.lan. A 10.1.1.100\""
          "\"vane.lan. A 10.1.1.110\""
          "\"nexus.lan. A 10.1.1.120\""
          "\"zephyr.lan. A 10.1.1.110\""
          "\"k3s-api.lan. A 10.1.1.100\""
        ];
      };
      forward-zone = [{
        name = ".";
        forward-addr = [ "10.1.1.100" ];
      }];
    };
  };

  # ── Libvirtd ────────────────────────────────────────────
  virtualisation.libvirtd = {
    enable = true;
    qemu.package = pkgs.qemu_kvm;
    qemu.swtpm.enable = true;
    onBoot = "start";
    onShutdown = "shutdown";
  };
  virtualisation.spiceUSBRedirection.enable = true;

  systemd.tmpfiles.rules = [
    "f /var/lib/libvirt/images/c.raw 0640 root libvirtd - -"
  ];

  # ── iSCSI target: export md0p1 to Windows VM ────────────
  services.target = {
    enable = true;
    config = {
      storage_objects = [{
        plugin = "block";
        name = "games-raid";
        dev = "/dev/md0p1";
        attributes = { block_size = 512; emulate_write_cache = 0; unmap_granularity = 512; };
      }];
      targets = [{
        fabric = "iscsi";
        wwn = "iqn.2025-06.lan.krash3:games";
        tpgs = [{
          tag = 1;
          enable = true;
          portals = [{ ip_address = "192.168.122.1"; port = 3260; }];
          luns = [{ index = 0; alias = "games-raid"; storage_object = "/backstores/block/games-raid"; }];
          acls = [{ node_wwn = "iqn.1991-05.com.microsoft:windows-vm"; }];
          attributes = { authentication = 0; generate_node_acls = 1; demo_mode_write_protect = 0; };
        }];
      }];
    };
  };

  systemd.services.configure-iscsi-target = {
    wantedBy = [ "multi-user.target" ];
    after = [ "iscsi-target.service" "assemble-games-raid.service" ];
    requires = [ "iscsi-target.service" "assemble-games-raid.service" ];
    path = [ pkgs.targetcli-fb ];
    script = ''
      for i in $(seq 1 30); do
        [ -b /dev/md0p1 ] && break
        sleep 1
      done
      ${pkgs.python3Packages.rtslib-fb}/bin/targetctl restore /etc/target/saveconfig.json 2>/dev/null || true
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  # ── Samba (local only, krash15 D: accessed directly from VM) ─
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "krash3";
        "netbios name" = "krash3";
        security = "user";
        "map to guest" = "Bad User";
        "guest account" = "nobody";
      };
    };
  };

  # ── VM autostart ────────────────────────────────────────
  systemd.services.libvirt-autostart-windows = {
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" "assemble-games-raid.service" ];
    path = [ pkgs.libvirt ];
    script = ''
      virsh define /var/lib/libvirt/images/windows-domain.xml 2>/dev/null || true
      virsh start windows 2>/dev/null || true
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  # ── Windows post-install config via Guest Agent ─────────
  systemd.services.configure-windows-vm = {
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirt-autostart-windows.service" "iscsi-target.service" ];
    path = [ pkgs.libvirt pkgs.jq ];
    script = ''
      for i in $(seq 1 120); do
        STATE=$(virsh domstate windows 2>/dev/null)
        if [ "$STATE" = "running" ]; then
          RESULT=$(virsh qemu-agent-command windows '{"execute":"guest-ping"}' 2>/dev/null)
          if echo "$RESULT" | grep -q "return"; then
            echo "Guest agent is responsive"
            break
          fi
        fi
        sleep 5
      done
      run_ps() {
        local SCRIPT="$1"
        local ENCODED=$(echo -n "$SCRIPT" | iconv -t UTF-16LE | base64 -w0)
        local CMD=$(cat <<JSON
{"execute":"guest-exec","arguments":{"path":"C:\\\\Windows\\\\System32\\\\WindowsPowerShell\\\\v1.0\\\\powershell.exe","arg":["-NoProfile","-NonInteractive","-EncodedCommand","$ENCODED"],"capture-output":true}}
JSON
)
        local HANDLE=$(virsh qemu-agent-command windows "$CMD" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.return.pid // empty')
        [ -z "$HANDLE" ] && { echo "Failed to execute PowerShell"; return 1; }
        for i in $(seq 1 60); do
          local STATUS=$(virsh qemu-agent-command windows "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$HANDLE}}" 2>/dev/null)
          local EXITED=$(echo "$STATUS" | ${pkgs.jq}/bin/jq -r '.return.exited // false')
          if [ "$EXITED" = "true" ]; then
            local CODE=$(echo "$STATUS" | ${pkgs.jq}/bin/jq -r '.return.exitcode // -1')
            echo "Exit: $CODE"
            echo "$STATUS" | ${pkgs.jq}/bin/jq -r '.return."out-data" // empty' | base64 -d 2>/dev/null
            return $CODE
          fi
          sleep 2
        done
        return 1
      }
      run_ps 'Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue; Set-Item WSMan:\\localhost\\Service\\Auth\\Basic -Value $true -Force; Set-Item WSMan:\\localhost\\Service\\AllowUnencrypted -Value $true -Force; Set-Service WinRM -StartupType Automatic; Restart-Service WinRM -Force; Write-Output \"WinRM configured\"' || true
      run_ps 'Set-Service MSiSCSI -StartupType Automatic; Start-Service MSiSCSI -ErrorAction SilentlyContinue; Start-Sleep 2; New-IscsiTargetPortal -TargetPortalAddress \"192.168.122.1\" -ErrorAction SilentlyContinue; Start-Sleep 2; Get-IscsiTarget -ErrorAction SilentlyContinue | ForEach-Object { if (-not $_.IsConnected) { Connect-IscsiTarget -NodeAddress $_.NodeAddress -TargetPortalAddress \"192.168.122.1\" -IsPersistent $true -ErrorAction SilentlyContinue; Write-Output \"iSCSI connected\" } }' || true
      run_ps 'Get-Disk | Where-Object { $_.BusType -eq \"iSCSI\" } | Format-Table Number, Size, PartitionStyle -AutoSize' || true
      echo "=== Windows configuration complete ==="
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 600;
    };
  };

  # ── Packages ────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    virt-manager libvirt virtio-win swtpm jq
  ];
}
