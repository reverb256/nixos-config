# Vaultwarden + FIDO/Passkeys Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Deploy Vaultwarden (self-hosted password manager) with FIDO2 WebAuthn support for 2 YubiKeys and TOTP 2FA, accessible via Tailscale VPN.

**Architecture:** Single quadlet (Podman+systemd) container with SQLite database, reverse-proxied through Caddy with Tailscale TLS termination. Secrets managed via Agenix with systemd credential mounting.

**Tech Stack:** Vaultwarden (Rust), Podman Quadlet, Caddy, Agenix, NixOS modules, WebAuthn/FIDO2, TOTP

---

## Task 1: Create Vaultwarden NixOS Module

**Files:**
- Create: `modules/services/vaultwarden.nix`

**Step 1: Create the module with quadlet configuration**

Write the complete NixOS module file:

```nix
# Vaultwarden - Self-hosted Bitwarden-compatible password manager
# FIDO2/WebAuthn support + TOTP 2FA
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.vaultwarden-module;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkMerge
    mkDefault
    ;
in {
  options.services.vaultwarden-module = {
    enable = mkEnableOption "Vaultwarden - Self-hosted password manager";

    hostName = mkOption {
      type = types.str;
      example = "vaultwarden.ts.net";
      description = "The hostname for Vaultwarden (Tailscale Magic DNS)";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/containers/vaultwarden/data";
      description = "Vaultwarden data directory (SQLite database, attachments, keys)";
    };

    port = mkOption {
      type = types.int;
      default = 8080;
      description = "Host port for Vaultwarden (container always listens on 80)";
    };

    adminTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/agenix/vaultwarden-admin-token";
      description = "Path to file containing admin token (use Agenix)";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # AGENIX SECRET MOUNTING
    # ============================================================================
    age.secrets.vaultwarden-admin-token = mkIf (cfg.adminTokenFile != null) {
      file = ../../secrets/vaultwarden-admin-token.age;
      mode = "440";
      owner = "root";
      group = "root";
      symlinks = false;
    };

    # ============================================================================
    # PODMAN QUADLET CONFIGURATION
    # ============================================================================
    systemd.packages = [pkgs.vaultwarden];

    # Create data directory with correct permissions
    systemd.tmpfiles.settings."vaultwarden" = {
      "${cfg.dataDir}" = {
        d = {
          mode = "700";
          user = "root";
          group = "root";
        };
      };
    };

    # Generate quadlet file from NixOS configuration
    environment.etc."containers/systemd/vaultwarden.container".text = ''
      [Unit]
      Description=Vaultwarden Password Manager
      After=network-online.target caddy.service
      Wants=caddy.service

      [Container]
      Image=docker.io/vaultwarden/server:latest
      ContainerName=vaultwarden
      PublishPort=${toString cfg.port}:80
      Volume=${cfg.dataDir}:/data:Z
      Environment=WEBSOCKET_ENABLED=true
      Environment=WEBSOCKET_ADDRESS=0.0.0.0
      Environment=LOG_LEVEL=info
      ${lib.optionalString (cfg.adminTokenFile != null) "SetCredential=admin-token:%d/ADMIN_TOKEN_FILE"}
      AutoUpdate=registry
      Label=io.containers.autoupdate=registry

      [Service]
      Restart=always
      RestartSec=10
      MemoryMax=512M
      CPUQuota=50%
      NoNewPrivileges=true
      PrivateTmp=true
      ProtectSystem=strict
      ProtectHome=true
      ReadOnlyPaths=/usr
      ReadWritePaths=${cfg.dataDir}

      [Install]
      WantedBy=multi-user.target default.target
    '';

    # ============================================================================
    # SYSTEMD CREDENTIALS FOR ADMIN TOKEN
    # ============================================================================
    systemd.services.vaultwarden = mkIf (cfg.adminTokenFile != null) {
      serviceConfig.LoadCredential = [
        "ADMIN_TOKEN_FILE:${cfg.adminTokenFile}"
      ];
      environment.ADMIN_TOKEN = "";
    };

    # ============================================================================
    # CADDY REVERSE PROXY INTEGRATION
    # ============================================================================
    services.caddy-module.${cfg.hostName} = {
      reverseProxy = "localhost:${toString cfg.port}";
      reverseProxyPort = 80;
    };

    # ============================================================================
    # FIREWALL (only allow Tailscale interface)
    # ============================================================================
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [cfg.port];

    # ============================================================================
    # PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [vaultwarden];
  };
}
```

**Step 2: Verify the module syntax**

Run: `nix eval .#nixosConfigurations.zephyr.config.services.vaultwarden-module.enable 2>&1 || true`
Expected: Either `false` (module not yet enabled) or successful evaluation

**Step 3: Commit the module**

```bash
git add modules/services/vaultwarden.nix
git commit -m "feat: add Vaultwarden module with quadlet + Caddy integration"
```

---

## Task 2: Add Agenix Secret Definition

**Files:**
- Modify: `secrets.nix`
- Create: `secrets/vaultwarden-admin-token.age` (generated)

**Step 1: Add secret to secrets.nix**

Read the current secrets.nix to find the zephyr public key reference:

```bash
grep -A5 "zephyr" /etc/nixos/secrets.nix | head -20
```

Expected output: Shows the public key variable name (likely `zephyr` or similar)

Add the vaultwarden admin token secret:

```nix
# Add to the secrets attribute set in secrets.nix
"vaultwarden-admin-token".age = {
  publicKeys = [zephyr];  # Use the actual key variable name from your file
};
```

**Step 2: Generate a secure admin token**

```bash
# Generate 512-bit random token (base64 encoded)
openssl rand -base64 48 | tr -d '\n=' | tee /tmp/vaultwarden-admin-token.txt
```

Expected output: 64-character random string (e.g., `aB3xK9mN2pQ7rT4vW8yX1zC5dF6gH0jK3mN5pQ7rS9tU1wY2...`)

**Step 3: Encrypt the secret with agenix**

```bash
# Navigate to nixos directory
cd /etc/nixos

# Encrypt the secret
agenix --edit secrets/vaultwarden-admin-token.age
```

Then paste the token content from `/tmp/vaultwarden-admin-token.txt`

Expected: File created at `secrets/vaultwarden-admin-token.age`

**Step 4: Verify secret file exists**

```bash
ls -la secrets/vaultwarden-admin-token.age
```

Expected: File exists with non-zero size

**Step 5: Clean up temporary file**

```bash
shred -u /tmp/vaultwarden-admin-token.txt
```

**Step 6: Commit the secret definition**

```bash
git add secrets.nix secrets/vaultwarden-admin-token.age
git commit -m "feat: add Vaultwarden admin token secret"
```

---

## Task 3: Enable Vaultwarden on Zephyr

**Files:**
- Modify: `hosts/zephyr/configuration.nix`

**Step 1: Add vaultwarden-module to zephyr configuration**

Read the current zephyr configuration to find where other services are enabled:

```bash
grep -n "services\." /etc/nixos/hosts/zephyr/configuration.nix | head -20
```

Add the vaultwarden module configuration:

```nix
# Add to hosts/zephyr/configuration.nix
# ============================================================================
# VAULTWARDEN - Self-hosted password manager
# ============================================================================
services.vaultwarden-module = {
  enable = true;
  hostName = "vaultwarden.ts.net";  # Tailscale Magic DNS
  dataDir = "/var/lib/containers/vaultwarden/data";
  port = 8080;
  adminTokenFile = "/run/agenix/vaultwarden-admin-token";
};
```

**Step 2: Verify the configuration is valid**

```bash
nix eval .#nixosConfigurations.zephyr.config.services.vaultwarden-module.enable
```

Expected output: `true`

**Step 3: Commit the configuration change**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "feat: enable Vaultwarden service on Zephyr"
```

---

## Task 4: Build and Test Configuration

**Step 1: Run flake check**

```bash
just test
```

Expected output: `all tests passed` or similar success message

If fails: Check error messages for:
- Undefined variables in vaultwarden.nix
- Missing imports in configuration.nix
- Syntax errors in Nix expressions

**Step 2: Verify colmena can build**

```bash
cd /etc/nixos && nix run .#apps.x86_64-linux.colmena -- build --on zephyr
```

Expected output: Successful build with closure sizes

**Step 3: Deploy to local system**

```bash
just switch
```

Expected output: `switch complete` or similar

If fails: Check journalctl for service errors

**Step 4: Verify systemd service was created**

```bash
systemctl list-units | grep vaultwarden
```

Expected output: Shows `vaultwarden.service` loaded

**Step 5: Verify quadlet file was generated**

```bash
cat /etc/containers/systemd/vaultwarden.container
```

Expected output: Shows the quadlet configuration

**Step 6: Start the service**

```bash
sudo systemctl start vaultwarden
```

**Step 7: Check service status**

```bash
sudo systemctl status vaultwarden
```

Expected output: Service is `active (running)` or `activating`

If failed: Check logs with `journalctl -u vaultwarden -n 50`

**Step 8: Verify container is running**

```bash
podman ps | grep vaultwarden
```

Expected output: Shows `vaultwarden` container running

**Step 9: Verify data directory was created**

```bash
ls -la /var/lib/containers/vaultwarden/data/
```

Expected output: Shows `db.sqlite3` and other files created by Vaultwarden

**Step 10: Test admin endpoint access**

```bash
curl -I http://localhost:8080/admin
```

Expected output: `401 Unauthorized` (admin token not provided) or `404` (endpoint requires token)

**Step 11: Save the admin token for initial setup**

```bash
# Decrypt the admin token for use
agenix -d secrets/vaultwarden-admin-token.age > /tmp/vaultwarden-admin.txt
cat /tmp/vaultwarden-admin.txt  # Save this securely!
# After setup: shred -u /tmp/vaultwarden-admin.txt
```

**Step 12: Commit successful deployment**

```bash
git add -A
git commit -m "test: Vaultwarden deployed successfully"
```

---

## Task 5: Configure WebAuthn and FIDO2

**Prerequisites:** Service running, accessible via browser

**Step 1: Access Vaultwarden web UI**

Open browser to: `https://vaultwarden.ts.net/`

Expected: Vaultwarden web interface loads (Tailscale TLS)

**Step 2: Create initial user account**

- Click "Create account"
- Enter email and master password
- Note: Password must be strong (Vaultwarden enforces this)

**Step 3: Enable WebAuthn in Vaultwarden settings**

As the user, navigate to:
- Settings → Security → Two-step Login
- Click "Manage" next to "WebAuthn"

**Step 4: Register YubiKey 1 (Primary)**

- Click "Add WebAuthn Security Key"
- Enter a name: "YubiKey 1 - Primary"
- Touch YubiKey when prompted

Expected: YubiKey 1 registered successfully

**Step 5: Register YubiKey 2 (Backup)**

- Click "Add WebAuthn Security Key" again
- Enter a name: "YubiKey 2 - Backup"
- Touch the second YubiKey when prompted

Expected: YubiKey 2 registered successfully

**Step 6: Enable TOTP as backup 2FA**

- Navigate to Settings → Security → Two-step Login
- Click "Manage" next to "Authenticator App"
- Scan QR code with authenticator app (Authy, Google Authenticator, etc.)
- Enter 6-digit code to verify

Expected: TOTP enabled successfully

**Step 7: Verify login flow**

1. Log out of Vaultwarden
2. Log in with master password
3. When prompted for 2FA:
   - Choose WebAuthn
   - Touch YubiKey 1
   - Should log in successfully

**Step 8: Test backup YubiKey**

1. Log out again
2. Log in with master password
3. Choose WebAuthn
4. Use YubiKey 2 instead

Expected: Backup key works identically

**Step 9: Test TOTP fallback**

1. Log out
2. Log in with master password
3. Choose "Authenticator App" instead of WebAuthn
4. Enter 6-digit code from authenticator app

Expected: TOTP code works as backup

**Step 10: Document successful setup**

```bash
cat >> /etc/nixos/docs/VAULTWARDEN_SETUP.md << 'EOF'
# Vaultwarden Setup Complete

## Access
- URL: https://vaultwarden.ts.net/
- Admin Token: [stored in Agenix]

## Security Keys Registered
- YubiKey 1 (Primary)
- YubiKey 2 (Backup)

## 2FA Methods Enabled
- WebAuthn/FIDO2 (YubiKeys)
- TOTP (Authenticator App)

## Data Location
- SQLite Database: /var/lib/containers/vaultwarden/data/db.sqlite3
- Encryption Keys: /var/lib/containers/vaultwarden/data/rsa_key.*
- Attachments: /var/lib/containers/vaultwarden/data/attachments

## Backup Important Files
```bash
# Backup entire data directory
tar czf /backup/vaultwarden-$(date +%Y%m%d).tar.gz /var/lib/containers/vaultwarden/data/
```

## Recovery
If YubiKey 1 is lost:
1. Log in using YubiKey 2
2. Settings → Security → Two-step Login
3. Remove lost key, register new replacement

If both YubiKeys are lost:
1. Log in using TOTP code
2. Re-register security keys
EOF
```

**Step 11: Commit documentation**

```bash
git add docs/VAULTWARDEN_SETUP.md
git commit -m "docs: add Vaultwarden setup and recovery documentation"
```

---

## Task 6: Configure Bitwarden Clients

**Prerequisites:** Vaultwarden running, user account created

**Step 1: Install Bitwarden client on desktop**

On Zephyr:
```bash
# Bitwarden CLI is already in packages via vaultwarden module
# For GUI, use Flathub or distro package
```

**Step 2: Configure desktop client**

1. Open Bitwarden client
2. Click "Environment" (settings icon)
3. Select "Self-hosted"
4. Enter server URL: `https://vaultwarden.ts.net`
5. Log in with email and master password
6. Approve 2FA with YubiKey 1

**Step 3: Install mobile app**

1. Install Bitwarden from App Store/Play Store
2. Open app, tap "Log in"
3. Gear icon → Environment → Self-hosted
4. Enter: `https://vaultwarden.ts.net`
5. Log in with credentials + YubiKey

**Step 4: Test browser extension**

1. Install Bitwarden browser extension
2. Click extension icon
3. Gear → Environment → Self-hosted
4. Enter: `https://vaultwarden.ts.net`
5. Log in

**Step 5: Verify sync works**

1. Add a new login on desktop
2. Check mobile app - should sync automatically
3. Check browser extension - should appear

**Step 6: Commit client setup notes**

```bash
cat >> /etc/nixos/docs/VAULTWARDEN_SETUP.md << 'EOF'
## Client Setup

### Desktop
- Server: https://vaultwarden.ts.net
- 2FA: WebAuthn with YubiKey

### Mobile
- Install from app store
- Server: https://vaultwarden.ts.net
- 2FA: WebAuthn (if device supports) or TOTP

### Browser Extension
- Environment: Self-hosted
- Server URL: https://vaultwarden.ts.net
EOF

git add docs/VAULTWARDEN_SETUP.md
git commit -m "docs: add client setup instructions"
```

---

## Task 7: Add Backup Automation

**Files:**
- Create: `scripts/backup-vaultwarden.sh` (optional)

**Step 1: Create backup script**

```bash
cat > /etc/nixos/scripts/backup-vaultwarden.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/backup/vaultwarden"
DATA_DIR="/var/lib/containers/vaultwarden/data"
DATE=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

echo "Backing up Vaultwarden data..."
tar czf "$BACKUP_DIR/vaultwarden-$DATE.tar.gz" -C "$DATA_DIR" .

echo "Backup complete: $BACKUP_DIR/vaultwarden-$DATE.tar.gz"

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "vaultwarden-*.tar.gz" -mtime +7 -delete
EOF

chmod +x /etc/nixos/scripts/backup-vaultwarden.sh
```

**Step 2: Add to systemd timer (optional)**

```bash
cat >> /etc/nixos/hosts/zephyr/configuration.nix << 'EOF'
# Vaultwarden backup
systemd.timers.vaultwarden-backup = {
  wantedBy = ["timers.target"];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};

systemd.services.vaultwarden-backup = {
  script = "/etc/nixos/scripts/backup-vaultwarden.sh";
  serviceConfig.Type = "oneshot";
};
EOF
```

**Step 3: Test backup script**

```bash
sudo /etc/nixos/scripts/backup-vaultwarden.sh
```

Expected: Backup file created in `/backup/vaultwarden/`

**Step 4: Commit backup setup**

```bash
git add scripts/backup-vaultwarden.sh
git commit -m "feat: add Vaultwarden backup automation"
```

---

## Task 8: Final Verification and Cleanup

**Step 1: Verify all services are running**

```bash
systemctl status vaultwarden caddy
podman ps
```

Expected: All services active

**Step 2: Test full login flow from all devices**

- Desktop: ✓
- Mobile: ✓
- Browser: ✓

**Step 3: Test YubiKey 2 (backup)**

Use backup key to verify it works

**Step 4: Test TOTP fallback**

Use authenticator app code to verify it works

**Step 5: Verify database is being written to**

```bash
sqlite3 /var/lib/containers/vaultwarden/data/db.sqlite3 "SELECT COUNT(*) FROM ciphers;"
```

Expected: Returns number of items in vault (0 or more)

**Step 6: Check logs for any errors**

```bash
journalctl -u vaultwarden --since "1 hour ago" | grep -i error || echo "No errors found"
```

Expected: No errors or only non-critical warnings

**Step 7: Run full cluster test**

```bash
just test
```

Expected: All tests pass

**Step 8: Final commit**

```bash
git add -A
git commit -m "feat: Vaultwarden + FIDO2/Passkeys implementation complete"
```

---

## Post-Setup Checklist

After deployment, verify these items:

- [ ] Vaultwarden accessible at `https://vaultwarden.ts.net/`
- [ ] User account created
- [ ] YubiKey 1 registered as primary
- [ ] YubiKey 2 registered as backup
- [ ] TOTP enabled as fallback
- [ ] Desktop client configured and syncing
- [ ] Mobile app configured and syncing
- [ ] Browser extension working
- [ ] Backup script tested
- [ ] Admin token saved securely
- [ ] Recovery procedure documented

---

## Rollback Procedure

If anything goes wrong:

1. **Stop the service:**
   ```bash
   sudo systemctl stop vaultwarden
   sudo systemctl disable vaultwarden
   ```

2. **Revert configuration:**
   ```bash
   git checkout HEAD~1 -- hosts/zephyr/configuration.nix
   just switch
   ```

3. **Clean up data (if needed):**
   ```bash
   sudo rm -rf /var/lib/containers/vaultwarden
   ```

4. **Restore from backup:**
   ```bash
   sudo tar xzf /backup/vaultwarden/vaultwarden-YYYYMMDD.tar.gz -C /
   ```

---

**End of Implementation Plan**
