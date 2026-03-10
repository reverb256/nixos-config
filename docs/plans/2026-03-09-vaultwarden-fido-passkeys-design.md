# Vaultwarden + FIDO/Passkeys Implementation Design

**Date:** 2026-03-09
**Author:** Claude Code Agent
**Status:** Approved

---

## Goal

Deploy Vaultwarden (self-hosted Bitwarden-compatible password manager) with FIDO2 WebAuthn support for 2 YubiKeys (primary + backup) and TOTP 2FA, accessible exclusively via Tailscale VPN.

---

## Architecture

### Approach: Single Quadlet + Caddy Reverse Proxy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ZEPHYR HOST (Local)                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  vaultwarden.service (quadlet-generated)                           │   │
│  │  ├── Image: docker.io/vaultwarden/server:latest                    │   │
│  │  ├── Port: 8080 (host) → 80 (container)                           │   │
│  │  ├── Volume: /var/lib/containers/vaultwarden/data → /data          │   │
│  │  └── Admin Token (via Agenix + systemd credentials)                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Caddy Reverse Proxy: vaultwarden.ts.net:443 → localhost:8080      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────▼────────────┐
                    │   TAILSCALE VPN        │
                    │  vaultwarden.ts.net    │
                    └────────────────────────┘
```

### Tech Stack
- **Vaultwarden:** Rust-based Bitwarden API server
- **Database:** SQLite (zero config, single file)
- **Deployment:** Podman Quadlet (systemd-managed containers)
- **Reverse Proxy:** Caddy with Tailscale TLS
- **Secrets:** Agenix (Age encryption)
- **2FA:** WebAuthn (FIDO2) + TOTP

---

## Components

### 1. NixOS Module (`modules/services/vaultwarden.nix`)
- Quadlet configuration template
- Systemd service with security hardening
- Caddy integration
- Agenix secret mounting

### 2. Agenix Secret (`secrets/vaultwarden-admin-token.age`)
- Admin token for `/admin` endpoint
- Auto-generated at deployment

### 3. Caddy Reverse Proxy
- Route: `vaultwarden.ts.net:443 → localhost:8080`
- OWASP security headers (inherited)
- Tailscale TLS termination

### 4. Data Persistence
- Location: `/var/lib/containers/vaultwarden/data`
- Contents:
  - `db.sqlite3` - SQLite database
  - `attachments/` - Encrypted file storage
  - `rsa_key.*` - End-to-end encryption keys
  - `sends/` - Bitwarden Send temporary files

---

## Data Flow

### Registration & Login
```
┌─────────────┐     WebAuthn      ┌──────────────┐     TOTP        ┌─────────────┐
│  Bitwarden  │ ─────────────────>│  Vaultwarden │ ──────────────>│  Authenticator│
│   Client    │ <─────────────────│              │ <──────────────│     App      │
└─────────────┘      Challenge    └──────────────┘      Verify      └─────────────┘
       │                                                              │
       │  YubiKey 1 (Primary) OR YubiKey 2 (Backup)                   │
       └──────────────────────────────────────────────────────────────┘
```

### Sync Flow
```
Bitwarden Client → Tailscale VPN → Caddy → Vaultwarden → SQLite DB
     (encrypted)        (TLS)      (443→8080)    (API)         (storage)
```

---

## Security Considerations

### Transport Security
- **Tailscale TLS:** End-to-end encryption from client to Zephyr
- **Caddy:** HTTP/2 + security headers
- **Vaultwarden:** E2E encryption (client-side AES-256)

### Authentication Layers
1. **Tailscale:** VPN access control (who can reach the service)
2. **Vaultwarden:** Master password + 2FA (WebAuthn + TOTP)
3. **Admin Panel:** Additional `ADMIN_TOKEN` required

### Systemd Hardening
- `NoNewPrivileges=true` - Prevent privilege escalation
- `ProtectSystem=strict` - Read-only system directories
- `PrivateTmp=true` - Isolated /tmp
- `MemoryMax=512M` - Resource limit
- `ReadOnlyPaths=/usr` - Minimal filesystem access

### Backup Strategy
- **Critical files:** `db.sqlite3`, `rsa_key.*`
- **Backup location:** `/var/lib/containers/vaultwarden/data`
- **Frequency:** Automated via existing backup scripts

---

## FIDO/Passkeys Setup

### WebAuthn Configuration
- **Relying Party:** `vaultwarden.ts.net`
- **Origins:** `https://vaultwarden.ts.net`
- **YubiKey 1:** Registered as primary security key
- **YubiKey 2:** Registered as backup security key

### Passkeys Support
- Vaultwarden supports passkeys natively via WebAuthn
- Same flow as FIDO2 keys
- Browser/passkey manager stores credentials

### TOTP (2FA Backup)
- Enabled via Vaultwarden Settings → Two-step Login
- Scan QR code with authenticator app
- Required as second factor after WebAuthn

---

## Implementation Checklist

- [ ] Create `modules/services/vaultwarden.nix` module
- [ ] Add admin token to `secrets.nix`
- [ ] Generate `vaultwarden-admin-token.age`
- [ ] Enable `vaultwarden-module` on Zephyr
- [ ] Add Caddy route for `vaultwarden.ts.net`
- [ ] Build and test (`just test`)
- [ ] Deploy (`just switch`)
- [ ] Verify container starts (`podman ps`)
- [ ] Access admin panel to create initial user
- [ ] Configure WebAuthn in Vaultwarden settings
- [ ] Register YubiKey 1 (primary)
- [ ] Register YubiKey 2 (backup)
- [ ] Enable TOTP 2FA
- [ ] Test full login flow

---

## Rollback Plan

If deployment fails:
1. `just rollback` - Revert to previous generation
2. `podman stop vaultwarden` - Stop container manually
3. `rm /var/lib/containers/vaultwarden` - Clean up data (if needed)

---

## Next Steps

After deployment:
1. Create first user account via web UI
2. Set up organization for shared items (optional)
3. Configure backup automation for data directory
4. Import existing passwords (if migrating from another manager)

---

**End of Design**
