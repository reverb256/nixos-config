{
  config,
  pkgs,
  lib,
  ...
}: {
  # Imperative fan control fixes applied during debugging
  # TODO: Convert to full fan-control module with temperature curves
  #
  # Manual PWM values applied (imperative):
  # - pwm1: 127 (50%)  - Front intake
  # - pwm2: 127 (50%)  - Front intake
  # - pwm3: 147 (58%)  - Radiator (3060Ti)
  # - pwm4: 147 (58%)  - Radiator (3060Ti)
  # - pwm5: 147 (58%)  - Radiator (3060Ti)
  # - pwm6: 180 (70%)  - Radiator (3090 hybrid)
  # - pwm7:  45 (18%)  - Exhaust
  #
  # These values fix PWM clipping (128%) on NCT6797 controller

  # Set PWM values at boot via tmpfiles
  systemd.tmpfiles.rules = [
    # Enable manual PWM control for fans 1-7
    "d /sys/class/hwmon/hwmon4 0755 root root -"

    # Set PWM enable mode to manual (1 = manual, 2 = automatic, 5 = automatic)
    "w /sys/class/hwmon/hwmon4/pwm1_enable - - - - 1"
    "w /sys/class/hwmon/hwmon4/pwm2_enable - - - - 1"
    "w /sys/class/hwmon/hwmon4/pwm3_enable - - - - 1"
    "w /sys/class/hwmon/hwmon4/pwm4_enable - - - - 1"
    "w /sys/class/hwmon/hwmon4/pwm5_enable - - - - 1"
    "w /sys/class/hwmon/hwmon4/pwm6_enable - - - - 1"
    "w /sys/class/hwmon/hwmon4/pwm7_enable - - - - 1"

    # Set PWM values (0-255 scale)
    "w /sys/class/hwmon/hwmon4/pwm1 - - - - 127"  # 50% - Front intake
    "w /sys/class/hwmon/hwmon4/pwm2 - - - - 127"  # 50% - Front intake
    "w /sys/class/hwmon/hwmon4/pwm3 - - - - 147"  # 58% - Radiator (3060Ti)
    "w /sys/class/hwmon/hwmon4/pwm4 - - - - 147"  # 58% - Radiator (3060Ti)
    "w /sys/class/hwmon/hwmon4/pwm5 - - - - 147"  # 58% - Radiator (3060Ti)
    "w /sys/class/hwmon/hwmon4/pwm6 - - - - 180"  # 70% - Radiator (3090 hybrid)
    "w /sys/class/hwmon/hwmon4/pwm7 - - - - 45"   # 18% - Exhaust
  ];

  # Install tools for fan monitoring and control
  environment.systemPackages = with pkgs; [
    lm_sensors  # sensors command
    i2c-tools   # i2c tools for NCT6797
    liquidctl   # AIO controller support
  ];

  # Load NCT6797 kernel module
  boot.kernelModules = [
    "nct6775"  # Driver for NCT6797
  ];

  boot.extraModulePackages = with config.boot.kernelPackages; [
    nct6775
  ];
}