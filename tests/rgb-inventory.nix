{pkgs, ...}: let
  inherit (pkgs) lib;
  contract = import ../contracts/rgb-inventory.nix;
  moduleSource = builtins.readFile ../modules/services/rgb-inventory.nix;
  rgbSource = builtins.readFile ../modules/hardware/rgb-control.nix;
  hostNames = builtins.attrNames contract.hosts;
  expectedHosts = ["forge" "nexus" "sentry" "zephyr"];
  allExpectedDevicesHaveRequiredFields =
    builtins.all
    (host:
      builtins.all
      (device:
        builtins.all (field: builtins.hasAttr field device) [
          "id"
          "kind"
          "backend"
          "hint"
          "expectedCount"
          "capability"
          "controlAllowed"
          "status"
        ])
      contract.hosts.${host}.expected)
    hostNames; # All four hosts now have OpenRGB-verified control devices: zephyr (7)
  # and nexus (2) were the original control-capable hosts; forge gained the
  # Sapphire RX 5700 XT (Nitro Glow V3 via AMDGPU DM i2c) and sentry the
  # Corsair Scimitar Pro RGB (PID 0x1B3E) in the 2026-08-16 scan. The
  # invariant to enforce is documentation completeness + allowlist safety,
  # not a host allowlist.
  controlListPolicy =
    contract.hosts.zephyr.controlDevices
    != []
    && contract.hosts.nexus.controlDevices != []
    && contract.hosts.forge.controlDevices != []
    && contract.hosts.sentry.controlDevices != []
    && builtins.all
    (device: builtins.hasAttr "matchAll" device)
    (contract.hosts.zephyr.controlDevices
      ++ contract.hosts.nexus.controlDevices
      ++ contract.hosts.forge.controlDevices ++ contract.hosts.sentry.controlDevices)
    && builtins.all
    (device: device.controlAllowed)
    (builtins.filter
      (device:
        builtins.any
        (allowed: lib.hasInfix device.hint allowed.hint)
        (contract.hosts.zephyr.controlDevices
          ++ contract.hosts.nexus.controlDevices
          ++ contract.hosts.forge.controlDevices ++ contract.hosts.sentry.controlDevices))
      (contract.hosts.zephyr.expected
        ++ contract.hosts.nexus.expected
        ++ contract.hosts.forge.expected ++ contract.hosts.sentry.expected));
  checks = {
    schemaVersion = contract.schemaVersion == 1;
    interfaceVersion = contract.interfaceVersion == "1.0";
    hostSet = lib.sort builtins.lessThan hostNames == expectedHosts;
    requiredFields = allExpectedDevicesHaveRequiredFields;
    controlListPolicy = controlListPolicy;
    noNumericIndexContract = !(lib.strings.hasInfix "deviceIds" (builtins.toJSON contract));
    stylixPaletteSource = lib.strings.hasInfix "config.lib.stylix.colors" moduleSource;
    paletteRoles = lib.strings.hasInfix "roles" moduleSource;
    inventoryJson = lib.strings.hasInfix "report.json" moduleSource;
    prometheusMetrics = lib.strings.hasInfix "rgb_inventory_scan_success" moduleSource;
    readOnlyDiscovery =
      lib.strings.hasInfix "--list-devices" moduleSource
      && lib.strings.hasInfix "openrazerDevices" moduleSource
      && !(lib.strings.hasInfix "--profile" moduleSource)
      && !(lib.strings.hasInfix "liquidctl initialize" moduleSource)
      && !(lib.strings.hasInfix "pwm1" moduleSource);
    detectedAndGapMetrics =
      lib.strings.hasInfix "rgb_inventory_detected" moduleSource
      && lib.strings.hasInfix "rgb_inventory_visibility_gap" moduleSource
      && lib.strings.hasInfix "expectedCount" moduleSource;
    syncTimer = lib.strings.hasInfix "systemd.timers.rgb-stylix-sync" moduleSource;
    repeatedNameSupport = lib.strings.hasInfix "matchAll" moduleSource;
    temperatureWritesRemoved = lib.strings.hasInfix "temperature RGB writes are not provided" rgbSource;
    noLegacyDefaultIndices = !(lib.strings.hasInfix "[6 2 7 9]" rgbSource);
    stylixTemperatureDefaultsRemoved = !(lib.strings.hasInfix "stylixColors.base0B" rgbSource);
  };
  failures = builtins.attrNames (lib.filterAttrs (_: value: !value) checks);
in {
  inherit checks failures;
  passed = failures == [];
}
