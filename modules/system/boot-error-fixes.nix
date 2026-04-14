{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    mkIf
    mkDefault
    ;
in
{
  options.services.boot-error-fixes = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable fixes for identified boot errors";
    };
  };

  config = mkIf config.services.boot-error-fixes.enable {
    users.groups.plugdev = { };

    virtualisation.podman = mkDefault {
      enable = true;
      dockerCompat = true;
    };


    systemd.services.boot-error-monitor = {
      description = "Monitor and report boot errors";
      wantedBy = [ "multi-user.target" ];
      after = [
        "systemd-sysusers.service"
        "multi-user.target"
      ];
      wants = [ "systemd-sysusers.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "boot-error-check" ''
          #!${pkgs.bash}/bin/bash
          echo "=== Boot Error Status ===" | ${pkgs.coreutils}/bin/tee -a /var/log/boot-errors.log

          if [ -z "$(${pkgs.coreutils}/bin/ls /run/agenix.d/*/ 2>/dev/null)" ]; then
            echo "WARNING: No agenix secrets decrypted" | ${pkgs.coreutils}/bin/tee -a /var/log/boot-errors.log
          fi

          if ! ${pkgs.shadow}/bin/getent group plugdev >/dev/null 2>&1; then
            echo "WARNING: plugdev group missing" | ${pkgs.coreutils}/bin/tee -a /var/log/boot-errors.log
          fi
        '';
        RemainAfterExit = true;
      };
    };
  };
}
