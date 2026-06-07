#!/usr/bin/env python3
"""Patch Noctalia BrightnessService.qml to add SDR brightness support
for external monitors without DDC/CI or backlight devices.

Supports Niri (niri msg output sdr-brightness).

Outputs are matched by name (e.g. HDMI-A-2 = Samsung TV).
"""
import sys

class PatchError(Exception):
    pass

def patch(content: str) -> str:
    failures = []

    # 1. Add sdrBrightnessOutputs property
    old1 = 'property list<var> availableBacklightDevices: []'
    new1 = '''property list<var> availableBacklightDevices: []
  // Outputs needing compositor-based SDR brightness (Samsung HDMI TV etc.)
  property list<var> sdrBrightnessOutputs: ["HDMI-A-2"]'''
    if 'sdrBrightnessOutputs' in content:
        print("sdrBrightnessOutputs already exists", file=sys.stderr)
    elif old1 in content:
        content = content.replace(old1, new1)
        print("Added sdrBrightnessOutputs property", file=sys.stderr)
    else:
        failures.append("Could not find availableBacklightDevices anchor for sdrBrightnessOutputs")

    # 2. Add isSdrBrightness property + update method
    old2 = 'readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : "internal")'
    if 'isSdrBrightness' in content:
        print("isSdrBrightness already exists", file=sys.stderr)
    elif old2 in content:
        new2 = '''readonly property bool isSdrBrightness: {
      if (isAppleDisplay || isDdc || brightnessPath !== "")
        return false;
      if (root.sdrBrightnessOutputs.indexOf(modelData.name) < 0)
        return false;
      return true;
    }
    readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : (isSdrBrightness ? "sdr-brightness" : "internal"))'''
        content = content.replace(old2, new2)
        print("Added isSdrBrightness property", file=sys.stderr)
    else:
        failures.append("Could not find method property anchor for isSdrBrightness")

    # 3. Add isSdrBrightness to brightnessControlAvailable
    old3 = '      return brightnessPath !== "";'
    sdr_check = 'if (isSdrBrightness) return true;'
    if old3 in content and sdr_check not in content:
        content = content.replace(old3, sdr_check + '\n      return brightnessPath !== "";', 1)
        print("Added isSdrBrightness to brightnessControlAvailable", file=sys.stderr)

    # 4. Insert sdr-brightness handler into setBrightness (BEFORE !isDdc, AFTER DDC)
    set_anchor = '      } else if (!isDdc) {\n        monitor.commandRunning = true;\n        monitor.ignoreNextChange = true;\n        var setMin = Settings.data.brightness.enforceMinimum ? "-n" : "";'

    set_sdr_handler = '''      } else if (isSdrBrightness) {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        var outputName = monitor.modelData.name;
        var sdrValue = value.toFixed(4);
        setBrightnessProc.command = ["niri", "msg", "output", outputName, "sdr-brightness", sdrValue];
        setBrightnessProc.running = true;
      } else if (!isDdc) {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        var setMin = Settings.data.brightness.enforceMinimum ? "-n" : "";'''

    if set_anchor in content:
        content = content.replace(set_anchor, set_sdr_handler, 1)
        print("Inserted sdr-brightness into setBrightness", file=sys.stderr)
    else:
        failures.append("Could not find setBrightness anchor for sdr-brightness injection")

    # 5. Insert sdr-brightness handler into initBrightness (BEFORE !isDdc, AFTER DDC)
    init_anchor = '      } else if (!isDdc) {\n        // Internal backlight: first try explicit output mapping, then fall back to first available.\n        var preferredDevicePath = root.getMappedBacklightDevice(modelData.name);'

    init_sdr_handler = '''      } else if (isSdrBrightness) {
        monitor.brightness = 0.5;
        monitor.brightnessUpdated(monitor.brightness);
        root.monitorBrightnessChanged(monitor, monitor.brightness);
        monitor.initInProgress = false;
      } else if (!isDdc) {
        // Internal backlight: first try explicit output mapping, then fall back to first available.
        var preferredDevicePath = root.getMappedBacklightDevice(modelData.name);'''

    if init_anchor in content:
        content = content.replace(init_anchor, init_sdr_handler, 1)
        print("Inserted sdr-brightness into initBrightness", file=sys.stderr)
    else:
        failures.append("Could not find initBrightness anchor for sdr-brightness injection")

    # 6. Add sdr-brightness to refreshBrightnessFromSystem
    old6 = '''      if (!monitor.isDdc && !monitor.isAppleDisplay) {
        // For internal displays, query the system directly
        refreshProc.command = ["sh", "-c", "cat " + monitor.brightnessPath + " && " + "cat " + monitor.maxBrightnessPath];'''

    new_refresh = '''      if (monitor.isSdrBrightness) {
        // Cannot read current SDR brightness from compositor, skip
        return;
      } else if (!monitor.isDdc && !monitor.isAppleDisplay) {'''

    if 'monitor.isSdrBrightness' in content and 'Cannot read current SDR' in content:
        print("sdr-brightness refreshBrightnessFromSystem already exists", file=sys.stderr)
    elif old6 in content:
        content = content.replace(old6, new_refresh)
        print("Added sdr-brightness to refreshBrightnessFromSystem", file=sys.stderr)
    else:
        failures.append("Could not find refreshBrightnessFromSystem anchor for sdr-brightness injection")

    if failures:
        raise PatchError(
            "Patch partially failed — upstream QML structure changed:\n  " +
            "\n  ".join(failures) +
            "\nUpdate patch-noctalia-brightness.py or remove noctalia-sdr-brightness.nix " +
            "if upstream merged the feature."
        )

    return content

if __name__ == "__main__":
    target = sys.argv[1]
    with open(target, 'r') as f:
        content = f.read()
    try:
        patched = patch(content)
    except PatchError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
    with open(target, 'w') as f:
        f.write(patched)
    print(f"Patched {target}")
