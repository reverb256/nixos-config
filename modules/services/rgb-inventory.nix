{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.rgb-inventory;
  inherit (config.lib.stylix.colors) base00 base05 base08 base09 base0B base0D base0E;
  textfileDir = "/var/lib/prometheus/node-exporter/textfile-collector";
  stateDir = "/var/lib/rgb-inventory";

  inventory = import ../../contracts/rgb-inventory.nix;
  hostName = config.networking.hostName;
  hostInventory =
    inventory.hosts.${
      hostName
    } or {
      expected = [];
      controlDevices = [];
    };

  json = pkgs.writeText "rgb-inventory-${hostName}.json" (builtins.toJSON {
    inherit (inventory) schemaVersion;
    inherit (inventory) interfaceVersion;
    inherit hostName;
    inherit (hostInventory) expected;
    inherit (hostInventory) controlDevices;
  });

  paletteJson = pkgs.writeText "stylix-rgb-palette-${hostName}.json" (builtins.toJSON {
    source = "stylix.base16";
    inherit base00 base05 base08 base09 base0B base0D base0E;
    roles = {
      primary = base0D;
      secondary = base0E;
      cool = base0B;
      warning = base09;
      critical = base08;
      neutral = base05;
      off = base00;
    };
  });

  expectedLines =
    lib.concatMapStringsSep "\n" (device: ''
      rgb_inventory_expected_info{host="${hostName}",backend="${device.backend}",device_kind="${device.kind}",device_hint="${device.hint}"} 1
      rgb_inventory_control_allowed{host="${hostName}",backend="${device.backend}",device_kind="${device.kind}",device_hint="${device.hint}"} ${
        if device.controlAllowed
        then "1"
        else "0"
      }
      rgb_inventory_expected_count{host="${hostName}",backend="${device.backend}",device_kind="${device.kind}",device_hint="${device.hint}"} ${toString device.expectedCount}
    '')
    hostInventory.expected;

  reportScript = pkgs.writeShellScript "rgb-inventory" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        PATH=${lib.makeBinPath (with pkgs; [bash coreutils findutils gnugrep gnused openrgb pciutils systemd])}:$PATH

        report=${stateDir}/report.json
        metrics=${textfileDir}/rgb_inventory.prom
        hostName=${hostName}
        tmp=$(mktemp "''${report}.XXXXXX")
        metrics_tmp=$(mktemp "''${metrics}.XXXXXX")
        trap 'rm -f "$tmp" "$metrics_tmp"' EXIT
        mkdir -p ${stateDir} ${textfileDir}

        openrgb_available=0
        openrgb_active=0
        if command -v openrgb >/dev/null 2>&1; then
          openrgb_available=1
          if systemctl is-active --quiet openrgb.service 2>/dev/null; then
            openrgb_active=1
          fi
        fi
        openrazer_available=0
        if command -v razer-cli >/dev/null 2>&1 || systemctl is-active --quiet openrazer-daemon.service 2>/dev/null; then
          openrazer_available=1
        fi
        # `razer-cli --list-devices` is not a stable read-only interface across
        # OpenRazer versions. Keep backend availability visible, but do not claim
        # device discovery until a version-specific enumerator is verified.
        openrazer_devices=""
        liquidctl_available=0
        command -v liquidctl >/dev/null 2>&1 && liquidctl_available=1
        if pci_output=$(lspci 2>/dev/null); then
          pci_gpu_count=$(printf '%s\n' "$pci_output" | grep -Eic 'VGA compatible controller|3D controller|Display controller' || true)
        else
          pci_gpu_count=0
          pci_output=""
        fi
        drm_gpu_count=$(find /sys/class/drm -maxdepth 1 -type l -name 'card[0-9]*' 2>/dev/null | wc -l)
        scan_success=1
        if [[ -z "$pci_output" ]]; then
          scan_success=0
        fi

        # Discovery only. Never invoke OpenRGB profiles, device writes, initialize,
        # PWM, fan, or controller setup operations here.
        openrgb_devices=""
        if (( openrgb_available )); then
          openrgb_devices=$(openrgb --client 127.0.0.1:6742 --list-devices 2>/dev/null || true)
        fi

        if (( openrgb_available )) && [[ -z "$openrgb_devices" ]]; then
          # An installed backend with no response is a failed discovery, not a
          # healthy empty inventory. Hosts without OpenRGB remain valid scans.
          scan_success=0
        fi

        cat > "$tmp" <<JSON
    {
      "schemaVersion": ${toString inventory.schemaVersion},
      "interfaceVersion": "${inventory.interfaceVersion}",
      "host": "${hostName}",
      "openrgbAvailable": $openrgb_available,
      "openrgbActive": $openrgb_active,
      "openrazerAvailable": $openrazer_available,
      "liquidctlAvailable": $liquidctl_available,
      "pciGpuCount": $pci_gpu_count,
      "drmGpuCount": $drm_gpu_count,
      "openrgbDevices": $(printf '%s' "$openrgb_devices" | ${pkgs.jq}/bin/jq -Rs .),
      "openrazerDevices": $(printf '%s' "$openrazer_devices" | ${pkgs.jq}/bin/jq -Rs .),
      "expected": $(cat ${json} | ${pkgs.jq}/bin/jq -c .expected),
      "controlDevices": $(cat ${json} | ${pkgs.jq}/bin/jq -c .controlDevices)
    }
    JSON
        mv -f "$tmp" "$report"

        cat > "$metrics_tmp" <<METRICS
    # HELP rgb_inventory_expected_info Expected RGB-capable device from the declarative contract.
    # TYPE rgb_inventory_expected_info gauge
    # HELP rgb_inventory_control_allowed Whether the device is explicitly approved for RGB writes.
    # TYPE rgb_inventory_control_allowed gauge
    # HELP rgb_inventory_expected_count Number of devices expected for the identity group.
    # TYPE rgb_inventory_expected_count gauge
    # HELP rgb_inventory_detected_count Number of devices observed for the identity group.
    # TYPE rgb_inventory_detected_count gauge
    # HELP rgb_inventory_detected Whether the expected device hint matched runtime discovery.
    # TYPE rgb_inventory_detected gauge
    # HELP rgb_inventory_visibility_gap Whether an expected device was not detected.
    # TYPE rgb_inventory_visibility_gap gauge
    # HELP rgb_inventory_backend_available Whether an RGB backend command is available.
    # TYPE rgb_inventory_backend_available gauge
    rgb_inventory_backend_available{host="${hostName}",backend="openrgb"} $openrgb_available
    rgb_inventory_backend_available{host="${hostName}",backend="openrazer"} $openrazer_available
    rgb_inventory_backend_available{host="${hostName}",backend="liquidctl"} $liquidctl_available
    # HELP rgb_inventory_backend_active Whether the native backend service is active.
    # TYPE rgb_inventory_backend_active gauge
    rgb_inventory_backend_active{host="${hostName}",backend="openrgb"} $openrgb_active
    # HELP rgb_inventory_pci_gpu_count Number of visible PCI display/GPU controllers.
    # TYPE rgb_inventory_pci_gpu_count gauge
    rgb_inventory_pci_gpu_count{host="${hostName}"} $pci_gpu_count
    # HELP rgb_inventory_drm_gpu_count Number of visible DRM GPU cards.
    # TYPE rgb_inventory_drm_gpu_count gauge
    rgb_inventory_drm_gpu_count{host="${hostName}"} $drm_gpu_count
    # HELP rgb_inventory_scan_success Whether the read-only inventory scan completed.
    # TYPE rgb_inventory_scan_success gauge
    rgb_inventory_scan_success{host="${hostName}"} $scan_success
    # HELP rgb_inventory_scan_timestamp_seconds Unix timestamp of the scan.
    # TYPE rgb_inventory_scan_timestamp_seconds gauge
    rgb_inventory_scan_timestamp_seconds{host="${hostName}"} $(date +%s)
    ${expectedLines}
    METRICS

        # Derive per-device detection from the read-only OpenRGB listing. This
        # intentionally reports ambiguity as a gap and never selects a device.
        while IFS= read -r entry; do
          hint=$(${pkgs.jq}/bin/jq -r .hint <<< "$entry")
          backend=$(${pkgs.jq}/bin/jq -r .backend <<< "$entry")
          kind=$(${pkgs.jq}/bin/jq -r .kind <<< "$entry")
          if [[ "$backend" == "openrgb" ]]; then
            # grep returns 1 on no match; under `set -euo pipefail` that aborts the
            # whole script mid-loop (missing hint => missing metric => exit 1).
            # Absorb the no-match exit so a visibility gap is recorded, not fatal.
            count=$(printf '%s\n' "$openrgb_devices" | grep -iF "$hint" | wc -l || true)
          elif [[ "$backend" == "openrazer" ]]; then
            count=$(printf '%s\n' "$openrazer_devices" | grep -iF "$hint" | wc -l || true)
          elif [[ "$backend" == "drm" ]]; then
            count=$drm_gpu_count
          elif [[ "$backend" == "pci" ]]; then
            count=$pci_gpu_count
          else
            count=0
          fi
          expected_count=$(${pkgs.jq}/bin/jq -r .expectedCount <<< "$entry")
          if (( count >= expected_count )); then detected=1; gap=0; else detected=0; gap=1; fi
          printf 'rgb_inventory_detected{host="%s",backend="%s",device_kind="%s",device_hint="%s"} %s\n' "$hostName" "$backend" "$kind" "$hint" "$detected" >> "$metrics_tmp"
          printf 'rgb_inventory_visibility_gap{host="%s",backend="%s",device_kind="%s",device_hint="%s"} %s\n' "$hostName" "$backend" "$kind" "$hint" "$gap" >> "$metrics_tmp"
          printf 'rgb_inventory_detected_count{host="%s",backend="%s",device_kind="%s",device_hint="%s"} %s\n' "$hostName" "$backend" "$kind" "$hint" "$count" >> "$metrics_tmp"
        done < <(${pkgs.jq}/bin/jq -c '.expected[]' ${json})
        mv -f "$metrics_tmp" "$metrics"
        printf '%s\n' "$report"
  '';

  controlAllowlist =
    pkgs.writeText "rgb-control-allowlist-${hostName}.json"
    (builtins.toJSON cfg.controlDevices);

  stylixSyncScript = pkgs.writeShellScript "rgb-stylix-sync" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    PATH=${lib.makeBinPath (with pkgs; [bash coreutils gnugrep gnused jq openrgb systemd])}:$PATH
    palette=${paletteJson}
    allowlist=${controlAllowlist}

    # Empty is the intentional fleet default. There is no numeric-index
    # fallback: a missing/ambiguous identity is always skipped.
    if [[ "$(${pkgs.jq}/bin/jq 'length' "$allowlist")" == 0 ]]; then
      echo "${hostName}: Stylix RGB sync skipped; control allowlist is empty"
      exit 0
    fi

    if ! systemctl is-active --quiet openrgb.service; then
      echo "${hostName}: Stylix RGB sync skipped; OpenRGB service is inactive" >&2
      exit 0
    fi

    devices=$(openrgb --client 127.0.0.1:6742 --list-devices 2>/dev/null || true)
    if [[ -z "$devices" ]]; then
      echo "${hostName}: Stylix RGB sync skipped; OpenRGB returned no devices" >&2
      exit 0
    fi

    # Resolve the transient CLI index only after matching the stable declared
    # name hint. This is the only place an observed index may be used.
    while IFS= read -r entry; do
      hint=$(${pkgs.jq}/bin/jq -r .hint <<< "$entry")
      role=$(${pkgs.jq}/bin/jq -r .role <<< "$entry")
      color=$(${pkgs.jq}/bin/jq -r --arg role "$role" '.roles[$role] // empty' "$palette")
      if [[ ! "$color" =~ ^[0-9A-Fa-f]{6}$ ]]; then
        echo "${hostName}: invalid or missing Stylix role '$role' for '$hint'" >&2
        continue
      fi

      matches=$(printf '%s\n' "$devices" | grep -iF "$hint" | sed -nE 's/^[[:space:]]*([0-9]+):.*/\1/p' || true)
      count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l)
      match_all=$(${pkgs.jq}/bin/jq -r .matchAll <<< "$entry")
      if (( count == 0 )); then
        echo "${hostName}: expected OpenRGB device matching '$hint'; found none" >&2
        continue
      fi
      if (( count != 1 )) && [[ "$match_all" != true ]]; then
        echo "${hostName}: expected exactly one OpenRGB device matching '$hint'; found $count" >&2
        continue
      fi
      if [[ "$match_all" == true ]]; then
        while IFS= read -r device; do
          openrgb --client 127.0.0.1:6742 -d "$device" -m Direct -c "$color" 2>/dev/null || \
            echo "${hostName}: OpenRGB write failed for '$hint' index $device" >&2
          sleep 1
        done <<< "$matches"
      else
        device=$(printf '%s\n' "$matches" | head -1)
        openrgb --client 127.0.0.1:6742 -d "$device" -m Direct -c "$color" 2>/dev/null || \
          echo "${hostName}: OpenRGB write failed for '$hint'" >&2
        sleep 1
      fi
    done < <(${pkgs.jq}/bin/jq -c '.[]' "$allowlist")
  '';
in {
  options.services.rgb-inventory = {
    enable = lib.mkEnableOption "read-only RGB inventory and Stylix palette reporting";
    stylixSync.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable explicit Stylix-to-RGB synchronization after stable identities are approved.";
    };
    controlDevices = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          hint = lib.mkOption {type = lib.types.str;};
          role = lib.mkOption {
            type = lib.types.enum ["primary" "secondary" "cool" "warning" "critical" "neutral" "off"];
          };
          matchAll = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Allow a verified repeated device name to match all occurrences.";
          };
        };
      });
      default = hostInventory.controlDevices;
      description = ''
        Stable OpenRGB name hints explicitly allowed to receive Stylix colors.
        Empty is the safe default; numeric device indices are not accepted.
      '';
    };
    interval = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "Inventory refresh interval in seconds.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "rgb-inventory" ''
        exec ${reportScript}
      '')
      (pkgs.writeShellScriptBin "rgb-stylix-palette" ''
        cat ${paletteJson}
      '')
    ];

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 root root -"
      "d ${textfileDir} 0755 root root -"
    ];

    systemd.services.rgb-inventory = {
      description = "Read-only RGB hardware inventory and metrics";
      after = ["network-online.target" "prometheus-node-exporter.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = reportScript;
        ReadWritePaths = [stateDir textfileDir];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET"];
      };
    };

    systemd.timers.rgb-inventory = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "${toString cfg.interval}s";
        Persistent = true;
      };
    };

    systemd.services.rgb-stylix-sync = lib.mkIf cfg.stylixSync.enable {
      description = "Apply the approved Stylix RGB palette";
      after = ["openrgb.service" "rgb-inventory.service"];
      wants = ["openrgb.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = stylixSyncScript;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET"];
      };
    };

    systemd.timers.rgb-stylix-sync = lib.mkIf cfg.stylixSync.enable {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "45s";
        OnUnitActiveSec = "${toString cfg.interval}s";
        Persistent = true;
      };
    };
  };
}
