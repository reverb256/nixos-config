# Systemd service helper functions
# Reduces boilerplate for common systemd service patterns
{
  lib,
  pkgs,
  ...
}: rec {
  /*
  Create a oneshot systemd service configuration

  # Example
  mkOneshotService {
    description = "My one-shot service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    script = "/path/to/script";
  }
  */
  mkOneshotService = {
    description,
    after ? [],
    wantedBy ? [],
    before ? [],
    script,
    path ? [],
    environment ? {},
    user ? null,
    workingDirectory ? null,
    serviceConfig ? {},
  }: {
    inherit description after wantedBy before;
    serviceConfig =
      {
        Type = "oneshot";
        ExecStart = script;
      }
      // (lib.optionalAttrs (user != null) {User = user;})
      // (lib.optionalAttrs (workingDirectory != null) {WorkingDirectory = workingDirectory;})
      // (lib.optionalAttrs (path != []) {Path = path;})
      // (lib.optionalAttrs (environment != {}) {Environment = environment;})
      // serviceConfig;
  };

  /*
  Create a simple systemd service configuration

  # Example
  mkSimpleService {
    description = "My simple service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    execStart = "${pkgs.my-package}/bin/my-daemon";
  }
  */
  mkSimpleService = {
    description,
    after ? [],
    wantedBy ? [],
    execStart,
    environment ? {},
    user ? null,
    workingDirectory ? null,
    restart ? "on-failure",
    serviceConfig ? {},
  }: {
    inherit description after wantedBy;
    serviceConfig =
      {
        Type = "simple";
        ExecStart = execStart;
        Restart = restart;
      }
      // (lib.optionalAttrs (user != null) {User = user;})
      // (lib.optionalAttrs (workingDirectory != null) {WorkingDirectory = workingDirectory;})
      // (lib.optionalAttrs (environment != {}) {Environment = environment;})
      // serviceConfig;
  };

  /*
  Create a monitoring/exporter service with common patterns

  # Example
  mkExporterService {
    name = "my-exporter";
    description = "My metrics exporter";
    port = 9100;
    execStart = "${pkgs.my-exporter}/bin/my-exporter";
  }
  */
  mkExporterService = {
    name,
    description,
    port,
    execStart,
    after ? ["network-online.target"],
    wantedBy ? ["multi-user.target"],
    user ? null,
    group ? null,
    path ? [pkgs.curl pkgs.coreutils],
  }: {
    systemd.services.${name} = {
      inherit description after wantedBy;
      serviceConfig =
        {
          Type = "simple";
          ExecStart = execStart;
        }
        // (lib.optionalAttrs (user != null) {inherit user;})
        // (lib.optionalAttrs (group != null) {inherit group;})
        // (lib.optionalAttrs (path != []) {inherit path;});
    };

    # Open firewall for the exporter
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [port];
  };

  /*
  Create a timer-based service (cron alternative)

  # Example
  mkTimerService {
    name = "my-timer";
    description = "My periodic task";
    script = "/path/to/task";
    startAt = "daily";
  }
  */
  mkTimerService = {
    name,
    description,
    script,
    startAt,
    after ? ["multi-user.target"],
    wantedBy ? ["timers.target"],
    user ? null,
    persistent ? true,
  }: {
    systemd.services.${name} = mkOneshotService {
      inherit description script after user wantedBy;
    };

    systemd.timers.${name} = {
      inherit description after wantedBy;
      timerConfig = {
        OnCalendar = startAt;
        Persistent = persistent;
      };
    };
  };
}
