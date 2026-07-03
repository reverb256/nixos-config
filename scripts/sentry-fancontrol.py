#!/usr/bin/env python3
"""
Fan control for Sentry (NCT6793, ASUS B550M TUF Gaming)
hwmon2 (nct6793) - controls system fans 2-5.
AMD GPU has its own amdgpu fan control (separate hwmon).

Fan layout:
  pwm2:  CPU fan header (connected to processor fan)
  pwm3:  CHA_FAN1 (front intake? - empty/0 RPM)
  pwm4:  CHA_FAN2 (rear exhaust? - empty/0 RPM)
  pwm5:  CHA_FAN3 (side exhaust - 1200 RPM @ 24%)

CPU: AMD Ryzen 9 3900X (Zen2, 12-core)
GPU: AMD Radeon RX 5600 XT (separate amdgpu fan control)
"""
import time
import sys
import subprocess
import os
from pathlib import Path

HWMON = Path("/sys/class/hwmon/hwmon2")   # NCT6793
AMD_HWMON = Path("/sys/class/hwmon/hwmon1")  # amdgpu
INTERVAL = 5

# Fan configs: pwm2 = CPU fan, pwm3-5 = chassis fans
# GPU (5600 XT) fan is controlled by amdgpu driver separately
FAN_CONFIGS = [
    # CPU fan (pwm2) - responds to CPU temp (TSI via temp13 or CPUTIN via temp1)
    {"pwm": 2, "temp": 13, "min_temp": 40, "max_temp": 80, "min_pwm": 50, "max_pwm": 180},
    # Chassis fan 1 (pwm3) - empty header
    {"pwm": 3, "temp": 1, "min_temp": 35, "max_temp": 65, "min_pwm": 35, "max_pwm": 120},
    # Chassis fan 2 (pwm4) - empty header
    {"pwm": 4, "temp": 1, "min_temp": 35, "max_temp": 65, "min_pwm": 35, "max_pwm": 120},
    # Chassis fan 3 (pwm5) - exhaust
    {"pwm": 5, "temp": 1, "min_temp": 35, "max_temp": 65, "min_pwm": 35, "max_pwm": 150},
]


def read_int(path: Path) -> int:
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return 0


def write_int(path: Path, value: int) -> bool:
    try:
        path.write_text(str(max(0, min(255, value))))
        return True
    except OSError:
        return False


def get_amd_gpu_temps() -> list:
    """Get AMD GPU junction temps via hwmon (amdgpu)."""
    temps = []
    for suffix in ["", "_1", "_2"]:
        try:
            t = read_int(AMD_HWMON / f"temp{suffix}_input")
            if t > 0:
                temps.append(t // 1000)
        except OSError:
            pass
    return temps


def get_cpu_temp() -> int:
    """Get CPU TSI temp (temp13 on NCT6793, in millidegrees)."""
    try:
        return read_int(HWMON / "temp13_input") // 1000
    except OSError:
        return 0


def ensure_manual_mode():
    for cfg in FAN_CONFIGS:
        enable_file = HWMON / f"pwm{cfg['pwm']}_enable"
        current = read_int(enable_file)
        if current != 1:
            write_int(enable_file, 1)


def pwm_for_temp(temp: int, cfg: dict) -> int:
    min_t, max_t = cfg["min_temp"], cfg["max_temp"]
    min_p, max_p = cfg["min_pwm"], cfg["max_pwm"]
    if temp <= min_t:
        return min_p
    if temp >= max_t:
        return max_p
    ratio = (temp - min_t) / (max_t - min_t)
    return int(min_p + ratio * (max_p - min_p))


def main():
    print(f"NCT6793 fan control starting for Sentry...", flush=True)
    print(f"hwmon: {HWMON}", flush=True)

    if not HWMON.exists():
        print(f"ERROR: {HWMON} not found!", flush=True)
        sys.exit(1)

    ensure_manual_mode()
    print("All PWM channels set to manual mode", flush=True)
    print(f"Interval: {INTERVAL}s\n", flush=True)

    try:
        while True:
            cpu_temp = get_cpu_temp()
            amd_temps = get_amd_gpu_temps()
            max_amd = max(amd_temps) if amd_temps else 0
            effective = max(cpu_temp, max_amd)

            status = f"[{time.strftime('%H:%M:%S')}] "

            for cfg in FAN_CONFIGS:
                pwm_num = cfg["pwm"]

                # Use max of CPU and AMD GPU temp for fan speed
                if max_amd > 0 and cpu_temp < max_amd:
                    fan_temp = max_amd
                    label = f"GPU{max_amd}C"
                else:
                    fan_temp = cpu_temp
                    label = "CPU"

                pwm = pwm_for_temp(fan_temp, cfg)
                pwm_file = HWMON / f"pwm{pwm_num}"
                fan_file = HWMON / f"fan{pwm_num}_input"

                write_int(pwm_file, pwm)
                rpm = read_int(fan_file)
                pct = int(round(pwm / 255 * 100))

                status += f"F{pwm_num}:{rpm:4}rpm@{pct:3}%({label}:{fan_temp}C) "

            if amd_temps:
                status += f"| AMD GPU: {amd_temps[0]}°C"

            print(status, flush=True)
            time.sleep(INTERVAL)

    except KeyboardInterrupt:
        print("\nFan control stopped.", flush=True)


if __name__ == "__main__":
    main()