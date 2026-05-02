# NixOS Module Reference — Working Examples

Complete working examples from the cluster. Use these as copy-paste templates.

## Simple Service Module

Source pattern: `modules/services/*.nix`

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.my-service;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.my-service = {
    enable = mkEnableOption "My Service";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for the web interface";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/my-service";
      description = "Data directory";
    };
  };

  config = mkIf cfg.enable {
    # State directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    # Firewall — ALWAYS use mkOptionDefault in shared modules
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];

    # Systemd service
    systemd.services.my-service = {
      description = "My Service";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe pkgs.my-package;
        Restart = "on-failure";
        RestartSec = "10s";
        WorkingDirectory = cfg.dataDir;
      };
    };
  };
}
```

## Service with Agenix Secret

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.my-service;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.my-service = {
    enable = mkEnableOption "My Service";
  };

  config = mkIf cfg.enable {
    age.secrets.my-service-env = {
      file = ../../secrets/my-service-env.age;
      owner = "my-service";
      group = "my-service";
    };

    users.users.my-service = {
      isSystemUser = true;
      group = "my-service";
    };
    users.groups.my-service = {};

    systemd.services.my-service = {
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = lib.getExe pkgs.my-package;
        EnvironmentFile = config.age.secrets.my-service-env.path;
        User = "my-service";
        Group = "my-service";
      };
    };
  };
}
```

## Service with Shell Script

```nix
systemd.services.my-service = {
  wantedBy = ["multi-user.target"];
  path = lib.makeBinPath [pkgs.bash pkgs.coreutils pkgs.curl pkgs.jq];

  serviceConfig = {
    ExecStart = pkgs.writeShellScript "my-service-start" ''
      set -euo pipefail

      # Load secrets
      export API_KEY=$(cat ${config.age.secrets.api-key.path})

      # Health check before starting
      if ! ${lib.getExe pkgs.curl} -sf http://localhost:8080/health > /dev/null 2>&1; then
        echo "Pre-start health check failed" >&2
      fi

      exec ${lib.getExe pkgs.my-package} --port 8080
    '';
    Restart = "on-failure";
    RestartSec = "5s";
  };
};
```

## Service with Timer

```nix
# Timer
systemd.timers.my-cleanup = {
  wantedBy = ["timers.target"];
  timerConfig = {
    OnCalendar = "*-*-* 03:00:00";  # Daily at 3am
    Persistent = true;
    RandomizedDelaySec = "5m";
  };
};

# Service (oneshot for timers)
systemd.services.my-cleanup = {
  script = ''
    ${lib.getExe pkgs.findutils}/bin/find ${cfg.dataDir} -name "*.tmp" -mtime +7 -delete
  '';
  serviceConfig = {
    Type = "oneshot";
    User = "my-service";
  };
};
```

## Environment File Generation

```nix
# Generate env file from config
environment.etc."my-service/config.yaml".text = lib.generators.toYAML {} {
  port = cfg.port;
  debug = cfg.debug;
  database_url = "postgres://localhost:5432/mydb";
};

# Or as JSON:
environment.etc."my-service/config.json".text =
  lib.generators.toJSON {} {
    port = cfg.port;
    features = { enable_x = true; };
  };
```
