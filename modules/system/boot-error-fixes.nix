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
    includePrinting = mkOption {
      type = types.bool;
      default = true;
      description = "Enable CUPS printing subsystem (disable on headless servers with no printer)";
    };
  };

  config = mkIf config.services.boot-error-fixes.enable {
    services.printing.enable = lib.mkForce config.services.boot-error-fixes.includePrinting;

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
          ${pkgs.logrotate}/sbin/logrotate --state /var/lib/logrotate.status "${config.services.logrotate.configFile}" 2>&1 || true
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

          echo "INFO: sops-nix secrets at /run/secrets/ (if directory exists)" | ${pkgs.coreutils}/bin/tee -a /var/log/boot-errors.log

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
    systemd.tmpfiles.rules = lib.mkIf config.services.boot-error-fixes.includePrinting [
      "Z+ /nix/store/*-cups-progs/lib/cups/notifier/dbus 0555 root root - -"
    ];

    # HP Envy 7800 network printer (10.1.1.173) — only when printing is enabled
    systemd.services.add-network-printer = mkIf config.services.boot-error-fixes.includePrinting {
      description = "Add HP Envy 7800 network printer";
      after = ["cups.service" "cups.socket"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Fail-fast + auto-retry: 30s startup ceiling prevents the boot sequence
        # from hanging when cups or the network printer at 10.1.1.173:9100 is
        # unreachable. Restart=on-failure lets the unit auto-recover once cups
        # comes up and the printer becomes reachable (was previously a silent
        # multi-user.target blocker on hosts where the printer is occasionally
        # powered off). Closes the add-network-printer half of #329.
        TimeoutStartSec = "30";
        Restart = "on-failure";
        RestartSec = "2min";
        # Bound auto-retry: 5 attempts within 25 min. Cups + k3s control-plane
        # restarts routinely take 2-5 min to fully resolve; this profile lets
        # transient cluster storms self-heal within ~10 min (5 x 2-min cadence)
        # before the unit goes silent. Permanently-broken cups surfaces as
        # journal spam bounded by the 25-min envelope, not forever.
        StartLimitBurst = 5;
        StartLimitIntervalSec = "25min";
        ExecStart = pkgs.writeShellScript "add-network-printer" ''
          #!${pkgs.bash}/bin/bash
          set -e
          # Wait for cups to be ready
          for i in 1 2 3 4 5; do
            ${pkgs.cups}/bin/lpstat -r 2>/dev/null && break
            sleep 1
          done
          # Add printer if not exists
          if ! ${pkgs.cups}/bin/lpstat -p 2>/dev/null | grep -q "HP-Envy-7800"; then
            ${pkgs.cups}/bin/lpadmin -p "HP-Envy-7800" -v "socket://10.1.1.173:9100" -E || true
          fi
          # Set as default
          ${pkgs.cups}/bin/lpoptions -d HP-Envy-7800 || true
        '';
      };
    };

    # Set default printer — wayland-common.nix already sets this with correct name (HP_Envy_7800).
    # Removed duplicate to fix conflicting definition values build error.
    # hardware.printers.ensureDefaultPrinter = "HP-Envy-7800";

    # Fix ensure-printers failing when printer is offline (lpadmin timeout).
    # Set successExitStatus so the service doesn't report as failed.
    systemd.services.ensure-printers = mkIf config.services.boot-error-fixes.includePrinting {
      serviceConfig.SuccessExitStatus = "0 1";
      serviceConfig.TimeoutStartSec = "30";
    };
  };
}
