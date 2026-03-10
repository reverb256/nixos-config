# NixOS Module Structure Documentation

This document describes the structure, patterns, and best practices for NixOS modules in this configuration.

## Module Organization

```
/etc/nixos/
├── modules/
│   ├── services/        # Service configurations (Caddy, Nextcloud, GlitchTip, etc.)
│   ├── gaming/          # Gaming-related configurations
│   └── network-constants.nix
├── hosts/               # Host-specific configurations
├── flake.nix            # Flake entry point
└── docs/                # Documentation
```

## Module Pattern Template

```nix
# Module Description
# Brief explanation of what this module does
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Module options
  options.services.<module-name> = {
    enable = lib.mkEnableOption "<service description>";

    # Add module-specific options here
  };

  # Module configuration
  config = lib.mkIf config.services.<module-name>.enable {
    # Configuration when enabled
  };
}
```

## Best Practices

### 1. Use mkIf for Conditional Configuration

Always use `lib.mkIf` to conditionally apply configuration:

```nix
config = lib.mkIf cfg.enable {
  # Configuration only applies when module is enabled
};
```

### 2. Use mkOption for Type Safety

Define all options with proper types:

```nix
port = lib.mkOption {
  type = lib.types.port;
  default = 8080;
  description = "Port for the service";
};
```

### 3. Use Agenix for Secrets

Never hardcode passwords. Use Agenix secrets:

```nix
passwordFile = lib.mkOption {
  type = lib.types.nullOr lib.types.path;
  example = "/run/agenix/service-password";
  description = "Path to file containing password";
};
```

### 4. Use ReadOnlyPaths for Secret Access

Grant services read-only access to secrets:

```nix
systemd.services.<service>.serviceConfig.ReadOnlyPaths =
  lib.optional (cfg.passwordFile != null) cfg.passwordFile;
```

### 5. Firewall Rules

Add firewall rules only when the service is enabled:

```nix
networking.firewall.allowedTCPPorts =
  lib.optional cfg.openFirewall cfg.port;
```

### Systemd Service Security Hardening Pattern

All systemd services should include:

```nix
systemd.services.<service-name> = {
  serviceConfig = {
    NoNewPrivileges = true;           # Prevent privilege escalation
    PrivateTmp = true;                # Isolate /tmp
    ProtectSystem = "strict";         # Read-only system dirs
    ProtectHome = true;               # Hide home directories
    RestrictRealtime = true;          # Prevent real-time priority abuse
    RestrictAddressFamilies = [       # Limit socket types
      "AF_UNIX" "AF_INET" "AF_INET6"  # Adjust for service needs
    ];
  };
};
```

**Exceptions:**
- Services needing raw sockets: Add "AF_PACKET"
- Services needing filesystem access: Add ReadWritePaths
- Services binding privileged ports: Add AmbientCapabilities = ["CAP_NET_BIND_SERVICE"]

## Module Examples

### Caddy Web Server Module

Located at: `/etc/nixos/modules/services/caddy.nix`

Features:
- Automatic HTTPS with Let's Encrypt
- Reverse proxy configuration
- Security headers (OWASP A05:2021)
- Systemd service hardening

### Nextcloud Module

Located at: `/etc/nixos/modules/services/nextcloud.nix`

Features:
- PostgreSQL database integration
- Redis caching
- Nginx reverse proxy
- Synapse AI command center integration
- Systemd service hardening for nextcloud-setup and php-fpm-nextcloud

### GlitchTip Module

Located at: `/etc/nixos/modules/services/glitchtip-selfhosted.nix`

Features:
- Podman container orchestration
- PostgreSQL and Redis containers
- Secret management via Agenix
- Systemd service hardening for glitchtip-web and glitchtip-worker

## Service Integration Patterns

### AI Inference Gateway Integration

Services can integrate with the AI Inference Gateway for error tracking:

```nix
services.ai-inference.sentry = lib.mkIf cfg.enableForGateway {
  enable = true;
  dsn = "http://glitchtip:${toString cfg.port}@${cfg.host}:${toString cfg.port}/1";
  environment = "production";
  tracesSampleRate = 0.1;
};
```

## Adding a New Module

1. Create the module file in `/etc/nixos/modules/services/`
2. Follow the Module Pattern Template
3. Add systemd service hardening
4. Include security best practices
5. Add documentation to this file
6. Test with `nixos-rebuild build --fast`
7. Update relevant host configurations

## Testing Checklist

- [ ] Module builds without errors: `nixos-rebuild build --fast`
- [ ] Systemd services start correctly
- [ ] Firewall rules are applied
- [ ] Secrets are properly sourced from Agenix
- [ ] Service is accessible (if applicable)
- [ ] Security hardening is in place
