#!/usr/bin/env python3
"""
Nexus (Gigabyte X470 AORUS ULTRA) fan control — it87 fork driver.

Two SuperIO chips (see lm-sensors configs/Gigabyte/X470-AORUS-ULTRA-GAMING.conf):
  it8686  (hwmonN, SYS_FAN* main chip): fan1 CPU_FAN, fan2 SYS_FAN1,
          fan3 SYS_FAN2, fan4 SYS_FAN3, fan5 CPU_OPT
  it8792  (hwmonN+1, EC chip):          fan1 SYS_FAN5_PUMP, fan2 SYS_FAN6_PUMP,
          fan3 SYS_FAN4

CPU_FAN is on the it8686 chip (fan1/pwm1). The it8792 channels are
EC-controlled on some Gigabyte boards and may reject direct writes — the
known workaround is toggling pwmX_enable 0->1 before each write.

This script auto-discovers the two chips by name and maps:
  - CPU_FAN (it8686 pwm1): CPU temp curve (k10temp)
  - SYS_FAN1..3 (it8686 pwm2-4): max(CPU, GPU) curve
  - CPU_OPT (it8686 pwm5): CPU curve
  - SYS_FAN4/5/6 (it8792 pwm1-3): max(CPU, GPU) curve, EC-toggle

Temps: k10temp (hwmonN, name=k10temp) + nvidia-smi GPU.
"""
import time
import subprocess
from pathlib import Path

HWMON = Path("/sys/class/hwmon")
NVIDIA_SMI = "/run/current-system/sw/bin/nvidia-smi"
INTERVAL = 5  # seconds

# Curve: (min_temp, max_temp, min_pwm, max_pwm)
CURVE = (40, 75, 60, 255)


def read_int(path):
    try:
        return int(Path(path).read_text().strip())
    except Exception:
        return None


def write_int(path, value):
    try:
        Path(path).write_text(str(int(value)))
        return True
    except Exception:
        return False


def find_chips():
    """Return (it8686_hwmon, it8792_hwmon, k10temp_hwmon) by name."""
    it8686 = it8792 = k10temp = None
    for h in sorted(HWMON.glob("hwmon*")):
        name = (h / "name").read_text().strip()
        if name.startswith("it8686"):
            it8686 = h
        elif name.startswith("it8792"):
            it8792 = h
        elif name == "k10temp":
            k10temp = h
    return it8686, it8792, k10temp


def gpu_temp():
    try:
        out = subprocess.run(
            [NVIDIA_SMI, "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
        return max(int(x) for x in out.splitlines() if x.strip())
    except Exception:
        return 0


def pwm_for(temp, gpu, min_temp, max_temp, min_pwm, max_pwm):
    hot = max(temp, gpu)
    if hot <= min_temp:
        return min_pwm
    if hot >= max_temp:
        return max_pwm
    frac = (hot - min_temp) / (max_temp - min_temp)
    return int(min_pwm + frac * (max_pwm - min_pwm))


def set_pwm(hwmon, pwm, value):
    """Write pwm value; for EC chips toggle enable 0->1 first."""
    # Toggle manual mode then apply (works around Gigabyte EC override)
    write_int(hwmon / f"pwm{pwm}_enable", 0)
    write_int(hwmon / f"pwm{pwm}_enable", 1)
    write_int(hwmon / f"pwm{pwm}", value)


def main():
    min_temp, max_temp, min_pwm, max_pwm = CURVE
    while True:
        try:
            it8686, it8792, k10temp = find_chips()
            gpu = gpu_temp()
            cpu = read_int(k10temp / "temp1_input") if k10temp else None
            if cpu is None:
                time.sleep(INTERVAL)
                continue
            cpu_c = cpu / 1000.0

            if it8686 is not None:
                for pwm in (1, 2, 3, 4, 5):
                    v = pwm_for(cpu_c, gpu, min_temp, max_temp, min_pwm, max_pwm)
                    set_pwm(it8686, pwm, v)

            if it8792 is not None:
                for pwm in (1, 2, 3):
                    v = pwm_for(cpu_c, gpu, min_temp, max_temp, min_pwm, max_pwm)
                    set_pwm(it8792, pwm, v)
        except Exception:
            pass
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
