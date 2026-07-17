---
name: add-service
description: Add create new systemd service module NixOS. Use for: add service, create service, new service, systemd, daemon, background service, add module.
disable-model-invocation: false
---

# Add New Systemd Service

## Trigger Keywords
add service, create service, new service, systemd, daemon, background process, service module, add to modules

## Step 1: Ask User for Details
**Question 1**: What is the service name? (e.g., "redis", "my-api")
**Question 2**: Which host should enable this? (default: zephyr)
**Question 3**: What package/executable runs the service?

## Step 2: Create Module File

**Location**: `modules/services/SERVICE-NAME/SERVICE-NAME.nix`

## Step 3: Fill Template (replace placeholders)

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.SERVICE-NAME;
in
{
  options.services.SERVICE-NAME = {
    enable = lib.mkEnableOption "SERVICE-NAME service";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      PACKAGE-NAME
    ];

    systemd.services.SERVICE-NAME = {
      description = "SERVICE-NAME service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.PACKAGE-NAME}/bin/BINARY-NAME";
        Restart = "on-failure";
        DynamicUser = true;
      };
    };
  };
}
```

## Step 4: Register Module

**File**: `modules/default.nix`
**Add line**: `services.SERVICE-NAME = import ./services/SERVICE-NAME/SERVICE-NAME.nix;`

## Step 5: Enable on Host

**File**: `hosts/HOSTNAME/configuration.nix`
**Add line**: `services.SERVICE-NAME.enable = true;`

## Step 6: Rebuild

```bash
nix flake check
sudo nixos-rebuild switch --flake .#HOSTNAME
```

## Few-Shot Examples

### Example 1: Simple service (no options)
```
User: Add a redis service
Model: [CREATE] modules/services/redis/redis.nix
      [REGISTER] in modules/default.nix
      [ENABLE] services.redis.enable = true;
      [REBUILD] nix flake check && nixos-rebuild switch
```

### Example 2: Service with port option
```
User: Create a web service on port 3000
Model: [CREATE] modules/services/my-web/my-web.nix
      [ADD] port option (default 3000)
      [ADD] firewall rule for port
      [REBUILD]
```

### Example 3: Background daemon
```
User: Add a monitoring daemon
Model: [CREATE] modules/services/monitor-daemon/monitor-daemon.nix
      [SET] wantedBy = multi-user.target
      [SET] Restart = always
      [REBUILD]
```

## Common Service Patterns

### Pattern 1: Network Service (needs firewall)
```nix
networking.firewall.allowedTCPPorts = [ 8080 ];
```

### Pattern 2: Database (needs state directory)
```nix
serviceConfig = {
  StateDirectory = "SERVICE-NAME";
  ExecStart = "... --data /var/lib/SERVICE-NAME";
};
```

### Pattern 3: Service with config file
```nix
settings = {
  configFile = pkgs.writeText "config.yaml" ''
    key: value
  '';
};
serviceConfig.ExecStart = "... --config ${cfg.settings.configFile}";
```

## Module Structure Reference

```
modules/
└── services/
    └── SERVICE-NAME/
        ├── default.nix       (optional - exports)
        ├── SERVICE-NAME.nix  (main module)
        └── README.md         (optional docs)
```

## Service Commands (for user reference)

```bash
systemctl status SERVICE-NAME     # Check if running
journalctl -u SERVICE-NAME -f     # View logs
systemctl restart SERVICE-NAME    # Restart
systemctl enable SERVICE-NAME     # Start on boot
```
