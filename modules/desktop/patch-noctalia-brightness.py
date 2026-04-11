#!/usr/bin/env python3
"""Patch Noctalia BrightnessService.qml to add niri SDR brightness support."""
import sys

def patch(content: str) -> str:
    # 1. Add niriSdrOutputs property
    content = content.replace(
        'property list<var> availableBacklightDevices: []',
        'property list<var> availableBacklightDevices: []\n  // Outputs with niri SDR brightness (NV_PLANE_DEGAMMA_MULTIPLIER)\n  property list<var> niriSdrOutputs: ["HDMI-A-2"]'
    )
    
    # 2. Add isNiriSdr property and update method
    content = content.replace(
        'readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : "internal")',
        'readonly property bool isNiriSdr: {\n      if (isAppleDisplay || isDdc || brightnessPath !== "")\n        return false;\n      return root.niriSdrOutputs.indexOf(modelData.name) >= 0;\n    }\n    readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : (isNiriSdr ? "niri-sdr" : "internal"))'
    )
    
    # 3. Add isNiriSdr check to brightnessControlAvailable
    content = content.replace(
        'return brightnessPath !== "";',
        'if (isNiriSdr) return true;\n      return brightnessPath !== "";'
    )
    
    # 4. Add niri-sdr branch to setBrightness (insert before "else if (!isDdc)")
    content = content.replace(
        '      } else if (!isDdc) {\n        monitor.commandRunning = true;\n        monitor.ignoreNextChange = true;\n        var backlightDeviceName = root.getBacklightDeviceName(monitor.backlightDevice);\n        if (backlightDeviceName !== "") {\n          setBrightnessProc.command = ["brightnessctl", "-d", backlightDeviceName, "s", rounded + "%"];\n        } else {\n          setBrightnessProc.command = ["brightnessctl", "s", rounded + "%"];\n        }\n        setBrightnessProc.running = true;\n      }\n    }\n\n    function initBrightness(): void {\n      monitor.initInProgress = true;\n      if (isAppleDisplay) {\n        initProc.command = ["asdbctl", "get"];\n        initProc.running = true;\n      } else if (isDdc && busNum !== "") {\n        initProc.command = ["ddcutil", "-b", busNum, "--sleep-multiplier=0.05", "getvcp", "10", "--brief"];\n        initProc.running = true;\n      } else if (!isDdc) {',
        '      } else if (isNiriSdr) {\n        monitor.commandRunning = true;\n        monitor.ignoreNextChange = true;\n        var sdrValue = value.toFixed(4);\n        var outputName = monitor.modelData.name;\n        setBrightnessProc.command = ["niri", "msg", "output", outputName, "sdr-brightness", sdrValue];\n        setBrightnessProc.running = true;\n      } else if (!isDdc) {\n        monitor.commandRunning = true;\n        monitor.ignoreNextChange = true;\n        var backlightDeviceName = root.getBacklightDeviceName(monitor.backlightDevice);\n        if (backlightDeviceName !== "") {\n          setBrightnessProc.command = ["brightnessctl", "-d", backlightDeviceName, "s", rounded + "%"];\n        } else {\n          setBrightnessProc.command = ["brightnessctl", "s", rounded + "%"];\n        }\n        setBrightnessProc.running = true;\n      }\n    }\n\n    function initBrightness(): void {\n      monitor.initInProgress = true;\n      if (isAppleDisplay) {\n        initProc.command = ["asdbctl", "get"];\n        initProc.running = true;\n      } else if (isDdc && busNum !== "") {\n        initProc.command = ["ddcutil", "-b", busNum, "--sleep-multiplier=0.05", "getvcp", "10", "--brief"];\n        initProc.running = true;\n      } else if (isNiriSdr) {\n        monitor.brightness = 0.7;\n        monitor.brightnessUpdated(monitor.brightness);\n        root.monitorBrightnessChanged(monitor, monitor.brightness);\n        monitor.initInProgress = false;\n      } else if (!isDdc) {'
    )
    
    # 5. Add niri-sdr to refreshBrightnessFromSystem
    content = content.replace(
        '      if (!monitor.isDdc && !monitor.isAppleDisplay) {\n        // For internal displays, query the system directly\n        refreshProc.command = ["sh", "-c", "cat " + monitor.brightnessPath + " && " + "cat " + monitor.maxBrightnessPath];\n        refreshProc.running = true;',
        '      if (monitor.isNiriSdr) {\n        // Cannot read current niri SDR brightness, skip\n        return;\n      } else if (!monitor.isDdc && !monitor.isAppleDisplay) {\n        // For internal displays, query the system directly\n        refreshProc.command = ["sh", "-c", "cat " + monitor.brightnessPath + " && " + "cat " + monitor.maxBrightnessPath];\n        refreshProc.running = true;'
    )
    
    return content

if __name__ == "__main__":
    target = sys.argv[1]
    with open(target, 'r') as f:
        content = f.read()
    patched = patch(content)
    with open(target, 'w') as f:
        f.write(patched)
    print(f"Patched {target}")
