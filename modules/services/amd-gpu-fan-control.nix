{ config, lib, pkgs, ... }:
let
  cfg = config.services.amd-gpu-fan-control;
in
{
  options.services.amd-gpu-fan-control = {
    enable = lib.mkEnableOption "AMD GPU Fan Control Service";
  };

  config = lib.mkIf cfg.enable {
    # Create the fan control script
    environment.etc."local/bin/amd-fan-control.sh".text = ''
      #!/run/current-system/sw/bin/bash
      # AMD GPU Fan Control for RX 5700 XT
      # Monitors temperature and adjusts PWM fan speed

      GPU0_PWM="/sys/class/drm/card0/device/hwmon/hwmon0/pwm1"
      GPU1_PWM="/sys/class/drm/card2/device/hwmon/hwmon1/pwm1"
      GPU0_TEMP="/sys/class/drm/card0/device/hwmon/hwmon0/temp1_input"
      GPU1_TEMP="/sys/class/drm/card2/device/hwmon/hwmon1/temp1_input"

      # GPU 0: Aggressive curve (03:00.0 - runs hotter)
      set_gpu0_fan() {
          local temp=$(cat $GPU0_TEMP | awk '{print $1/1000}')
          local pwm

          if [ $temp -lt 50 ]; then
              pwm=80   # ~31%
          elif [ $temp -lt 60 ]; then
              pwm=120  # ~47%
          elif [ $temp -lt 70 ]; then
              pwm=160  # ~63%
          elif [ $temp -lt 80 ]; then
              pwm=200  # ~78%
          else
              pwm=255  # 100%
          fi

          echo $pwm > $GPU0_PWM
      }

      # GPU 1: Moderate curve (08:00.0 - runs cooler)
      set_gpu1_fan() {
          local temp=$(cat $GPU1_TEMP | awk '{print $1/1000}')
          local pwm

          if [ $temp -lt 50 ]; then
              pwm=60   # ~24%
          elif [ $temp -lt 60 ]; then
              pwm=100  # ~39%
          elif [ $temp -lt 70 ]; then
              pwm=140  # ~55%
          elif [ $temp -lt 80 ]; then
              pwm=180  # ~71%
          else
              pwm=255  # 100%
          fi

          echo $pwm > $GPU1_PWM
      }

      # Ensure manual PWM mode on startup
      echo 1 > /sys/class/drm/card0/device/hwmon/hwmon0/pwm1_enable 2>/dev/null || true
      echo 1 > /sys/class/drm/card2/device/hwmon/hwmon1/pwm1_enable 2>/dev/null || true

      echo "AMD Fan Control started: GPU0 $(cat $GPU0_TEMP | awk '{print $1/1000}')°C, GPU1 $(cat $GPU1_TEMP | awk '{print $1/1000}')°C"

      # Main control loop
      while true; do
          set_gpu0_fan
          set_gpu1_fan
          sleep 5
      done
    '';

    systemd.services.amd-gpu-fan-control = {
      description = "AMD GPU Fan Control Service";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "/etc/local/bin/amd-fan-control.sh";
        Restart = "always";
        RestartSec = "10s";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Ensure the script is executable
    systemd.tmpfiles.rules = [
      "Z /etc/local/bin/amd-fan-control.sh 0755 root root -"
    ];
  };
}
