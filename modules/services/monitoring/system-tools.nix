# System Monitoring Tools Module
# CLI utilities for system monitoring and debugging
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.monitoring.system-tools = {
    enable = mkEnableOption "System monitoring CLI tools";

    packageSet = mkOption {
      type = types.enum ["basic" "standard" "full"];
      default = "standard";
      description = ''
        Package set to install:
        - basic: htop, iotop, sysstat
        - standard: basic + nethogs, iftop, perf, linuxPackages.perf
        - full: standard + bpftrace, bcc-tools, strace, ltrace
      '';
    };
  };

  config = mkIf config.services.monitoring.system-tools.enable {
    # Base packages always included
    environment.systemPackages = with pkgs; [
      htop
      iotop
      sysstat
      pciutils
      usbutils
      lm_sensors
    ]
    ++ lib.optionals (config.services.monitoring.system-tools.packageSet != "basic") [
      nethogs
      iftop
      perf
    ]
    ++ lib.optionals (config.services.monitoring.system-tools.packageSet == "full") [
      bpftrace
      bcc-tools
      strace
      ltrace
    ];
  };
}
