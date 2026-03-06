---
name: add-service
description: Add a new systemd service module to modules/services/
---

# Add New Service

Create a new systemd service module following NixOS conventions.

## Step 1: Create Service Module

Create the service at: `modules/services/SERVICE-NAME/SERVICE-NAME.nix`

## Template

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.SERVICE-NAME;
in
{
  options.services.SERVICE-NAME = {
    enable = lib.mkEnableOption "SERVICE-NAME service";

    # Add service-specific options here
    # port = lib.mkOption {
    #   type = lib.types.port;
    #   default = 8080;
    #   description = "Port to listen on";
    # };
  };

  config = lib.mkIf cfg.enable {
    # Add packages
    environment.systemPackages = with pkgs; [
      # package-name
    ];

    # Add systemd service
    systemd.services.SERVICE-NAME = {
      description = "SERVICE-NAME service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.package-name}/bin/binary";
        Restart = "on-failure";
        DynamicUser = true;
      };
    };

    # Optional: Open firewall ports
    # networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

## Step 2: Register the Module

Add to `modules/default.nix`:

```nix
services.SERVICE-NAME = import ./services/SERVICE-NAME/SERVICE-NAME.nix;
```

## Step 3: Enable on Host

Add to `hosts/HOSTNAME/configuration.nix`:

```nix
services.SERVICE-NAME.enable = true;
```

## Step 4: Rebuild

```bash
nix flake check
sudo nixos-rebuild switch --flake .#HOSTNAME
```

## Service Management Commands

```bash
# Check status
systemctl status SERVICE-NAME

# View logs
journalctl -u SERVICE-NAME -f

# Restart service
systemctl restart SERVICE-NAME

# Enable/disable
systemctl enable SERVICE-NAME
systemctl disable SERVICE-NAME
```

## Example: Simple Web Service

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.my-web-service;
in
{
  options.services.my-web-service = {
    enable = lib.mkEnableOption "my web service";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.my-web-service = {
      description = "My Web Service";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.my-web-package}/bin/my-web-server --port ${toString cfg.port}";
        Restart = "on-failure";
        DynamicUser = true;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```
