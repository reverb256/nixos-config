---
name: agenix-secrets
description: Manage age-encrypted secrets in NixOS configurations using agenix. Always use this skill whenever you need to add API keys, tokens, passwords, certificates, or any sensitive data to your NixOS systems. Use when you see keywords like: "secret", "password", "token", "api key", "credential", "encrypted", "agenix", ".age file", "secrets.nix", "age.secrets", or when working with /run/agenix paths. This skill handles the complete multi-host workflow across zephyr, forge, nexus, and sentry: creating encrypted files with agenix, managing user and host keys, updating secrets.nix, configuring age.secrets in host configuration.nix files, and rebuilding systems. Even if you just need to view existing secrets or validate configuration, use this skill.
---

# Agenix Secrets Manager

A comprehensive skill for managing encrypted secrets across multiple NixOS hosts using agenix. Agenix encrypts secrets with age public keys and decrypts them at build time to `/run/agenix/*`.

## Quick Reference Card

| I want to... | Command |
|--------------|---------|
| **Add a secret for one host** | `python3 scripts/add_secret.py name "value"` |
| **Add a secret for multiple hosts** | `python3 scripts/add_secret_multihost.py name "value" --hosts zephyr,forge,nexus` |
| **Setup host keys** | `python3 scripts/setup_host_keys.py --all-known-hosts` |
| **Validate configuration** | `python3 scripts/validate.py` |
| **List all secrets** | `python3 scripts/list_secrets.py` |
| **Re-encrypt all secrets** | `python3 scripts/rekey_secrets.py` |
| **Test decrypt a secret** | `python3 scripts/test_secrets.py secret-name` |

## When to use this skill

- Adding new API keys, tokens, passwords, or certificates
- Managing secrets across multiple hosts (zephyr, forge, nexus, sentry)
- Setting up host keys for automated decryption
- Re-encrypting secrets when keys change
- Sharing secrets between hosts vs. host-specific secrets
- Validating secret configurations
- Debugging secret deployment issues

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Your Workflow                           │
│  1. Create encrypted secret (with user + host keys)             │
│  2. Register in secrets.nix                                     │
│  3. Add age.secrets.* to host configuration.nix                 │
│  4. Rebuild target hosts                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         How It Works                            │
│                                                                  │
│  secrets.nix ──> agenix encrypts ──> secret.age                  │
│      │                           │                              │
│      │                           ▼                              │
│      │                    encrypted file                        │
│      │                           │                              │
│      │                           ▼                              │
│      └──> configuration.nix ──> build ──> /run/agenix/secret   │
│                                  (decrypted at runtime)         │
└─────────────────────────────────────────────────────────────────┘
```

## Key Concepts

### Secret Types

1. **User secrets** - encrypted with your age key only
2. **Host secrets** - encrypted with host SSH keys (automatic decryption)
3. **Shared secrets** - encrypted with multiple host/user keys
4. **Service secrets** - for specific services (API keys, tokens, etc.)

### Multi-Host Setup

Your infrastructure has 4 hosts:
- **zephyr** - RTX 3090, Quest Pro, AI inference
- **forge** - Build server
- **nexus** - Services host
- **sentry** - Monitoring/host

Each host has its own `configuration.nix` that declares which secrets it needs.

### File Locations

- `/etc/nixos/secrets/*.age` - Encrypted secret files
- `/etc/nixos/secrets.nix` - Maps secrets to public keys
- `/etc/nixos/hosts/{host}/configuration.nix` - Declares age.secrets.* per host
- `/run/agenix/*` - Decrypted secrets at runtime
- `scripts/` - Automation scripts for common workflows

## Quick Reference

### Get host public key
```bash
# Get host's SSH public key in age format
ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
```

### Create a new secret
```bash
# Use the helper script
python3 /etc/nixos/skills/agenix-secrets/scripts/add_secret.py \
  secret-name "secret-value" \
  --hosts zephyr,forge \
  --owner j_kro
```

### Rekey all secrets
```bash
# Re-encrypt with new keys
python3 /etc/nixos/skills/agenix-secrets/scripts/rekey_all.py
```

### Validate configuration
```bash
# Check all secrets are properly configured
python3 /etc/nixos/skills/agenix-secrets/scripts/validate.py
```

## Workflows

### Workflow 1: Add a User-Only Secret

For secrets only you can access (personal API keys):

```bash
# 1. Create encrypted file
cd /etc/nixos
echo "my-secret-token" | \
  RULES=/etc/nixos/secrets.nix \
  agenix -e secrets/my-token.age -i ~/.age/key.txt

# 2. Add to secrets.nix
# Add both entries (for relative path compatibility):
"my-token.age".publicKeys = [users.j_kro];
"secrets/my-token.age".publicKeys = [users.j_kro];

# 3. Configure in target host's configuration.nix
age.secrets.my-token = {
  file = "${inputs.self}/secrets/my-token.age";
  mode = "440";
  owner = "j_kro";
};

# 4. Rebuild the host
sudo nixos-rebuild switch --flake .#zephyr
```

### Workflow 2: Add a Multi-Host Secret

For secrets needed on multiple hosts (shared service credentials):

```bash
# 1. Get host public keys first
# On zephyr:
ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
# Output: age1l4v... (copy this)

# Repeat for forge, nexus, sentry

# 2. Create encrypted file with multiple recipients
cd /etc/nixos
echo "shared-secret" | \
  RULES=/etc/nixos/secrets.nix \
  agenix -e secrets/shared.age -i ~/.age/key.txt \
  --age-plugin-address=age1l4v... \
  --age-plugin-address=age1xyz...  # other host keys

# 3. Add to secrets.nix with all recipients
"shared.age".publicKeys = [
  users.j_kro
  hosts.zephyr
  hosts.forge
  hosts.nexus
];

# 4. Configure in each host's configuration.nix
# (Add to zephyr/configuration.nix, forge/configuration.nix, etc.)
age.secrets.shared = {
  file = "${inputs.self}/secrets/shared.age";
  mode = "440";
  owner = "service-user";
};

# 5. Rebuild all hosts
sudo nixos-rebuild switch --flake .#zephyr
# ... repeat for other hosts
```

### Workflow 3: Set Up Host Keys (One-Time)

Enable automatic secret decryption on hosts:

```bash
# 1. On each host, get the SSH host public key in age format
sudo ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
# Copy the output (age1l4v...)

# 2. Update secrets.nix to include host keys
let
  users = {
    j_kro = "age1p98yp8w64rdugp03332gxnz5q2vcnucn69cs5qm6s2l2u7epqfcqmu2pqe";
  };
  hosts = {
    zephyr = "age1l4v...";  # from zephyr
    forge = "age1xyz...";   # from forge
    nexus = "age1abc...";   # from nexus
    sentry = "age1def...";  # from sentry
  };
in {
  # Existing secrets...
}

# 3. Re-encrypt secrets with host keys
cd /etc/nixos
RULES=/etc/nixos/secrets.nix agenix -r -i ~/.age/key.txt

# 4. Update secrets.nix entries to include host keys
"api-key.age".publicKeys = [
  users.j_kro
  hosts.zephyr
  hosts.forge
];
```

### Workflow 4: Rekey After Adding New Host

When adding a new host or rotating keys:

```bash
# 1. Add new host to secrets.nix
hosts {
  # ... existing hosts
  new-host = "age1newkey...";
}

# 2. Re-encrypt all secrets with new key
cd /etc/nixos
RULES=/etc/nixos/secrets.nix agenix -r -i ~/.age/key.txt

# 3. Update each secret's entry in secrets.nix to include new host
"secret.age".publicKeys = [
  users.j_kro
  hosts.zephyr
  hosts.forge
  hosts.new-host  # Add to all secrets this host needs
];
```

## Automation Scripts

The skill includes helper scripts in `scripts/`:

### add_secret.py
Add a new secret with automatic configuration updates:
```bash
python3 scripts/add_secret.py <name> <value> [options]
  --hosts HOSTS    Comma-separated list of hosts (default: zephyr only)
  --owner USER     Owner user (default: j_kro)
  --group GROUP    Group for permissions (optional)
  --no-rebuild     Skip rebuild step
```

### add_secret_multihost.py
Add a secret to multiple hosts with proper key management:
```bash
python3 scripts/add_secret_multihost.py <name> <value>
  --hosts zephyr,forge,nexus
  --shared          Same secret on all hosts
  --per-host        Unique secret per host
```

### setup_host_keys.py
One-time setup to add host keys to secrets.nix:
```bash
python3 scripts/setup_host_keys.py
  --host zephyr --key "age1l4v..."
  --host forge --key "age1xyz..."
```

### rekey_all.py
Re-encrypt all secrets after key changes:
```bash
python3 scripts/rekey_all.py
```

### validate.py
Check all secrets are properly configured:
```bash
python3 scripts/validate.py
  --verbose    Show detailed issues
```

### list_secrets.py
Show all secrets and which hosts can access them:
```bash
python3 scripts/list_secrets.py
  --by-host    Group by host
```

## Configuration Examples

### secrets.nix Structure

```nix
{
  description = "Agenix secrets configuration";

  # User keys
  users = {
    j_kro = "age1p98yp8w64rdugp03332gxnz5q2vcnucn69cs5qm6s2l2u7epqfcqmu2pqe";
  };

  # Host keys (for automatic decryption)
  hosts = {
    zephyr = "age1l4vzephyrkey...";
    forge = "age1l4vforgekey...";
    nexus = "age1l4vnexuskey...";
    sentry = "age1l4vsentrykey...";
  };

  # Secret definitions
  "api-key.age".publicKeys = [users.j_kro hosts.zephyr];
  "secrets/api-key.age".publicKeys = [users.j_kro hosts.zephyr];

  "shared-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.forge
    hosts.nexus
  ];
  "secrets/shared-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.forge
    hosts.nexus
  ];
}
```

### configuration.nix Declaration

```nix
# In /etc/nixos/hosts/zephyr/configuration.nix
age.secrets.api-key = {
  file = "${inputs.self}/secrets/api-key.age";
  mode = "440";
  owner = "j_kro";
  group = "ai-inference";  # Optional: for service access
};

# For systemd services
age.secrets.service-token = {
  file = "${inputs.self}/secrets/service-token.age";
  mode = "440";
  owner = "service-user";
  group = "service-group";
};

# For environment variables in services
age.secrets.db-password = {
  file = "${inputs.self}/secrets/db-password.age";
  mode = "440";
  owner = "postgres";
};
```

### Using Secrets in Configuration

```nix
# Read secret into configuration
services.my-service = {
  apiKey = builtins.readFile /run/agenix/api-key;
};

# For systemd services
systemd.services.my-service = {
  serviceConfig.EnvironmentFile = /run/agenix/my-service-env;
};

# For shell scripts
systemd.services.my-script = {
  script = ''
    export API_KEY=$(cat /run/agenix/api-key)
    # Use API_KEY
  '';
};
```

## Troubleshooting

### "attribute 'xxx.age' missing"
**Cause**: Secret not registered in secrets.nix
**Fix**: Add both `"xxx.age"` and `"secrets/xxx.age"` entries to secrets.nix

### "path does not exist" error
**Cause**: agenix can't find secrets.nix
**Fix**: Run from `/etc/nixos` or set `RULES=/etc/nixos/secrets.nix`

### "No recipient keys"
**Cause**: No public keys for this secret in secrets.nix
**Fix**: Add at least one public key (user or host) to the secret's entry

### Secret not decrypting on host
**Cause**: Host key not added to secret's publicKeys
**Fix**: Add `hosts.hostname` to the secret's publicKeys list and re-encrypt

### Permission denied accessing /run/agenix/*
**Cause**: Wrong owner/group in age.secrets.* declaration
**Fix**: Set correct `owner` and `group` in configuration.nix

## Best Practices

1. **Always add both path entries** to secrets.nix:
   - `"secret.age"` - for running from `/etc/nixos/secrets/`
   - `"secrets/secret.age"` - for running from `/etc/nixos/`

2. **Use host keys for production**: Add host keys so secrets decrypt automatically during builds

3. **Group related secrets**: Use `group` in age.secrets.* to share secrets between services

4. **Validate before deploying**: Run `validate.py` to catch configuration issues

5. **Test decryption**: Use `test_secrets.py` to verify secrets can be decrypted

6. **Document secret purpose**: Add comments in secrets.nix explaining what each secret is for

7. **Rotate regularly**: Rekey secrets periodically and when adding/removing hosts

8. **Keep secrets.nix in git**: It's safe to commit (only contains public keys)

9. **Never commit .age files**: Already in .gitignore, but double-check

10. **Use descriptive names**: `service-api-key.age` not `key1.age`

## Security Considerations

- **Age keys**: Store your private key (`~/.age/key.txt`) securely
- **Host keys**: SSH host keys are less secure than dedicated age keys, but convenient
- **Secrets at rest**: Encrypted with multiple recipients for redundancy
- **Secrets at runtime**: Decrypted to `/run/agenix/*` (in RAM, not disk)
- **Permissions**: Always use restrictive mode (`440` or `400`)
- **Access control**: Only grant owner/group to users/services that need it

## Advanced Patterns

### Per-Environment Secrets
```nix
# Different secrets for dev/prod
"api-key-dev.age".publicKeys = [users.j_kro hosts.zephyr];
"api-key-prod.age".publicKeys = [users.j_kro hosts.forge hosts.nexus];
```

### Conditional Secret Loading
```nix
# Only load secret on specific host
age.secrets.special = lib.mkIf (config.networking.hostName == "zephyr") {
  file = "${inputs.self}/secrets/special.age";
  mode = "440";
  owner = "j_kro";
};
```

### Secret Dependencies
```nix
# Ensure service only starts if secret exists
systemd.services.my-service = {
  after = ["agenix.service"];
  requires = ["agenix.service"];
};
```

## Migration Guide

### From single-host to multi-host
1. Generate SSH host keys for each host
2. Add hosts to secrets.nix
3. Re-encrypt secrets with host keys
4. Update secrets.nix entries
5. Add age.secrets.* to each host's configuration.nix

### Adding a new host
1. Get host's SSH public key: `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`
2. Add host to secrets.nix
3. Re-encrypt secrets that need this host
4. Create host's configuration.nix with required age.secrets.*
5. Rebuild new host
