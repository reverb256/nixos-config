{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.recovery-specialisation;
  inherit (lib) mkEnableOption mkIf;
in {
  options.services.recovery-specialisation = {
    enable = mkEnableOption "Recovery boot specialisation with verbose logging and debug shell";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.initrd-ssh-recovery.enable;
        message = "recovery-specialisation requires initrd-ssh-recovery to be enabled";
      }
    ];

    # Recovery specialisation: boot with verbose logging + debug shell
    # Select at grub: "NixOS Generation X (recovery)"
    # Or: sudo /run/current-system/specialisation/recovery/bin/switch-to-configuration test
    specialisation.recovery.configuration = {
      boot.kernelParams = [
        "systemd.log_level=debug"
        "systemd.log_target=console"
        "udev.log_priority=debug"
        "rd.systemd.debug_shell"
        "rd.emergency=reboot"
        "fbcon=scrollback:1024k"
        # Panic and lockup detection (from forge recovery)
        "panic=10"
        "panic_on_oops=1"
        "softlockup_panic=1"
        "nmi_watchdog=1"
        # Storage debug
        "rd.udev.log_priority=debug"
        "boot.shell_on_fail"
      ];

      boot.initrd.systemd.services.emergency = {
        after = ["sysroot.mount"];
        unitConfig.DefaultDependencies = false;
        serviceConfig.Type = "idle";
        serviceConfig.ExecStart = "${pkgs.systemd}/bin/reboot -f";
      };
    };
  };
}
