{
  config,
  pkgs,
  lib,
  ...
}: {
  # Fan control for Sentry (NCT6793, ASUS B550M TUF Gaming)
  # PWM2 = CPU fan header
  # PWM3-5 = Chassis fan headers
  # AMD GPU fan controlled separately by amdgpu driver (hwmon1)

  systemd.services.sentry-fancontrol = {
    description = "Sentry NCT6793 fan control";
    wantedBy = ["multi-user.target"];
    after = ["multi-user.target"];
    serviceConfig = {
      ExecStart = lib.getExe pkgs.python3 + " ${./fan-control-scripts/sentry-fancontrol.py}";
      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      RestrictRealtime = true;
    };
  };

  environment.systemPackages = with pkgs; [ lm_sensors ];

  boot.kernelModules = ["nct6775"];
}