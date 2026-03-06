#!/usr/bin/env python3
"""
Simple fan control for MSI X570 TOMAHAWK with NCT6797
Bypasses lm-sensors fancontrol path validation issues.
"""
import time
import sys
from pathlib import Path

# Configuration
HWMON = Path("/sys/class/hwmon/hwmon6")
INTERVAL = 5  # seconds

# Fan configurations: (pwm_num, temp_input_num, min_temp, max_temp, min_pwm, max_pwm)
FAN_CONFIGS = [
    # CPU fans - use temp13 (AMD TSI core temp) - more aggressive curve
    {"pwm": 1, "temp": 13, "min_temp": 45, "max_temp": 80, "min_pwm": 70, "max_pwm": 255},
    {"pwm": 2, "temp": 13, "min_temp": 45, "max_temp": 80, "min_pwm": 70, "max_pwm": 255},
    # Case fans - use temp1 (SYSTIN) - respond to system temp
    {"pwm": 3, "temp": 1, "min_temp": 35, "max_temp": 65, "min_pwm": 75, "max_pwm": 200},
    {"pwm": 4, "temp": 1, "min_temp": 35, "max_temp": 65, "min_pwm": 75, "max_pwm": 200},
    {"pwm": 5, "temp": 1, "min_temp": 35, "max_temp": 65, "min_pwm": 75, "max_pwm": 200},
    {"pwm": 6, "temp": 1, "min_temp": 35, "max_temp": 65, "min_pwm": 75, "max_pwm": 200},
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
    print("Starting simple fan control for MSI X570 TOMAHAWK...", flush=True)
    print(f"Reading from: {HWMON}", flush=True)

    # Verify hwmon exists
    if not HWMON.exists():
        print(f"Error: {HWMON} not found!", flush=True)
        sys.exit(1)

    # Ensure manual mode
    ensure_manual_mode()

    print(f"Fan control interval: {INTERVAL}s", flush=True)
    print("Press Ctrl+C to stop\n", flush=True)

    try:
        while True:
            # Build status line
            status = f"[{time.strftime('%H:%M:%S')}] "

            for config in FAN_CONFIGS:
                pwm_num = config["pwm"]
                temp_num = config["temp"]

                # Read temperature (millidecelsius to celsius)
                temp_file = HWMON / f"temp{temp_num}_input"
                temp_raw = read_int(temp_file)
                temp = temp_raw / 1000.0

                # Calculate and set PWM
                pwm = calculate_pwm(int(temp), config)
                pwm_file = HWMON / f"pwm{pwm_num}"

                # Read current fan RPM
                fan_file = HWMON / f"fan{pwm_num}_input"
                rpm = read_int(fan_file)

                # Write PWM
                write_int(pwm_file, pwm)

                percent = int(pwm / 255 * 100)
                status += f"F{pwm_num}:{rpm:4}rpm@{percent:3}%(temp{temp_num}:{temp:4.1f}C) "

            # Print the complete line
            print(status, flush=True)
            time.sleep(INTERVAL)

    except KeyboardInterrupt:
        print("\nFan control stopped.", flush=True)

if __name__ == "__main__":
    main()
