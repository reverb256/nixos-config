# Game Pass Windows VM via Incus — Zephyr only
#
# This is the sole Incus backend for the Zephyr Game Pass VM.
# Incus exclusively owns the RTX 3060 Ti when the VM is started; the RTX 3090
# remains host-owned. The retired libvirt backend is not imported or started.
#
# Incus guest contract:
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
# from the imported ISO. This avoids activation unexpectedly creating or
# starting a VM.
{config, lib, pkgs, vfioPkgs, ...}: let
  cfg = config.virtualisation.incus;
  incus = cfg.clientPackage;
  incusVm = "gamepass-win11-incus";
  storagePool = "gamepass";
  storageRoot = "/var/lib/incus-gamepass";
  incusNetwork = "incusbr-gp";
  vfioGpu = "0000:24:00.0";
  vfioAudio = "0000:24:00.1";
  vfioGpuVendor = "0x10de";
  vfioGpuDevice = "0x2486";
  vfioAudioVendor = "0x10de";
  vfioAudioDevice = "0x228b";
  vfioIommuGroup = "24";
  protectedGpu = "0000:2d:00.0";
  protectedAudio = "0000:2d:00.1";
  protectedGpuVendor = "0x10de";
  protectedGpuDevice = "0x2204";
  protectedAudioVendor = "0x10de";
  protectedAudioDevice = "0x1aef";
  protectedIommuGroup = "27";
  nvidiaSmi = "${config.hardware.nvidia.package.bin}/bin/nvidia-smi";
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

  # Incus VFIO preflight guard. The lock and owner marker protect against
  # concurrent starts while Incus moves the 3060 Ti between host driver and VFIO.
  handoffScript = pkgs.writeShellScript "gamepass-vfio-handoff" ''
    set -euo pipefail

    exec 9>/run/lock/gamepass-vfio.lock
    ${pkgs.util-linux}/bin/flock -x 9
    mode="''${1:-}"
    owner_file=/run/gamepass-vfio/owner
    state_file=/run/gamepass-vfio/original-drivers
    protected_state_file=/run/gamepass-vfio/protected-drivers
    devices=("${vfioGpu}" "${vfioAudio}")
    protected_devices=("${protectedGpu}" "${protectedAudio}")

    driver_for() {
      local dev="$1"
      if [ -L "/sys/bus/pci/devices/$dev/driver" ]; then
        ${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/readlink "/sys/bus/pci/devices/$dev/driver")"
      else
        echo none
      fi
    }

    validate_identity() {
      local dev vendor device group gpu_group audio_group
      for dev in "''${devices[@]}"; do
        test -e "/sys/bus/pci/devices/$dev" || {
          echo "Required passthrough function is missing: $dev" >&2
          return 1
        }
        vendor=$(cat "/sys/bus/pci/devices/$dev/vendor")
        device=$(cat "/sys/bus/pci/devices/$dev/device")
        case "$dev" in
          "${vfioGpu}")
            [ "$vendor" = "${vfioGpuVendor}" ] && [ "$device" = "${vfioGpuDevice}" ] || {
              echo "Unexpected GPU identity at $dev: $vendor:$device (expected ${vfioGpuVendor}:${vfioGpuDevice})" >&2
              return 1
            }
            ;;
          "${vfioAudio}")
            [ "$vendor" = "${vfioAudioVendor}" ] && [ "$device" = "${vfioAudioDevice}" ] || {
              echo "Unexpected audio identity at $dev: $vendor:$device (expected ${vfioAudioVendor}:${vfioAudioDevice})" >&2
              return 1
            }
            ;;
        esac
      done
      gpu_group=$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/readlink -f "/sys/bus/pci/devices/${vfioGpu}/iommu_group")")
      audio_group=$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/readlink -f "/sys/bus/pci/devices/${vfioAudio}/iommu_group")")
      [ "$gpu_group" = "${vfioIommuGroup}" ] && [ "$audio_group" = "$gpu_group" ] || {
        echo "Unexpected IOMMU groups: ${vfioGpu}=$gpu_group ${vfioAudio}=$audio_group (expected shared group ${vfioIommuGroup})" >&2
        return 1
      }
      group_members=$(${pkgs.findutils}/bin/find "/sys/kernel/iommu_groups/${vfioIommuGroup}/devices" -mindepth 1 -maxdepth 1 -type l -printf '%f\\n' | ${pkgs.coreutils}/bin/sort)
      expected_members=$(printf '%s\\n' "${vfioGpu}" "${vfioAudio}" | ${pkgs.coreutils}/bin/sort)
      [ "$group_members" = "$expected_members" ] || {
        echo "Refusing handoff: IOMMU group ${vfioIommuGroup} contains unexpected members:" >&2
        printf '%s\\n' "$group_members" >&2
        return 1
      }
      for dev in "''${protected_devices[@]}"; do
        test -e "/sys/bus/pci/devices/$dev" || {
          echo "Protected RTX 3090 function is missing: $dev" >&2
          return 1
        }
        vendor=$(cat "/sys/bus/pci/devices/$dev/vendor")
        device=$(cat "/sys/bus/pci/devices/$dev/device")
        case "$dev" in
          "${protectedGpu}")
            [ "$vendor" = "${protectedGpuVendor}" ] && [ "$device" = "${protectedGpuDevice}" ] || {
              echo "Unexpected protected GPU identity at $dev: $vendor:$device (expected ${protectedGpuVendor}:${protectedGpuDevice})" >&2
              return 1
            }
            ;;
          "${protectedAudio}")
            [ "$vendor" = "${protectedAudioVendor}" ] && [ "$device" = "${protectedAudioDevice}" ] || {
              echo "Unexpected protected audio identity at $dev: $vendor:$device (expected ${protectedAudioVendor}:${protectedAudioDevice})" >&2
              return 1
            }
            ;;
        esac
        case "$dev:$(driver_for "$dev")" in
          "${protectedGpu}:nvidia"|"${protectedAudio}:snd_hda_intel") ;;
          *)
            echo "Refusing handoff: protected RTX 3090 function has unexpected driver: $dev=$(driver_for "$dev")" >&2
            return 1
            ;;
        esac
        protected_group=$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/readlink -f "/sys/bus/pci/devices/$dev/iommu_group")")
        [ "$protected_group" = "${protectedIommuGroup}" ] || {
          echo "Unexpected protected RTX 3090 IOMMU group for $dev: $protected_group (expected ${protectedIommuGroup})" >&2
          return 1
        }
      done
    }

    capture_driver_state() {
      : > "$state_file"
      : > "$protected_state_file"
      local dev
      for dev in "''${devices[@]}"; do
        printf '%s %s\\n' "$dev" "$(driver_for "$dev")" >> "$state_file"
      done
      for dev in "''${protected_devices[@]}"; do
        printf '%s %s\\n' "$dev" "$(driver_for "$dev")" >> "$protected_state_file"
      done
    }

    verify_protected_state() {
      local dev expected actual
      while read -r dev expected; do
        actual=$(driver_for "$dev")
        [ "$actual" = "$expected" ] && [ "$actual" != "vfio-pci" ] || {
          echo "Protected RTX 3090 driver changed for $dev: was $expected, now $actual" >&2
          return 1
        }
      done < "$protected_state_file"
    }

    verify_original_state() {
      local dev expected actual
      while read -r dev expected; do
        actual=$(driver_for "$dev")
        [ "$actual" = "$expected" ] || {
          echo "3060 Ti rollback incomplete for $dev: was $expected, now $actual" >&2
          return 1
        }
      done < "$state_file"
    }

    claim() {
      local backend="$1"
      mkdir -p /run/gamepass-vfio
      if [ -s "$owner_file" ] && [ "$(cat "$owner_file")" != "$backend" ]; then
        echo "3060 Ti is already owned by $(cat "$owner_file")" >&2
        exit 1
      fi

      if [ "$backend" != incus ]; then
        echo "Unsupported VFIO backend: $backend (Incus is the only backend)" >&2
        exit 2
      fi

      validate_identity
      capture_driver_state
      while read -r dev original_driver; do
        case "$dev:$original_driver" in
          "${vfioGpu}:nvidia"|"${vfioAudio}:snd_hda_intel") ;;
          *)
            echo "Refusing handoff from unexpected host driver: $dev=$original_driver" >&2
            exit 1
            ;;
        esac
      done < "$state_file"

      # Incus performs the actual vfio-pci bind and records its own
      # last_state.pci.driver for restoration. The host guard is deliberately
      # preflight-only: it must not bind/unbind the same functions behind
      # Incus's back. If a later check fails, discard only our state marker;
      # no host driver transition has occurred yet.
      trap 'rc=$?; trap - EXIT; if [ "$rc" -ne 0 ]; then rm -f "$owner_file" "$state_file" "$protected_state_file"; fi; exit "$rc"' EXIT

      # Stop only the workloads known to use this card. The RTX 3090 services
      # are not touched. A successful stop command is not enough: refuse the
      # handoff if either workload remains active.
      for unit in peakminer-zephyr-3060ti.service bonsai-1bit-zephyr.service; do
        systemctl stop "$unit" 2>/dev/null || true
        if systemctl is-active --quiet "$unit" 2>/dev/null; then
          echo "Refusing VFIO handoff: workload remains active: $unit" >&2
          exit 1
        fi
      done

      if ! gpu_rows=$(${nvidiaSmi} --query-gpu=pci.bus_id,uuid --format=csv,noheader,nounits 2>/dev/null); then
        echo "Refusing VFIO handoff: cannot query GPU identities from ${nvidiaSmi}" >&2
        exit 1
      fi
      target_matches=$(printf '%s\\n' "$gpu_rows" | ${pkgs.gawk}/bin/awk -F', ' '$1 ~ /24:00\\.0$/ && $2 ~ /^GPU-[[:alnum:]-]+$/ {count += 1; uuid = $2} END {print count, uuid}')
      read -r target_match_count target_uuid <<EOF
$target_matches
EOF
      [ "$target_match_count" = 1 ] && [ -n "$target_uuid" ] || {
        echo "Refusing VFIO handoff: expected exactly one valid RTX 3060 Ti identity row, got: $target_matches" >&2
        exit 1
      }
      if ! compute_rows=$(${nvidiaSmi} --query-compute-apps=gpu_uuid,pid,process_name --format=csv,noheader,nounits 2>/dev/null); then
        echo "Refusing VFIO handoff: cannot query CUDA clients from ${nvidiaSmi}" >&2
        exit 1
      fi
      target_clients=$(printf '%s\\n' "$compute_rows" | ${pkgs.gawk}/bin/awk -F', ' -v uuid="$target_uuid" '$1 == uuid {print}')
      [ -z "$target_clients" ] || {
        echo "Refusing VFIO handoff: unexpected CUDA clients still use the RTX 3060 Ti:" >&2
        printf '%s\\n' "$target_clients" >&2
        exit 1
      }
      pmon_output=""
      if ! pmon_output=$(${nvidiaSmi} pmon -i 00000000:24:00.0 -c 1 2>/dev/null); then
        echo "Refusing VFIO handoff: nvidia-smi pmon failed for the RTX 3060 Ti" >&2
        exit 1
      fi
      printf '%s\\n' "$pmon_output" | ${pkgs.gnugrep}/bin/grep -Eq 'gpu[[:space:]]+pid' || {
        echo "Refusing VFIO handoff: nvidia-smi pmon returned an unrecognized sample" >&2
        exit 1
      }
      target_graphics=$(printf '%s\\n' "$pmon_output" | ${pkgs.gawk}/bin/awk '$2 ~ /^[0-9]+$/ {print}')
      [ -z "$target_graphics" ] || {
        echo "Refusing VFIO handoff: graphics/compute clients still use the RTX 3060 Ti:" >&2
        printf '%s\\n' "$target_graphics" >&2
        exit 1
      }

      # Incus now owns the transition. It loads vfio-pci, applies the IOMMU
      # group override, and restores the recorded host drivers after stop.
      # Keep this marker until ExecStopPost verifies that Incus restored them.
      printf '%s\\n' "$backend" > "$owner_file"
      trap - EXIT
    }

    release() {
      local backend="''${1:-}"
      if [ ! -s "$owner_file" ]; then
        echo "No active Incus GPU ownership; refusing to touch PCI drivers"
        return 0
      fi
      if [ -n "$backend" ] && [ "$(cat "$owner_file")" != "$backend" ]; then
        echo "Not releasing GPU owned by $(cat "$owner_file")" >&2
        exit 1
      fi
      [ -s "$state_file" ] && [ -s "$protected_state_file" ] || {
        echo "VFIO state files are incomplete; refusing to release the GPU" >&2
        exit 1
      }

      vm_state=$(${incus}/bin/incus info ${lib.escapeShellArg incusVm} --format csv -c status 2>/dev/null || echo unknown)
      [ "$vm_state" = STOPPED ] || {
        echo "Refusing to release VFIO while ${incusVm} is not stopped (state: $vm_state)" >&2
        exit 1
      }
      # Incus owns VFIO unbind/rebind in its post-stop hook. The host guard
      # only verifies that Incus restored the exact drivers captured above;
      # it never races Incus by writing to the PCI driver sysfs itself.
      if ! verify_original_state; then
        echo "Incus did not restore the 3060 Ti host drivers; refusing to clear ownership state" >&2
        return 1
      fi
      verify_protected_state
      rm -f "$owner_file" "$state_file" "$protected_state_file"
    }

    case "$mode" in
      pre-incus) claim incus ;;
      post) release "''${2:-}" ;;
      *) echo "Usage: $0 {pre-incus|post [owner]}" >&2; exit 2 ;;
    esac
  '';

  gamepassVm = pkgs.writeShellScriptBin "incus-gamepass-vm" ''
    set -euo pipefail

    incus=${incus}/bin/incus
    vm=${lib.escapeShellArg incusVm}
    pool=${lib.escapeShellArg storagePool}
    source_root=${lib.escapeShellArg storageRoot}
    orphan_pool_dir=${lib.escapeShellArg "/var/lib/incus/storage-pools/gamepass"}
    iso=${lib.escapeShellArg "/var/lib/incus-gamepass/win11.iso"}
    virtio_iso=${lib.escapeShellArg "${virtioWinIso}/virtio-win.iso"}

    usage() {
      cat >&2 <<'EOF'
Usage:
  incus-gamepass-vm reconcile      Inspect Incus pool/source drift (read-only)
  incus-gamepass-vm create         Create the dormant Incus VM and import ISOs
  incus-gamepass-vm start           Start Incus VM through the ownership guard
  incus-gamepass-vm stop            Stop Incus VM through the ownership guard
  incus-gamepass-vm status          Show both backend states
  incus-gamepass-vm check-looking-glass  Verify host KVMFR access
EOF
      exit 2
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

    reconcile_storage() {
      local registered source_value
      if ! registered=$($incus storage list -f csv -c n 2>/dev/null); then
        echo "ERROR: unable to query Incus storage pools; refusing reconciliation" >&2
        exit 1
      fi
      if printf '%s\\n' "$registered" | ${pkgs.gnugrep}/bin/grep -Fxq "$pool"; then
        source_value=$($incus storage get "$pool" source 2>/dev/null || true)
        if [ "$source_value" = "$source_root" ]; then
          echo "OK: Incus pool '$pool' is registered with source '$source_root'"
          exit 0
        fi
        echo "ERROR: Incus pool '$pool' has unexpected source '$source_value' (expected '$source_root')" >&2
        exit 1
      fi
      if [ -e "$orphan_pool_dir" ]; then
        echo "BLOCKED: unregistered Incus storage directory exists: $orphan_pool_dir" >&2
        echo "Inventory it before any preseed or cleanup; no automatic deletion is performed." >&2
        exit 2
      fi
      if [ -d "$source_root" ] && [ -n "$(${pkgs.findutils}/bin/find "$source_root" -mindepth 1 -print -quit 2>/dev/null)" ]; then
        echo "BLOCKED: expected source directory is non-empty but pool '$pool' is unregistered: $source_root" >&2
        echo "Confirm ownership and backup state before registering or migrating it." >&2
        exit 2
      fi
      echo "READY: no registered '$pool' pool or orphan state detected; preseed may initialize '$source_root'"
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
      reconcile)
        reconcile_storage
        ;;
      start)
        exec systemctl start gamepass-incus-vm.service
        ;;
      stop)
        exec systemctl stop gamepass-incus-vm.service
        ;;
      status)
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

  vmStartScript = pkgs.writeShellScript "gamepass-incus-start" ''
    set -euo pipefail
    rc=0
    ${incus}/bin/incus start ${lib.escapeShellArg incusVm} || rc=$?
    [ "$rc" -eq 0 ] && exit 0
    state=$(${incus}/bin/incus info ${lib.escapeShellArg incusVm} --format csv -c status 2>/dev/null || echo unknown)
    if [ "$state" = STOPPED ]; then
      echo "Incus start failed after VFIO claim; checking Incus driver restoration" >&2
      if ! ${handoffScript} post incus; then
        echo "CRITICAL: Incus did not restore the 3060 Ti; inspect /run/gamepass-vfio and journal immediately" >&2
      fi
    else
      echo "CRITICAL: Incus start failed and VM state is '$state'; refusing automatic GPU release" >&2
      echo "Confirm the VM is stopped before running: ${handoffScript} post incus" >&2
    fi
    exit "$rc"
  '';

in {
  config = lib.mkIf (config.networking.hostName == "zephyr") {
    # Incus-only host prerequisites. The 3060 Ti remains on the host driver
    # until gamepass-incus-vm.service performs the guarded handoff; the 3090
    # is never detached or passed through.
    boot.initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
    boot.kernelModules = [ "kvmfr" ];
    boot.kernelParams = [ "kvmfr.static_size_mb=64" ];
    boot.extraModulePackages = [
      (vfioPkgs.linuxPackagesFor config.boot.kernelPackages.kernel).kvmfr
    ];
    services.udev.packages = lib.singleton (pkgs.writeTextFile {
      name = "kvmfr-udev";
      text = ''SUBSYSTEM=="kvmfr", GROUP="kvm", MODE="0660", TAG+="uaccess"'';
      destination = "/etc/udev/rules.d/70-kvmfr.rules";
    });
    users.users.j_kro.extraGroups = [ "incus" "incus-admin" "kvm" ];

    virtualisation.incus = {
      enable = true;
      # Incus owns its own bridge and storage pool. Preseed is idempotent and
      # does not remove existing entities.
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
              # using the host kvmfr module declared above.
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
              # Incus' VM GPU device type models a whole physical GPU and
              # lets Incus/QEMU apply its PCI passthrough lifecycle. The
              # companion HDMI-audio function remains a raw PCI device.
              gpu = {
                type = "gpu";
                gputype = "physical";
                pci = vfioGpu;
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

    # Idempotent preseed (re-deploy safe).
    # The nixpkgs-generated incus-preseed.service runs `incus admin init
    # --preseed` unconditionally. On a 2nd activation the gamepass storage
    # pool directory persists from the prior generation, so init errors with
    # "Storage pool directory ... already exists" and ABORTS the whole
    # activation. Guard it: if the pool is already known to incus, skip the
    # preseed. The dormant VM is still created later by the operator via
    # incus-gamepass-vm.
    systemd.services.incus-preseed = {
      serviceConfig = {
        ExecStart = lib.mkForce [
          (pkgs.writeShellScript "incus-preseed-guarded" ''
            set -euo pipefail
            # Incus 7 exposes registered pools via `storage list`; the old
            # `storage pool list` spelling always failed and made every
            # activation fall through to a second init attempt.
            if ! registered=$(${incus}/bin/incus storage list -f csv -c n 2>/dev/null); then
              echo "ERROR: unable to query Incus storage pools; refusing preseed" >&2
              exit 1
            fi
            if printf '%s\\n' "$registered" | ${pkgs.gnugrep}/bin/grep -Fxq gamepass; then
              driver=$(${incus}/bin/incus storage show gamepass --format yaml 2>/dev/null | ${pkgs.gnused}/bin/sed -n 's/^driver: *//p' | ${pkgs.coreutils}/bin/head -n 1)
              source=$(${incus}/bin/incus storage get gamepass source 2>/dev/null || true)
              if [ "$driver" = "dir" ] && [ "$source" = "${storageRoot}" ]; then
                echo "incus gamepass pool already present with expected driver/source; skipping preseed"
                exit 0
              fi
              echo "ERROR: registered gamepass pool has unexpected driver/source '$driver'/'$source' (expected 'dir'/'${storageRoot}')" >&2
              exit 1
            fi
            if [ -e "/var/lib/incus/storage-pools/gamepass" ]; then
              echo "ERROR: unregistered Incus storage directory exists at /var/lib/incus/storage-pools/gamepass" >&2
              echo "Inventory and reconcile it before activation; refusing to delete or overwrite VM state." >&2
              exit 1
            fi
            if [ -d "${storageRoot}" ] && [ -n "$(${pkgs.findutils}/bin/find "${storageRoot}" -mindepth 1 -print -quit 2>/dev/null)" ]; then
              echo "ERROR: expected Incus source ${storageRoot} is non-empty but gamepass is unregistered" >&2
              echo "Confirm ownership and backup state before registering or migrating it." >&2
              exit 1
            fi
            if ! existing_storage=$(${incus}/bin/incus storage list -f csv -c n 2>/dev/null); then
              echo "ERROR: unable to query Incus storage resources; refusing preseed" >&2
              exit 1
            fi
            if ! existing_profiles=$(${incus}/bin/incus profile list -f csv -c n 2>/dev/null); then
              echo "ERROR: unable to query Incus profiles; refusing preseed" >&2
              exit 1
            fi
            unexpected_storage=$(printf '%s\\n' "$existing_storage" | ${pkgs.gnugrep}/bin/grep -vFx gamepass | ${pkgs.gnugrep}/bin/grep -v '^$' || true)
            unexpected_profiles=$(printf '%s\\n' "$existing_profiles" | ${pkgs.gnugrep}/bin/grep -vFx default | ${pkgs.gnugrep}/bin/grep -v '^$' || true)
            if [ -n "$unexpected_storage" ] || [ -n "$unexpected_profiles" ]; then
              echo "ERROR: Incus has existing resources but the Game Pass pool/profile is incomplete" >&2
              echo "Storage resources: ''${unexpected_storage:-none}" >&2
              echo "Non-default profiles: ''${unexpected_profiles:-none}" >&2
              echo "Refusing to re-run admin init; use incus-gamepass-vm reconcile and complete an explicit operator-approved registration." >&2
              exit 1
            fi
            if ! existing_networks=$(${incus}/bin/incus network list -f csv -c n 2>/dev/null); then
              echo "ERROR: unable to query Incus networks; refusing preseed" >&2
              exit 1
            fi
            if printf '%s\\n' "$existing_networks" | ${pkgs.gnugrep}/bin/grep -Fxq '${incusNetwork}'; then
              echo "ERROR: Incus already has network '${incusNetwork}' but no registered Game Pass pool/profile" >&2
              echo "Refusing to re-run admin init against a partially initialized daemon; use incus-gamepass-vm reconcile." >&2
              exit 1
            fi
            exec ${incus}/bin/incus admin init --preseed < ${pkgs.writeText "incus-gamepass-preseed.yaml" (lib.generators.toYAML {} config.virtualisation.incus.preseed)}
          '')
        ];
      };
    };

    # Incus delegates its cgroup to the QEMU VM process. Give that service
    # access to the KVMFR character device used by the Incus QEMU VM. This is
    # intentionally narrower than a blanket device policy.
    systemd.services.incus.serviceConfig = {
      SupplementaryGroups = [ "kvm" ];
      DeviceAllow = [ "/dev/kvmfr0 rw" ];
    };

    systemd.tmpfiles.rules = [
      "d ${storageRoot} 0750 root root -"
    ];

    environment.systemPackages = [ gamepassVm lookingGlassLauncher pkgs.squashfsTools ];

    # The Incus VM is manual-only and never autostarts. Direct `incus` commands
    # can bypass this wrapper; normal operations should use incus-gamepass-vm.
    systemd.services.gamepass-incus-vm = {
      description = "Dormant Incus-only Game Pass Windows VM";
      after = [ "incus.service" "incus-preseed.service" ];
      wants = [ "incus-preseed.service" ];
      requires = [ "incus-preseed.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = [
          lookingGlassCheck
          "${handoffScript} pre-incus"
        ];
        ExecStart = vmStartScript;
        ExecStop = vmStopScript;
        ExecStopPost = "${handoffScript} post incus";
        TimeoutStartSec = "infinity";
        TimeoutStopSec = 120;
      };
    };
  };
}
