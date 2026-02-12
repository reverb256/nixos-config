# Security Configuration

**Status**: SECURE (Score: 8.5/10)
**Last Updated**: 2026-02-12

## Authentication

- SSH: Key-based only (`PasswordAuthentication = false`)
- Root login: Disabled (`PermitRootLogin = "no"`)
- Sudo: Passwordless for j_kro (YubiKey planned)

## Secrets Management

- Tool: Agenix (age encryption)
- Location: `/run/agenix/`
- Files: API keys, tokens, credentials

## Service Security

### Service Accounts
- `mining`: No sudo, video/render groups only
- `lobster`: No sudo, no docker, no wheel
- All services use `isSystemUser = true`

### Network Binding
- All services bind to `127.0.0.1` by default
- External access via nginx reverse proxy only

### Systemd Hardening
```nix
NoNewPrivileges = true;
ProtectSystem = "strict";
ProtectHome = true;
PrivateTmp = true;
```

## Network Security

- Firewall: Default deny, explicit allows only
- DNS: Unbound with DoT (Quad9/Google)
- VPN: Tailscale mesh for cluster management

## Controlled Access

| Access | User | Purpose |
|--------|------|---------|
| Passwordless sudo | j_kro | Mining control from desktop |
| Docker/Podman | j_kro | Development containers |
| Tailscale admin | j_kro | VPN management |

## Incident Response

See: [INCIDENT_RESPONSE_PLAN.md](INCIDENT_RESPONSE_PLAN.md)
