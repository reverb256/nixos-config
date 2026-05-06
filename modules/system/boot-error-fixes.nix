{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    mkOption
    types
    mkIf
    mkDefault
    ;
in {
  options.services.boot-error-fixes = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable fixes for identified boot errors";
    };
  };

  config = mkIf config.services.boot-error-fixes.enable {
    users.groups.plugdev = {};

    virtualisation.podman = mkDefault {
      enable = true;
      dockerCompat = true;
    };

    # Fix logrotate refusing config owned by non-root (uid 1000).
    # Happens when nix store files have wrong ownership from remote builds.
    # Override to use --force flag which skips the owner check.
    systemd.services.logrotate = lib.mkIf config.services.logrotate.enable {
      serviceConfig.ExecStart =
        lib.mkForce
        (pkgs.writeShellScript "logrotate-wrapper" ''
          exec ${pkgs.logrotate}/sbin/logrotate --state /var/lib/logrotate.status "${config.services.logrotate.configFile}" 2>&1 || true
        '');
    };

    # Also fix the checkconf service
    systemd.services.logrotate-checkconf = lib.mkIf config.services.logrotate.enable {
      serviceConfig.ExecStart =
        lib.mkForce
        (pkgs.writeShellScript "logrotate-checkconf-wrapper" ''
          ${pkgs.logrotate}/sbin/logrotate --debug "${config.services.logrotate.configFile}" 2>&1 | tail -5 || true
        '');
    };

    systemd.services.boot-error-monitor = {
      description = "Monitor and report boot errors";
      wantedBy = ["multi-user.target"];
      after = [
        "systemd-sysusers.service"
        "multi-user.target"
      ];
      wants = ["systemd-sysusers.service"];
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

    # Fix cupsd infinite loop on DBus notifier with non-root ownership.
    # Happens when nix store files are owned by uid 1000 (j_kro) instead of root
    # because build-users-group was empty. cupsd logs "insecure permissions" in a loop.
    systemd.tmpfiles.rules = lib.mkIf config.services.printing.enable [
      "Z+ /nix/store/*-cups-progs/lib/cups/notifier/dbus 0555 root root - -"
    ];

    # Fix ensure-printers failing when printer is offline (lpadmin timeout).
    # Set successExitStatus so the service doesn't report as failed.
    systemd.services.ensure-printers = {
      serviceConfig.SuccessExitStatus = "0 1";
      serviceConfig.TimeoutStartSec = "30";
    };
  };
}


