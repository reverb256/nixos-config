#!/usr/bin/env python3
"""Patch Noctalia BrightnessService.qml to add SDR brightness support
for external monitors without DDC/CI or backlight devices.

Supports both Niri (niri msg output sdr-brightness) and
Hyprland (hyprctl keyword monitor ... sdrbrightness) via hypr-set-sdr-brightness.

Outputs are matched by name (e.g. HDMI-A-2 = Samsung TV) and compositor
is detected at runtime via environment variables.
"""
import sys

class PatchError(Exception):
    pass

def patch(content: str) -> str:
    failures = []

    # 1. Add sdrBrightnessOutputs property (shared list for both compositors)
    old1 = 'property list<var> availableBacklightDevices: []'
    new1 = '''property list<var> availableBacklightDevices: []
  // Outputs needing compositor-based SDR brightness (Samsung HDMI TV etc.)
  property list<var> sdrBrightnessOutputs: ["HDMI-A-2"]'''
    if 'sdrBrightnessOutputs' in content:
        print("sdrBrightnessOutputs already exists", file=sys.stderr)
    elif 'niriSdrOutputs' in content:
        content = content.replace('niriSdrOutputs', 'sdrBrightnessOutputs')
        print("Renamed niriSdrOutputs -> sdrBrightnessOutputs", file=sys.stderr)
    elif old1 in content:
        content = content.replace(old1, new1)
        print("Added sdrBrightnessOutputs property", file=sys.stderr)
    else:
        failures.append("Could not find availableBacklightDevices anchor for sdrBrightnessOutputs")

    # 2. Add isSdrBrightness property + update method
    old2 = 'readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : "internal")'
    if 'isNiriSdr' in content and 'readonly property bool isNiriSdr' in content:
        old_niri_block_start = content.index('readonly property bool isNiriSdr:')
        brace_count = 0
        block_end = old_niri_block_start
        for i in range(old_niri_block_start, len(content)):
            if content[i] == '{':
                brace_count += 1
            elif content[i] == '}':
                brace_count -= 1
                if brace_count == 0:
                    block_end = i + 1
                    break
        old_niri_block = content[old_niri_block_start:block_end]

        new_block = '''readonly property bool isSdrBrightness: {
      if (isAppleDisplay || isDdc || brightnessPath !== "")
        return false;
      if (root.sdrBrightnessOutputs.indexOf(modelData.name) < 0)
        return false;
      // Check compositor
      if (Qt.application.arguments.join(" ").indexOf("hyprland") >= 0
          || typeof HYPRLAND_INSTANCE_SIGNATURE !== 'undefined')
        return true;
      return typeof NIRI_SOCKET !== 'undefined' || root.sdrBrightnessOutputs.indexOf(modelData.name) >= 0;
    }'''
        content = content.replace(old_niri_block, new_block)
        content = content.replace('isNiriSdr ? "niri-sdr"', 'isSdrBrightness ? "sdr-brightness"')
        print("Upgraded isNiriSdr -> isSdrBrightness (dual compositor)", file=sys.stderr)
    elif 'isSdrBrightness' in content:
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
        if 'if (isNiriSdr) return true;' in content:
            content = content.replace('if (isNiriSdr) return true;', sdr_check)
            print("Updated brightnessControlAvailable: isNiriSdr -> isSdrBrightness", file=sys.stderr)
        else:
            content = content.replace(old3, sdr_check + '\n      return brightnessPath !== "";', 1)
            print("Added isSdrBrightness to brightnessControlAvailable", file=sys.stderr)

    # 4. Insert sdr-brightness handler into setBrightness (BEFORE !isDdc, AFTER DDC)
    set_anchor = '      } else if (!isDdc) {\n        monitor.commandRunning = true;\n        monitor.ignoreNextChange = true;\n        var setMin = Settings.data.brightness.enforceMinimum ? "-n" : "";'

    set_sdr_handler = '''      } else if (isSdrBrightness) {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        var outputName = monitor.modelData.name;
        var sdrValue = value.toFixed(4);
        if (typeof HYPRLAND_INSTANCE_SIGNATURE !== 'undefined' || Qt.application.arguments.join(" ").indexOf("hyprland") >= 0) {
          var mappedValue = (0.5 + value * 1.5).toFixed(4);
          setBrightnessProc.command = ["hypr-set-sdr-brightness", outputName, mappedValue];
        } else {
          setBrightnessProc.command = ["niri", "msg", "output", outputName, "sdr-brightness", sdrValue];
        }
        setBrightnessProc.running = true;
      } else if (!isDdc) {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        var setMin = Settings.data.brightness.enforceMinimum ? "-n" : "";'''

    # Handle already-patched-with-old-names
    old_niri_set = '''      } else if (isNiriSdr) {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        var sdrValue = value.toFixed(4);
        var outputName = monitor.modelData.name;
        setBrightnessProc.command = ["niri", "msg", "output", outputName, "sdr-brightness", sdrValue];
        setBrightnessProc.running = true;
      } else if (!isDdc) {'''

    old_broken_sdr = '''      } else if (isSdrBrightness) {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        var outputName = monitor.modelData.name;
        var sdrValue = value.toFixed(4);
        if (typeof HYPRLAND_INSTANCE_SIGNATURE !== 'undefined' || Qt.application.arguments.join(" ").indexOf("hyprland") >= 0) {
          var mappedValue = (0.5 + value * 1.5).toFixed(4);
          setBrightnessProc.command = ["hypr-set-sdr-brightness", outputName, mappedValue];
        } else {
          setBrightnessProc.command = ["niri", "msg", "output", outputName, "sdr-brightness", sdrValue];
        }
        setBrightnessProc.running = true;
      } else if (!isDdc) {'''

    if set_anchor in content:
        content = content.replace(set_anchor, set_sdr_handler, 1)
        print("Inserted sdr-brightness into setBrightness", file=sys.stderr)
    elif old_niri_set in content:
        content = content.replace(old_niri_set, set_sdr_handler, 1)
        print("Replaced niri-sdr with dual sdr-brightness in setBrightness", file=sys.stderr)
    elif old_broken_sdr in content:
        print("sdr-brightness already in setBrightness (may need DDC fix)", file=sys.stderr)
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

    old_niri_init = '''      } else if (isNiriSdr) {
        monitor.brightness = 0.7;
        monitor.brightnessUpdated(monitor.brightness);
        root.monitorBrightnessChanged(monitor, monitor.brightness);
        monitor.initInProgress = false;
      } else if (!isDdc) {'''

    old_broken_init = '''      } else if (isSdrBrightness) {
        monitor.brightness = 0.5;
        monitor.brightnessUpdated(monitor.brightness);
        root.monitorBrightnessChanged(monitor, monitor.brightness);
        monitor.initInProgress = false;
      } else if (!isDdc) {'''

    if init_anchor in content:
        content = content.replace(init_anchor, init_sdr_handler, 1)
        print("Inserted sdr-brightness into initBrightness", file=sys.stderr)
    elif old_niri_init in content:
        content = content.replace(old_niri_init, init_sdr_handler, 1)
        print("Replaced niri-sdr with sdr-brightness in initBrightness", file=sys.stderr)
    elif old_broken_init in content:
        print("sdr-brightness already in initBrightness", file=sys.stderr)
    else:
        failures.append("Could not find initBrightness anchor for sdr-brightness injection")

    # 6. Add sdr-brightness to refreshBrightnessFromSystem
    old6 = '''      if (!monitor.isDdc && !monitor.isAppleDisplay) {
        // For internal displays, query the system directly
        refreshProc.command = ["sh", "-c", "cat " + monitor.brightnessPath + " && " + "cat " + monitor.maxBrightnessPath];'''

    old_niri_refresh = '''      if (monitor.isNiriSdr) {
        // Cannot read current niri SDR brightness, skip
        return;
      } else if (!monitor.isDdc && !monitor.isAppleDisplay) {'''

    new_refresh = '''      if (monitor.isSdrBrightness) {
        // Cannot read current SDR brightness from compositor, skip
        return;
      } else if (!monitor.isDdc && !monitor.isAppleDisplay) {'''

    if 'monitor.isSdrBrightness' in content and 'Cannot read current SDR' in content:
        print("sdr-brightness refreshBrightnessFromSystem already exists", file=sys.stderr)
    elif old_niri_refresh in content:
        content = content.replace(old_niri_refresh, new_refresh)
        print("Upgraded niri-sdr -> sdr-brightness in refreshBrightnessFromSystem", file=sys.stderr)
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
