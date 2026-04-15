#!/usr/bin/env python3
"""Patch Noctalia BrightnessService.qml to add niri SDR brightness support.

Adds a 4th brightness control method using 'niri msg output sdr-brightness'
for monitors without DDC/CI or backlight devices (e.g. Samsung HDMI TV
via NV_PLANE_DEGAMMA_MULTIPLIER).
"""
import sys

class PatchError(Exception):
    pass

def patch(content: str) -> str:
    failures = []
    # 1. Add niriSdrOutputs property
    old1 = 'property list<var> availableBacklightDevices: []'
    new1 = '''property list<var> availableBacklightDevices: []
  // Outputs with niri SDR brightness (NV_PLANE_DEGAMMA_MULTIPLIER)
  property list<var> niriSdrOutputs: ["HDMI-A-2"]'''
    if 'niriSdrOutputs' in content:
        print("niriSdrOutputs already exists (upstream merged?)", file=sys.stderr)
    elif old1 in content:
        content = content.replace(old1, new1)
        print("Added niriSdrOutputs property", file=sys.stderr)
    else:
        failures.append("Could not find availableBacklightDevices anchor for niriSdrOutputs")

    # 2. Add isNiriSdr property and update method
    old2 = 'readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : "internal")'
    new2 = '''readonly property bool isNiriSdr: {
      if (isAppleDisplay || isDdc || brightnessPath !== "")
        return false;
      return root.niriSdrOutputs.indexOf(modelData.name) >= 0;
    }
    readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : (isNiriSdr ? "niri-sdr" : "internal"))'''
    if 'isNiriSdr' in content:
        print("isNiriSdr already exists (upstream merged?)", file=sys.stderr)
    elif old2 in content:
        content = content.replace(old2, new2)
        print("Added isNiriSdr property", file=sys.stderr)
    else:
        failures.append("Could not find method property anchor for isNiriSdr")

    # 3. Add isNiriSdr to brightnessControlAvailable
    old3 = '''      return brightnessPath !== "";'''
    new3 = '''if (isNiriSdr) return true;
      return brightnessPath !== "";'''
    if old3 in content and 'isNiriSdr' not in content.split('brightnessControlAvailable')[1].split('}')[0] if 'brightnessControlAvailable' in content else '':
        content = content.replace(old3, new3, 1)
        print("Added isNiriSdr to brightnessControlAvailable", file=sys.stderr)

    # 4. Insert niri-sdr handler into setBrightness
    old4 = '''      } else if (isDdc && busNum !== "") {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        var ddcValue = Math.round(value * monitor.maxBrightness);
        var ddcBus = busNum;
        Qt.callLater(() => {
                       setBrightnessProc.command = ["ddcutil", "-b", ddcBus, "--noverify", "--async", "--enable-dynamic-sleep", "--sleep-multiplier=0.05", "setvcp", "10", ddcValue];
                       setBrightnessProc.running = true;
                     });
      } else if (!isDdc) {'''

    new4 = '''      } else if (isDdc && busNum !== "") {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        var ddcValue = Math.round(value * monitor.maxBrightness);
        var ddcBus = busNum;
        Qt.callLater(() => {
                       setBrightnessProc.command = ["ddcutil", "-b", ddcBus, "--noverify", "--async", "--enable-dynamic-sleep", "--sleep-multiplier=0.05", "setvcp", "10", ddcValue];
                       setBrightnessProc.running = true;
                     });
      } else if (isNiriSdr) {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        var sdrValue = value.toFixed(4);
        var outputName = monitor.modelData.name;
        setBrightnessProc.command = ["niri", "msg", "output", outputName, "sdr-brightness", sdrValue];
        setBrightnessProc.running = true;
      } else if (!isDdc) {'''

    if 'niri msg output' in content:
        print("niri-sdr setBrightness handler already exists (upstream merged?)", file=sys.stderr)
    elif old4 in content:
        content = content.replace(old4, new4)
        print("Added niri-sdr to setBrightness", file=sys.stderr)
    else:
        failures.append("Could not find setBrightness ddcutil anchor for niri-sdr injection")

    # 5. Insert niri-sdr handler into initBrightness
    old5 = '''      } else if (isDdc && busNum !== "") {
        initProc.command = ["ddcutil", "-b", busNum, "--enable-dynamic-sleep", "--sleep-multiplier=0.05", "getvcp", "10", "--brief"];
        initProc.running = true;
      } else if (!isDdc) {'''

    new5 = '''      } else if (isDdc && busNum !== "") {
        initProc.command = ["ddcutil", "-b", busNum, "--enable-dynamic-sleep", "--sleep-multiplier=0.05", "getvcp", "10", "--brief"];
        initProc.running = true;
      } else if (isNiriSdr) {
        monitor.brightness = 0.7;
        monitor.brightnessUpdated(monitor.brightness);
        root.monitorBrightnessChanged(monitor, monitor.brightness);
        monitor.initInProgress = false;
      } else if (!isDdc) {'''

    if 'monitor.brightness = 0.7' in content:
        print("niri-sdr initBrightness handler already exists (upstream merged?)", file=sys.stderr)
    elif old5 in content:
        content = content.replace(old5, new5)
        print("Added niri-sdr to initBrightness", file=sys.stderr)
    else:
        failures.append("Could not find initBrightness ddcutil anchor for niri-sdr injection")

    # 6. Add niri-sdr to refreshBrightnessFromSystem
    old6 = '''      if (!monitor.isDdc && !monitor.isAppleDisplay) {
        // For internal displays, query the system directly
        refreshProc.command = ["sh", "-c", "cat " + monitor.brightnessPath + " && " + "cat " + monitor.maxBrightnessPath];'''

    new6 = '''      if (monitor.isNiriSdr) {
        // Cannot read current niri SDR brightness, skip
        return;
      } else if (!monitor.isDdc && !monitor.isAppleDisplay) {
        // For internal displays, query the system directly
        refreshProc.command = ["sh", "-c", "cat " + monitor.brightnessPath + " && " + "cat " + monitor.maxBrightnessPath];'''

    if 'monitor.isNiriSdr' in content and 'Cannot read current niri' in content:
        print("niri-sdr refreshBrightnessFromSystem already exists (upstream merged?)", file=sys.stderr)
    elif old6 in content:
        content = content.replace(old6, new6)
        print("Added niri-sdr to refreshBrightnessFromSystem", file=sys.stderr)
    else:
        failures.append("Could not find refreshBrightnessFromSystem anchor for niri-sdr injection")

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
