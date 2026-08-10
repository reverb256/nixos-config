# Game Pass Windows VM via Incus — Zephyr only
#
# This is the parallel Incus backend for modules/hardware/vfio-gamepass.nix.
# Both backends intentionally remain dormant and use separate storage. The
# existing libvirt domain is the rollback path; this Incus VM becomes the
# migration target after Windows is installed and tested.
#
# Guest contract shared with libvirt:
#   - 8 vCPUs pinned to host CPUs 8-15
#   - 16 GiB RAM
#   - Windows guest firmware/clock behavior
#   - VirtIO root disk and network
#   - TPM 2.0 and secure boot
#   - RTX 3060 Ti VGA + HDMI audio passthrough
#   - separate 200 GiB Incus storage volume
#
# Important: Incus instance state is deliberately not created at activation.
# The operator must run `incus-gamepass-vm create` once, then install Windows
# from the imported ISO. This avoids an activation unexpectedly creating or
# starting a VM, and keeps the libvirt rollback definition untouched.
{config, lib, pkgs, ...}: let
  cfg = config.virtualisation.incus;
  incus = cfg.clientPackage;
  incusVm = "gamepass-win11-incus";
  libvirtVm = "gamepass-win11";
  storagePool = "gamepass";
  storageRoot = "/var/lib/incus-gamepass";
  incusNetwork = "incusbr-gp";
  vfioGpu = "0000:24:00.0";
  vfioAudio = "0000:24:00.1";
  lookingGlass = pkgs.looking-glass-client;

  # nixpkgs' virtio-win is only the extracted driver tree (no ISO). Windows'
  # installer needs the VirtIO ISO to see its disk. The official release ISO
  # is a plain data CD of that same tree, so build it offline from the
  # nixpkgs driver tree with xorriso (no external download, fully declarative).
  virtioWinIso = pkgs.runCommandNoCC "virtio-win-iso" {
    nativeBuildInputs = [ pkgs.libisoburn pkgs.virtio-win ];
  } ''
    mkdir -p "$out"
    xorriso -as mkisofs \
      -V "VIRTIOWIN" -o "$out/virtio-win.iso" \
      ${pkgs.virtio-win}
  '';

  lookingGlassCheck = pkgs.writeShellScript "gamepass-looking-glass-check" ''
    set -euo pipefail
    device=/dev/kvmfr0
    test -c "$device" || {
      echo "Looking Glass unavailable: $device is not a character device" >&2
      exit 1
    }
    test -r "$device" -a -w "$device" || {
      echo "Looking Glass unavailable: $device is not readable and writable" >&2
      ls -l "$device" >&2 || true
      exit 1
    }
  '';

  lookingGlassLauncher = pkgs.writeShellScriptBin "looking-glass-gamepass" ''
    set -euo pipefail
    exec ${lookingGlass}/bin/looking-glass-client \
      -f /dev/kvmfr0 \
      -F \
      -S \
      "$@"
  '';

  # Shared dynamic handoff for both VM backends. Incus does not provide
  # libvirt's managed="yes" behavior, so make the ownership transition
  # explicit and reversible. The lock and owner marker also protect against
  # two wrapper-managed starts racing each other.
  handoffScript = pkgs.writeShellScript "gamepass-vfio-handoff" ''
    set -euo pipefail

    exec 9>/run/lock/gamepass-vfio.lock
    ${pkgs.util-linux}/bin/flock -x 9
    mode="''${1:-}"
    owner_file=/run/gamepass-vfio/owner
    devices=("${vfioGpu}" "${vfioAudio}")

    driver_for() {
      local dev="$1"
      if [ -L "/sys/bus/pci/devices/$dev/driver" ]; then
        basename "$(readlink "/sys/bus/pci/devices/$dev/driver")"
      else
        echo none
      fi
    }

    rollback_claim() {
      # ERR trap path: restore every function touched before returning the
      # original failure. Never leave a half-bound GPU behind.
      set +e
      for dev in "''${devices[@]}"; do
        if [ "$(driver_for "$dev")" = vfio-pci ]; then
          echo "$dev" > /sys/bus/pci/drivers/vfio-pci/unbind
        fi
        echo "" > "/sys/bus/pci/devices/$dev/driver_override"
        echo "$dev" > /sys/bus/pci/drivers_probe
      done
      modprobe nvidia 2>/dev/null || true
      modprobe snd_hda_intel 2>/dev/null || true
      for dev in "''${devices[@]}"; do
        echo "$dev" > /sys/bus/pci/drivers_probe
      done
      rm -f "$owner_file"
    }

    claim() {
      local backend="$1"
      trap rollback_claim ERR
      mkdir -p /run/gamepass-vfio
      if [ -s "$owner_file" ] && [ "$(cat "$owner_file")" != "$backend" ]; then
        echo "3060 Ti is already owned by $(cat "$owner_file")" >&2
        exit 1
      fi

      if [ "$backend" = incus ]; then
        if ${pkgs.libvirt}/bin/virsh -c qemu:///system domstate ${libvirtVm} 2>/dev/null \
          | ${pkgs.gnugrep}/bin/grep -Eiq 'running|paused'; then
          echo "Refusing Incus ownership: libvirt ${libvirtVm} is active" >&2
          exit 1
        fi
      else
        if ${incus}/bin/incus info ${incusVm} --format csv -c status 2>/dev/null \
          | ${pkgs.gnugrep}/bin/grep -Eiq 'running|paused|frozen'; then
          echo "Refusing libvirt ownership: Incus ${incusVm} is active" >&2
          exit 1
        fi
      fi

      # Stop only the workloads known to use this card. The RTX 3090 services
      # are not touched.
      for unit in peakminer-zephyr-3060ti.service bonsai-1bit-zephyr.service; do
        systemctl stop "$unit" 2>/dev/null || true
      done

      modprobe vfio-pci
      for dev in "''${devices[@]}"; do
        driver=$(driver_for "$dev")
        case "$driver" in
          vfio-pci|none) ;;
          nvidia|snd_hda_intel)
            echo "$dev" > "/sys/bus/pci/drivers/$driver/unbind"
            ;;
          *)
            echo "Refusing to detach $dev from unexpected driver $driver" >&2
            exit 1
            ;;
        esac
        echo vfio-pci > "/sys/bus/pci/devices/$dev/driver_override"
        echo "$dev" > /sys/bus/pci/drivers/vfio-pci/bind
      done

      for dev in "''${devices[@]}"; do
        [ "$(driver_for "$dev")" = vfio-pci ] || {
          echo "VFIO bind failed for $dev" >&2
          exit 1
        }
      done
      printf '%s\\n' "$backend" > "$owner_file"
      trap - ERR
    }

    release() {
      local backend="''${1:-}"
      [ -e "$owner_file" ] || backend=""
      if [ -n "$backend" ] && [ -s "$owner_file" ] && [ "$(cat "$owner_file")" != "$backend" ]; then
        echo "Not releasing GPU owned by $(cat "$owner_file")" >&2
        exit 1
      fi

      for dev in "''${devices[@]}"; do
        if [ "$(driver_for "$dev")" = vfio-pci ]; then
          echo "$dev" > /sys/bus/pci/drivers/vfio-pci/unbind || true
        fi
        echo "" > "/sys/bus/pci/devices/$dev/driver_override" || true
        echo "$dev" > /sys/bus/pci/drivers_probe || true
      done
      modprobe nvidia 2>/dev/null || true
      modprobe snd_hda_intel 2>/dev/null || true
      local expected=(nvidia snd_hda_intel)
      local index=0
      for dev in "''${devices[@]}"; do
        echo "$dev" > /sys/bus/pci/drivers_probe || true
        actual=$(driver_for "$dev")
        if [ "$actual" != "''${expected[$index]}" ]; then
          echo "GPU cleanup incomplete: $dev is bound to $actual (expected ''${expected[$index]})" >&2
          return 1
        fi
        index=$((index + 1))
      done
      rm -f "$owner_file"
    }

    case "$mode" in
      pre-incus) claim incus ;;
      pre-libvirt) claim libvirt ;;
      post) release "''${2:-}" ;;
      *) echo "Usage: $0 {pre-incus|pre-libvirt|post [owner]}" >&2; exit 2 ;;
    esac
  '';

  gamepassVm = pkgs.writeShellScriptBin "incus-gamepass-vm" ''
    set -euo pipefail

    incus=${incus}/bin/incus
    virsh=${pkgs.libvirt}/bin/virsh
    vm=${lib.escapeShellArg incusVm}
    libvirt_vm=${lib.escapeShellArg libvirtVm}
    pool=${lib.escapeShellArg storagePool}
    iso=${lib.escapeShellArg "/var/lib/libvirt/images/win11.iso"}
    virtio_iso=${lib.escapeShellArg "${virtioWinIso}/virtio-win.iso"}

    usage() {
      cat >&2 <<'EOF'
Usage:
  incus-gamepass-vm create         Create the dormant Incus VM and import ISOs
  incus-gamepass-vm start           Start Incus VM through the ownership guard
  incus-gamepass-vm stop            Stop Incus VM through the ownership guard
  incus-gamepass-vm start-libvirt   Start the dormant libvirt rollback VM
  incus-gamepass-vm stop-libvirt    Stop the libvirt rollback VM
  incus-gamepass-vm status          Show both backend states
  incus-gamepass-vm check-looking-glass  Verify host KVMFR access
EOF
      exit 2
    }

    libvirt_state() {
      $virsh -c qemu:///system domstate "$libvirt_vm" 2>/dev/null || echo "undefined"
    }

    incus_state() {
      $incus info "$vm" --format csv -c status 2>/dev/null || echo "undefined"
    }

    check_looking_glass() {
      test -c /dev/kvmfr0 || {
        echo "Missing /dev/kvmfr0; deploy kvmfr before starting a VM" >&2
        exit 1
      }
      test -r /dev/kvmfr0 -a -w /dev/kvmfr0 || {
        echo "Cannot read/write /dev/kvmfr0; check kvm group permissions" >&2
        ls -l /dev/kvmfr0 >&2 || true
        exit 1
      }
      echo "KVMFR ready: $(stat -c '%U:%G %a' /dev/kvmfr0)"
    }

    ensure_iso_volume() {
      local path="$1"
      local name="$2"
      if ! $incus storage volume show "$pool" "$name" >/dev/null 2>&1; then
        test -f "$path" || {
          echo "Missing installer media: $path" >&2
          exit 1
        }
        $incus storage volume import "$pool" "$path" "$name" --type=iso
      fi
    }

    create_vm() {
      if $incus info "$vm" >/dev/null 2>&1; then
        echo "$vm already exists"
        exit 0
      fi
      test -f "$iso" || { echo "Missing installer media: $iso" >&2; exit 1; }
      test -f "$virtio_iso" || { echo "Missing VirtIO media: $virtio_iso" >&2; exit 1; }

      # `--empty --vm` creates a stopped VM. The preseeded profile supplies the
      # 200 GiB root volume, network, TPM, and PCI devices.
      $incus init --empty "$vm" --vm --profile gamepass-win11
      $incus config set "$vm" image.os Windows
      ensure_iso_volume "$iso" win11-installer
      ensure_iso_volume "$virtio_iso" virtio-win
      $incus config device add "$vm" installer disk \
        pool="$pool" source=win11-installer boot.priority=10
      $incus config device add "$vm" virtio-win disk \
        pool="$pool" source=virtio-win
      # Keep the Incus agent CD available for Windows agent installation and
      # later updates; it does not affect the Windows installer boot order.
      $incus config device add "$vm" incus-agent disk source=agent:config
      echo "Created dormant $vm. Start it only after reviewing: incus config show $vm --expanded"
    }

    case "''${1:-}" in
      create)
        create_vm
        ;;
      start)
        $virsh -c qemu:///system domstate "$libvirt_vm" 2>/dev/null \
          | grep -qx running && {
            echo "Refusing Incus start: $libvirt_vm is running" >&2
            exit 1
          } || true
        exec systemctl start gamepass-incus-vm.service
        ;;
      stop)
        exec systemctl stop gamepass-incus-vm.service
        ;;
      start-libvirt)
        $incus info "$vm" --format csv -c status 2>/dev/null \
          | grep -Eiq 'running|started' && {
            echo "Refusing libvirt start: $vm is running" >&2
            exit 1
          } || true
        exec systemctl start gamepass-libvirt-vm.service
        ;;
      stop-libvirt)
        exec systemctl stop gamepass-libvirt-vm.service
        ;;
      status)
        printf 'libvirt %-24s %s\n' "$libvirt_vm" "$(libvirt_state)"
        printf 'incus   %-24s %s\n' "$vm" "$(incus_state)"
        ;;
      *)
        usage
        ;;
    esac
  '';

  vmStopScript = pkgs.writeShellScript "gamepass-incus-stop" ''
    set -euo pipefail
    ${incus}/bin/incus stop ${lib.escapeShellArg incusVm} --force 2>/dev/null || true
  '';

  libvirtStopScript = pkgs.writeShellScript "gamepass-libvirt-stop" ''
    set -euo pipefail
    ${pkgs.libvirt}/bin/virsh -c qemu:///system shutdown ${lib.escapeShellArg libvirtVm} 2>/dev/null || true
  '';
in {
  config = lib.mkIf (config.networking.hostName == "zephyr") {
    virtualisation.incus = {
      enable = true;
      # Incus owns its own bridge and storage pool; libvirt's default network
      # remains separate. Preseed is idempotent and does not remove entities.
      preseed = {
        networks = [
          {
            name = incusNetwork;
            type = "bridge";
            config = {
              "ipv4.address" = "10.77.0.1/24";
              "ipv4.nat" = "true";
              "ipv6.address" = "none";
            };
          }
        ];
        storage_pools = [
          {
            name = storagePool;
            driver = "dir";
            config = {
              source = storageRoot;
            };
          }
        ];
        profiles = [
          {
            name = "gamepass-win11";
            config = {
              "limits.cpu" = "8-15";
              "limits.memory" = "16GiB";
              "limits.memory.hotplug" = "false";
              "security.secureboot" = "true";
              "boot.autostart" = "false";
              "boot.host_shutdown_action" = "stop";
              # Incus passes these raw QEMU arguments to the VM so the guest
              # can use the same 64 MiB Looking Glass shared-memory transport
              # as the libvirt backend. The host kvmfr module is supplied by
              # vfio-gamepass.nix.
              "raw.qemu" = "-object memory-backend-file,id=looking-glass,mem-path=/dev/kvmfr0,size=64M,share=on -device ivshmem-plain,memdev=looking-glass";
            };
            devices = {
              root = {
                type = "disk";
                path = "/";
                pool = storagePool;
                size = "200GiB";
              };
              eth0 = {
                type = "nic";
                name = "eth0";
                network = incusNetwork;
              };
              tpm = {
                type = "tpm";
              };
              gpu = {
                type = "pci";
                address = vfioGpu;
              };
              gpu-audio = {
                type = "pci";
                address = vfioAudio;
              };
            };
          }
        ];
      };
    };

    users.users.j_kro.extraGroups = [ "incus" "incus-admin" ];

    # Incus delegates its cgroup to the QEMU VM process. Give that service
    # access to the same KVMFR character device used by libvirt's QEMU. This
    # is intentionally narrower than a blanket device policy.
    systemd.services.incus.serviceConfig = {
      SupplementaryGroups = [ "kvm" ];
      DeviceAllow = [ "/dev/kvmfr0 rw" ];
    };

    systemd.tmpfiles.rules = [
      "d ${storageRoot} 0750 root root -"
    ];

    environment.systemPackages = [ gamepassVm lookingGlassLauncher pkgs.squashfsTools ];

    # Both backend units are manual-only. Conflicts prevents a normal
    # systemctl start from allowing both managers to own the GPU at once.
    # Direct `virsh`/`incus` commands can bypass any service guard, so normal
    # operations should use incus-gamepass-vm.
    systemd.services.gamepass-libvirt-vm = {
      description = "Dormant libvirt Game Pass Windows VM (rollback backend)";
      after = [ "libvirtd.service" "gamepass-vm-define.service" ];
      wants = [ "gamepass-vm-define.service" ];
      conflicts = [ "gamepass-incus-vm.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${handoffScript} pre-libvirt";
        ExecStart = "${pkgs.libvirt}/bin/virsh -c qemu:///system start ${libvirtVm}";
        ExecStop = libvirtStopScript;
        ExecStopPost = "${handoffScript} post libvirt";
        TimeoutStartSec = "infinity";
        TimeoutStopSec = 120;
      };
    };

    systemd.services.gamepass-incus-vm = {
      description = "Dormant Incus Game Pass Windows VM (migration backend)";
      after = [ "incus.service" "incus-preseed.service" ];
      wants = [ "incus-preseed.service" ];
      requires = [ "incus-preseed.service" ];
      conflicts = [ "gamepass-libvirt-vm.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = [
          lookingGlassCheck
          "${handoffScript} pre-incus"
        ];
        ExecStart = "${incus}/bin/incus start ${incusVm}";
        ExecStop = vmStopScript;
        ExecStopPost = "${handoffScript} post incus";
        TimeoutStartSec = "infinity";
        TimeoutStopSec = 120;
      };
    };
  };
}
