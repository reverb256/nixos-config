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
    pathPackages ? [],
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
      // (lib.optionalAttrs (pathPackages != []) {Path = lib.makeBinPath pathPackages;})
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
    pathPackages ? [],
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
      // (lib.optionalAttrs (pathPackages != []) {Path = lib.makeBinPath pathPackages;})
      // (lib.optionalAttrs (environment != {}) {Environment = environment;})
      // serviceConfig;
  };

  /*
  Create a service with clean PATH construction using lib.makeBinPath

  # Example
  mkPathService {
    description = "My service";
    execStart = "${pkgs.my-package}/bin/my-daemon";
    pathPackages = [pkgs.bash pkgs.coreutils pkgs.curl];
  }
  */
  mkPathService = {
    description,
    execStart,
    pathPackages ? [],
    after ? ["network.target"],
    wantedBy ? ["multi-user.target"],
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
        Path = lib.makeBinPath pathPackages;
      }
      // (lib.optionalAttrs (user != null) {User = user;})
      // (lib.optionalAttrs (workingDirectory != null) {WorkingDirectory = workingDirectory;})
      // (lib.optionalAttrs (environment != {}) {Environment = environment;})
      // serviceConfig;
  };

  /*
  Create a service using lib.getExe for executable resolution

  # Example
  mkExeService {
    description = "My service";
    package = pkgs.lm_sensors;
    args = "-s";
  }
  */
  mkExeService = {
    description,
    package,
    args ? "",
    after ? ["network.target"],
    wantedBy ? ["multi-user.target"],
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
        ExecStart = lib.getExe package + (if args != "" then " " + args else "");
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

  /*
  Create a sanitized debug configuration string using lib.generators.toPretty
  Hides secrets (passwords, API keys, tokens) while showing other config

  # Example
  mkDebugConfig {
    config = {
      database = {
        host = "localhost";
        port = 5432;
        passwordFile = "/run/secrets/db-password";
      };
      apiUrl = "https://api.example.com";
      apiKey = "secret123";
    };
    secretPatterns = ["password" "apiKey" "token" "secret"];
  }
  */
  mkDebugConfig = {
    config,
    secretPatterns ? ["password" "Password" "PASSWORD" "apiKey" "api_key" "token" "Token" "TOKEN" "secret" "Secret" "SECRET"],
  }: let
    # Convert config to pretty string
    prettyConfig = lib.generators.toPretty {} config;

    # Sanitize secrets by replacing values with "***REDACTED***"
    sanitize = str:
      builtins.foldl'
        (acc: pattern: lib.replaceStrings ["${pattern} = \"[^\"]*\""] ["${pattern} = \"***REDACTED***\""] acc)
        prettyConfig
        secretPatterns;
  in {
    /*
    Get sanitized debug output as a string

    # Example
    debugOutput = mkDebugConfig {
      config = cfg;
    }.getOutput;
    */
    getOutput = sanitize prettyConfig;

    /*
    Create ExecStartPre script that logs configuration to journal
    Returns a script string suitable for systemd's ExecStartPre

    # Example
    serviceConfig.ExecStartPre = mkDebugConfig {
      config = cfg;
      serviceName = "my-service";
    }.preStartLog;
    */
    preStartLog = serviceName: ''
      ${pkgs.coreutils}/bin/env echo "[${serviceName}] Configuration:" >&2
      ${pkgs.coreutils}/bin/env echo '${sanitize prettyConfig}' >&2
      ${pkgs.coreutils}/bin/env echo "[${serviceName}] Configuration end" >&2
    '';
  };

  /*
  Add debug logging to a service configuration
  Creates ExecStartPre that logs sanitized configuration

  # Example
  mkServiceWithDebug {
    name = "my-service";
    description = "My service";
    execStart = "${pkgs.my-package}/bin/my-daemon";
    debugConfig = {
      database = { host = "localhost"; };
      apiKeyFile = "/run/secrets/api-key";
    };
  }
  */
  mkServiceWithDebug = {
    name,
    description,
    execStart,
    debugConfig ? {},
    debugEnable ? true,
    after ? ["network.target"],
    wantedBy ? ["multi-user.target"],
    pathPackages ? [],
    environment ? {},
    user ? null,
    workingDirectory ? null,
    restart ? "on-failure",
    serviceConfig ? {},
  }: let
    debugHelper = mkDebugConfig {config = debugConfig;};
  in {
    inherit description after wantedBy;
    serviceConfig =
      {
        Type = "simple";
        ExecStart = execStart;
        Restart = restart;
      }
      // (lib.optionalAttrs (user != null) {User = user;})
      // (lib.optionalAttrs (workingDirectory != null) {WorkingDirectory = workingDirectory;})
      // (lib.optionalAttrs (pathPackages != []) {Path = lib.makeBinPath pathPackages;})
      // (lib.optionalAttrs (environment != {}) {Environment = environment;})
      // (lib.optionalAttrs (debugEnable && debugConfig != {}) {
        ExecStartPre = debugHelper.preStartLog name;
      })
      // serviceConfig;
  };
}
