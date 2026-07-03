{
  config,
  pkgs,
  lib,
  ...
}: {
  # Enable hardware monitoring fan control service
  # The fancontrol service (simple-fancontrol.py) handles all 7 NCT6797
  # PWM channels with GPU-aware temperature curves.
  # No more broken tmpfiles conflicts — the service owns PWM management.
  hardware.monitoring.fanControl = true;

  environment.systemPackages = with pkgs; [
    lm_sensors
    i2c-tools
    liquidctl
  ];

  boot.kernelModules = ["nct6775"];
}