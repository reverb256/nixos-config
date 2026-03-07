#!/usr/bin/env python3
"""
GPU-aware fan control for MSI X570 TOMAHAWK with NCT6797
Adjusts case fans based on GPU temperature in addition to CPU/System temps.
"""
import time
import sys
import subprocess
from pathlib import Path

# Configuration
HWMON = Path("/sys/class/hwmon/hwmon6")
INTERVAL = 5  # seconds

# Fan configurations: (pwm_num, temp_input_num, min_temp, max_temp, min_pwm, max_pwm)
# Also can specify GPU as temp source by using negative numbers for GPU indices
FAN_CONFIGS = [
    # CPU fans - use temp13 (AMD TSI core temp)
    {"pwm": 1, "temp": 13, "min_temp": 45, "max_temp": 80, "min_pwm": 70, "max_pwm": 255},
    {"pwm": 2, "temp": 13, "min_temp": 45, "max_temp": 80, "min_pwm": 70, "max_pwm": 255},
    # Case fans - use temp1 (SYSTIN) with GPU awareness
    {"pwm": 3, "temp": 1, "gpu_aware": True, "min_temp": 35, "max_temp": 65, "min_pwm": 75, "max_pwm": 200},
    {"pwm": 4, "temp": 1, "gpu_aware": True, "min_temp": 35, "max_temp": 65, "min_pwm": 75, "max_pwm": 200},
    {"pwm": 5, "temp": 1, "gpu_aware": True, "min_temp": 35, "max_temp": 65, "min_pwm": 75, "max_pwm": 200},
    {"pwm": 6, "temp": 1, "gpu_aware": True, "min_temp": 35, "max_temp": 65, "min_pwm": 75, "max_pwm": 200},
]

def read_int(path: Path) -> int:
    """Read an integer from a sysfs file."""
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return 0

def write_int(path: Path, value: int) -> bool:
    """Write an integer to a sysfs file."""
    try:
        path.write_text(str(value))
        return True
    except OSError:
        return False

def get_gpu_temps() -> list:
    """Get GPU temperatures using nvidia-smi."""
    try:
        result = subprocess.run(
            ["/run/current-system/sw/bin/nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
            capture_output=True,
            text=True,
            timeout=2
        )
        if result.returncode == 0:
            temps = []
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    temps.append(int(line.strip()))
            return temps
    except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
        pass
    return []

def ensure_manual_mode():
    """Ensure all PWM fans are in manual mode."""
    for config in FAN_CONFIGS:
        enable_file = HWMON / f"pwm{config['pwm']}_enable"
        current = read_int(enable_file)
        if current != 1:  # 1 = manual mode
            print(f"Setting PWM{config['pwm']} to manual mode...", flush=True)
            write_int(enable_file, 1)

def calculate_pwm(temp: int, config: dict) -> int:
    """Calculate PWM value based on temperature."""
    min_temp, max_temp = config["min_temp"], config["max_temp"]
    min_pwm, max_pwm = config["min_pwm"], config["max_pwm"]

    if temp <= min_temp:
        return min_pwm
    elif temp >= max_temp:
        return max_pwm
    else:
        # Linear interpolation
        ratio = (temp - min_temp) / (max_temp - min_temp)
        return int(min_pwm + ratio * (max_pwm - min_pwm))

def main():
    print("Starting GPU-aware fan control for MSI X570 TOMAHAWK...", flush=True)
    print(f"Reading from: {HWMON}", flush=True)

    # Verify hwmon exists
    if not HWMON.exists():
        print(f"Error: {HWMON} not found!", flush=True)
        sys.exit(1)

    # Ensure manual mode
    ensure_manual_mode()

    print(f"Fan control interval: {INTERVAL}s", flush=True)
    print("GPU-aware mode: ENABLED (case fans respond to max(CPU, GPU temp))", flush=True)
    print("Press Ctrl+C to stop\n", flush=True)

    try:
        while True:
            # Get GPU temps
            gpu_temps = get_gpu_temps()
            max_gpu_temp = max(gpu_temps) if gpu_temps else 0

            # Build status line
            status = f"[{time.strftime('%H:%M:%S')}] "

            for config in FAN_CONFIGS:
                pwm_num = config["pwm"]
                temp_num = config["temp"]

                # Read temperature (millidecelsius to celsius)
                temp_file = HWMON / f"temp{temp_num}_input"
                temp_raw = read_int(temp_file)
                temp = temp_raw / 1000.0

                # For GPU-aware fans, consider GPU temp too
                effective_temp = int(temp)
                temp_label = f"temp{temp_num}"

                if config.get("gpu_aware") and max_gpu_temp > 0:
                    # Use higher of system temp or GPU temp
                    if max_gpu_temp > effective_temp:
                        effective_temp = max_gpu_temp
                        temp_label = f"GPU{gpu_temps.index(max_gpu_temp) if max_gpu_temp in gpu_temps else '?'}"

                # Calculate and set PWM
                pwm = calculate_pwm(effective_temp, config)
                pwm_file = HWMON / f"pwm{pwm_num}"

                # Read current fan RPM
                fan_file = HWMON / f"fan{pwm_num}_input"
                rpm = read_int(fan_file)

                # Write PWM
                write_int(pwm_file, pwm)

                percent = int(pwm / 255 * 100)
                status += f"F{pwm_num}:{rpm:4}rpm@{percent:3}%({temp_label}:{effective_temp:3}C) "

            if gpu_temps:
                status += f"| GPUs: {'/'.join(map(str, gpu_temps))}°C"

            # Print the complete line
            print(status, flush=True)
            time.sleep(INTERVAL)

    except KeyboardInterrupt:
        print("\nFan control stopped.", flush=True)

if __name__ == "__main__":
    main()
