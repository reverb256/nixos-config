# NixOS Module Development Standards

**Version:** 1.0
**Last Updated:** 2026-03-24
**Purpose:** Guide for developing consistent, maintainable NixOS modules

---

## ExecStart Declaration Patterns

### Simple Executable with Arguments

```nix
# ✅ PREFERRED
serviceConfig.ExecStart = lib.getExe pkgs.lm_sensors + " -s";

# ❌ AVOID
serviceConfig.ExecStart = "${pkgs.lm_sensors}/bin/sensors -s";
```

### Simple Script Execution

```nix
# ✅ PREFERRED
serviceConfig.ExecStart = lib.getExe pkgs.python3 + " /etc/my-service/script.py";

# ❌ AVOID
serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 /etc/my-service/script.py";
```

### Complex Multi-Line Scripts

```nix
# ✅ PREFERRED
ExecStart = pkgs.writeShellScript "my-service" ''
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
  fi
  echo "Starting my-service..."
  ${lib.getExe pkgs.my-package} --config "$CONFIG_FILE"
'';

# ❌ AVOID
ExecStart = "${pkgs.bash}/bin/bash -c 'if [ ! -f $CONFIG_FILE ]; then echo \"Configuration file not found\"; exit 1; fi; ${pkgs.my-package}/bin/my-package --config $CONFIG_FILE'";
```

---

## PATH Construction Patterns

### Systemd Service PATH

```nix
# ✅ PREFERRED
serviceConfig.Path = lib.makeBinPath [pkgs.bash pkgs.coreutils pkgs.curl];

# ❌ AVOID
serviceConfig.Path = "${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.curl}/bin";
```

### Shell Script PATH

```nix
# ✅ PREFERRED
export PATH="${lib.makeBinPath [pkgs.bash pkgs.perl pkgs.curl]}:$PATH"

# ❌ AVOID
export PATH="${pkgs.bash}/bin:${pkgs.perl}/bin:${pkgs.curl}/bin:$PATH"
```

---

## Systemd Helper Functions

Use helper functions from `modules/lib/systemd-helpers.nix` when possible:

### mkExeService - Simple Executable Services

```nix
systemd.services.my-service = mkExeService {
  description = "My service";
  package = pkgs.lm_sensors;
  args = "-s";
};
```

### mkPathService - Services with Custom PATH

```nix
systemd.services.my-service = mkPathService {
  description = "My service";
  execStart = lib.getExe pkgs.my-package + " --daemon";
  pathPackages = [pkgs.bash pkgs.coreutils pkgs.curl];
};
```

### mkSimpleService - Generic Simple Service

```nix
systemd.services.my-service = mkSimpleService {
  description = "My service";
  execStart = lib.getExe pkgs.my-package + " --arg1 --arg2";
  environment = {
    "ENV_VAR" = "value";
  };
};
```

---

## Module Structure Template

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.my-service;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.my-service = {
    enable = mkEnableOption "My Service";

    package = mkOption {
      type = types.package;
      default = pkgs.my-package;
      description = "Package to use for my-service";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for my-service";
    };

    pathPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Packages to add to PATH";
    };
  };

  config = mkIf cfg.enable {
    # Use mkOptionDefault for extensible options
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];

    systemd.services.my-service = {
      description = "My Service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe cfg.package + " --port " + toString cfg.port;
        Restart = "on-failure";
        RestartSec = "10s";

        # Use lib.makeBinPath for PATH construction
        Path = lib.makeBinPath cfg.pathPackages;
      };
    };
  };
}
```

---

## Common Patterns

### Conditional Package Inclusion

```nix
buildInputs = [ pkgs.package1 ]
  ++ lib.optional cfg.enableFeature pkgs.package2
  ++ lib.optional cfg.enableOther pkgs.package3;
```

### Conditional Attributes

```nix
serviceConfig = {
  Type = "simple";
  ExecStart = lib.getExe cfg.package;
}
// lib.optionalAttrs (cfg.user != null) { User = cfg.user; }
// lib.optionalAttrs (cfg.group != null) { Group = cfg.group; }
// lib.optionalAttrs (cfg.workingDirectory != null) { WorkingDirectory = cfg.workingDirectory; };
```

### Conditional List Items

```nix
systemd.tmpfiles.rules = [
  "d /var/lib/my-service 0755 my-service my-service -"
] ++ lib.optional cfg.enableCache "d /var/cache/my-service 0755 my-service my-service -";
```

---

## Testing & Validation

### Pre-Commit Validation

```bash
# 1. Quick syntax check
just check

# 2. Build test (zephyr only)
just test

# 3. Single host deployment
just deploy zephyr
```

### Service Validation

```bash
# Check service status
systemctl status my-service

# View service logs
journalctl -xe -u my-service

# Verify ExecStart path
systemctl show my-service -p ExecStart
```

---

## Migration Checklist

When migrating existing modules to use lib functions:

- [ ] Replace `${pkgs.xxx}/bin/xxx` with `lib.getExe pkgs.xxx`
- [ ] Replace manual PATH construction with `lib.makeBinPath`
- [ ] Convert complex bash -c wrappers to `writeShellScript`
- [ ] Add `pathPackages` parameter to helper functions
- [ ] Run `just check` to validate syntax
- [ ] Test service starts successfully
- [ ] Verify service functionality
- [ ] Update documentation

---

## Resources

- **Helper Functions**: `modules/lib/systemd-helpers.nix`
- **Nixpkgs Lib Functions**: https://nixos.org/manual/nixos/stable/#chap-functions
- **Agent Guidelines**: `AGENTS.md`
- **Project Status**: `STATUS.md`
