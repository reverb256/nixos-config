#!/usr/bin/env python3
"""
GPU-aware fan control for NCT6797 (Zephyr MSI X570)
All 7 PWM channels with proper hwmon mapping.
Writes to hwmon4 (nct6797), not hwmon6 (jc42).

Fan layout:
  pwm1-2: Front intake (respond to CPU+GPU max)
  pwm3-5: Radiator fans (3060Ti, respond to GPU0)
  pwm6:   Radiator fan (3090 hybrid, respond to GPU1)
  pwm7:   Exhaust (respond to CPU/system temp)
"""
import time
import sys
import subprocess
import os
from pathlib import Path

HWMON = Path("/sys/class/hwmon/hwmon4")   # NCT6797
NVIDIA_SMI = "/run/current-system/sw/bin/nvidia-smi"
INTERVAL = 5   # seconds

# Fan configs: (pwm_num, temp_input, gpu_aware, min_temp, max_temp, min_pwm, max_pwm)
# GPU-aware fans use max(cpu_temp, max_gpu_temp)
FAN_CONFIGS = [
    # Front intake fans (respond to hot GPU + CPU)
    {"pwm": 1, "temp": 1,  "gpu_aware": True,  "min_temp": 35, "max_temp": 70, "min_pwm": 70,  "max_pwm": 200},  # SYSTIN
    {"pwm": 2, "temp": 1,  "gpu_aware": True,  "min_temp": 35, "max_temp": 70, "min_pwm": 70,  "max_pwm": 200},  # SYSTIN
    # Radiator fans - 3060Ti (GPU0)
    {"pwm": 3, "temp": 1,  "gpu_aware": True,  "min_temp": 35, "max_temp": 70, "min_pwm": 100, "max_pwm": 200},  # GPU-aware
    {"pwm": 4, "temp": 1,  "gpu_aware": True,  "min_temp": 35, "max_temp": 70, "min_pwm": 100, "max_pwm": 200},  # GPU-aware
    {"pwm": 5, "temp": 1,  "gpu_aware": True,  "min_temp": 35, "max_temp": 70, "min_pwm": 100, "max_pwm": 200},  # GPU-aware
    # Radiator fan - 3090 hybrid (GPU1)
    {"pwm": 6, "temp": 1,  "gpu_aware": True,  "min_temp": 35, "max_temp": 70, "min_pwm": 120, "max_pwm": 200},  # GPU-aware
    # Exhaust fan (system/CPU temp only)
    {"pwm": 7, "temp": 1,  "gpu_aware": False, "min_temp": 35, "max_temp": 70, "min_pwm": 35,  "max_pwm": 180},  # SYSTIN
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


def get_gpu_temps() -> list:
    try:
        result = subprocess.run(
            [NVIDIA_SMI, "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=2,
            env={**os.environ, "CUDA_VISIBLE_DEVICES": "0,1"}
        )
        if result.returncode == 0:
            return [int(line.strip()) for line in result.stdout.strip().split('\n') if line.strip()]
    except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
        pass
    return []


def get_cpu_temp() -> int:
    """Get effective system temp (prefer SYSTIN on NCT6797, fall back to k10temp Tctl)."""
    try:
        return read_int(HWMON / "temp1_input") // 1000
    except OSError:
        pass
    try:
        return read_int(Path("/sys/class/hwmon/hwmon3/temp1_input")) // 1000  # k10temp
    except OSError:
        return 0


def ensure_manual_mode():
    """Ensure all PWM channels stay in manual mode (1). Re-arm every tick."""
    for cfg in FAN_CONFIGS:
        enable_file = HWMON / f"pwm{cfg['pwm']}_enable"
        try:
            current = int(enable_file.read_text().strip())
        except (OSError, ValueError):
            current = 5
        if current != 1:
            write_int(enable_file, 1)


def pwm_for_temp(temp: int, cfg: dict) -> int:
    """Linear interpolation between min/max PWM for a given temp."""
    min_t, max_t = cfg["min_temp"], cfg["max_temp"]
    min_p, max_p = cfg["min_pwm"], cfg["max_pwm"]
    if temp <= min_t:
        return min_p
    if temp >= max_t:
        return max_p
    ratio = (temp - min_t) / (max_t - min_t)
    return int(min_p + ratio * (max_p - min_p))


def main():
    print(f"GPU-aware NCT6797 fan control starting...", flush=True)
    print(f"hwmon: {HWMON}", flush=True)

    if not HWMON.exists():
        print(f"ERROR: {HWMON} not found!", flush=True)
        sys.exit(1)

    ensure_manual_mode()
    print("All PWM channels set to manual mode (1)", flush=True)
    print(f"Interval: {INTERVAL}s\n", flush=True)

    try:
        while True:
            gpu_temps = get_gpu_temps()
            max_gpu = max(gpu_temps) if gpu_temps else 0
            cpu_temp = get_cpu_temp()
            effective = cpu_temp if cpu_temp > max_gpu else max_gpu

            # Re-arm manual mode every tick — NCT6797 firmware can revert to mode 5
            ensure_manual_mode()

            status = f"[{time.strftime('%H:%M:%S')}] "

            for cfg in FAN_CONFIGS:
                pwm_num = cfg["pwm"]
                temp_num = cfg["temp"]

                # Determine effective temp for this fan
                if cfg["gpu_aware"] and max_gpu > 0:
                    fan_temp = max(cpu_temp, max_gpu)
                    label = f"GPU{max_gpu}C"
                else:
                    fan_temp = cpu_temp
                    label = "CPU"

                # Read actual temp sensor value for display
                temp_file = HWMON / f"temp{temp_num}_input"
                display_temp = read_int(temp_file) // 1000

                pwm = pwm_for_temp(fan_temp, cfg)
                pwm_file = HWMON / f"pwm{pwm_num}"
                fan_file = HWMON / f"fan{pwm_num}_input"

                write_int(pwm_file, pwm)
                rpm = read_int(fan_file)
                pct = int(round(pwm / 255 * 100))

                status += f"F{pwm_num}:{rpm:4}rpm@{pct:3}%({label}:{fan_temp}C) "

            if gpu_temps:
                status += f"| GPUs: {'/'.join(map(str, gpu_temps))}°C"

            print(status, flush=True)
            time.sleep(INTERVAL)

    except KeyboardInterrupt:
        print("\nFan control stopped.", flush=True)


if __name__ == "__main__":
    main()