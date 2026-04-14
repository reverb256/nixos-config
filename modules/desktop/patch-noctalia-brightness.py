#!/usr/bin/env python3
"""Patch Noctalia BrightnessService.qml to add niri SDR brightness support.

Adds a 4th brightness control method using 'niri msg output sdr-brightness'
for monitors without DDC/CI or backlight devices (e.g. Samsung HDMI TV
via NV_PLANE_DEGAMMA_MULTIPLIER).
"""
import sys

def patch(content: str) -> str:
    # 1. Add niriSdrOutputs property
    old1 = 'property list<var> availableBacklightDevices: []'
    new1 = '''property list<var> availableBacklightDevices: []
  // Outputs with niri SDR brightness (NV_PLANE_DEGAMMA_MULTIPLIER)
  property list<var> niriSdrOutputs: ["HDMI-A-2"]'''
    if old1 in content and 'niriSdrOutputs' not in content:
        content = content.replace(old1, new1)
        print("Added niriSdrOutputs property", file=sys.stderr)

    # 2. Add isNiriSdr property and update method
    old2 = 'readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : "internal")'
    new2 = '''readonly property bool isNiriSdr: {
      if (isAppleDisplay || isDdc || brightnessPath !== "")
        return false;
      return root.niriSdrOutputs.indexOf(modelData.name) >= 0;
    }
    readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : (isNiriSdr ? "niri-sdr" : "internal"))'''
    if old2 in content and 'isNiriSdr' not in content:
        content = content.replace(old2, new2)
        print("Added isNiriSdr property", file=sys.stderr)
    elif 'isNiriSdr' in content:
        print("isNiriSdr already exists, skipping property injection", file=sys.stderr)

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

    if 'niri msg output' not in content and old4 in content:
        content = content.replace(old4, new4)
        print("Added niri-sdr to setBrightness", file=sys.stderr)
    elif 'niri msg output' in content:
        print("niri-sdr setBrightness handler already exists", file=sys.stderr)

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

    if old5 in content and 'monitor.brightness = 0.7' not in content:
        content = content.replace(old5, new5)
        print("Added niri-sdr to initBrightness", file=sys.stderr)
    elif 'monitor.brightness = 0.7' in content:
        print("niri-sdr initBrightness handler already exists", file=sys.stderr)

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

    if old6 in content and 'monitor.isNiriSdr' not in content:
        content = content.replace(old6, new6)
        print("Added niri-sdr to refreshBrightnessFromSystem", file=sys.stderr)

    return content

if __name__ == "__main__":
    target = sys.argv[1]
    with open(target, 'r') as f:
        content = f.read()
    patched = patch(content)
    with open(target, 'w') as f:
        f.write(patched)
    print(f"Patched {target}")
