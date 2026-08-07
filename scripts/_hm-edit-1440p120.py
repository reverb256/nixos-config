#!/usr/bin/env python3
"""One-off helper: set zephyr's HDMI-A-2 niri output to 2560x1440@120, scale 1.0.

Edit target: /home/j_kro/Projects/home-manager-config/modules/niri-outputs.nix
Only the zephyr "HDMI-A-2" block is touched (nexus HDMI-A-1 stays 4K).
"""

import re
import sys

PATH = "/home/j_kro/Projects/home-manager-config/modules/niri-outputs.nix"

with open(PATH) as f:
    s = f.read()

# Scope to the zephyr HDMI-A-2 block only.
hdmi_a2 = '        "HDMI-A-2" = {'
idx = s.find(hdmi_a2)
if idx < 0:
    print("error: HDMI-A-2 block not found")
    sys.exit(1)
end = s.find("};", idx)
if end < 0:
    print("error: block terminator not found")
    sys.exit(1)

block = s[idx:end]
new_block = re.sub(
    r"width = 3840;\s*height = 2160;\s*refresh = 60\.0;",
    "width = 2560;\n            height = 1440;\n            refresh = 119.998;",
    block,
)
new_block = re.sub(r"scale = 1\.5;", "scale = 1.0;", new_block)
if new_block == block:
    print("error: no changes made (regex did not match)")
    sys.exit(1)

s = s[:idx] + new_block + s[end:]
with open(PATH, "w") as f:
    f.write(s)
print("patched HDMI-A-2 -> 2560x1440@119.998, scale 1.0")
