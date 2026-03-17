# Agenix Multi-Host Secret Deployment Guide

**Last Updated:** 2026-03-16
**Cluster:** Zephyr (control), Forge, Nexus, Sentry
**Secrets System:** Agenix with age encryption

---

## Overview

This guide explains how encrypted secrets are deployed across the 4-host NixOS cluster.

`★ Insight ─────────────────────────────────────`
**Multi-Host Secret Deployment Architecture**
1. **Colmena transfers** `.age` files to all hosts during `just deploy`
2. **Host keys** in `secrets.nix` determine which hosts can decrypt which secrets
3. **age.secrets declarations** in each host config control what gets deployed
`─────────────────────────────────────────────────`

---

## Secret Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                    1. SECRET CREATION                             │
│  - User creates encrypted .age file with agenix                   │
│  - Adds publicKeys mapping to secrets.nix                         │
│  - Declares in agenix-secrets-registry or host config              │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    2. GIT COMMIT                                  │
│  - .age files are encrypted (safe to commit)                       │
│  - secrets.nix contains only public keys (safe)                    │
│  - Changes tracked in version control                             │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    3. COLMENA DEPLOYMENT                           │
│  - `just deploy` or colmena apply                                  │
│  - .age files transferred to ALL hosts                             │
│  - Nix store rebuilt on each host                                  │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    4. DECRYPTION AT BUILD                         │
│  - Each host decrypts secrets encrypted with its key               │
│  - agenix-rekey service verifies decryption                        │
│  - Secrets appear at /run/agenix/<name>                            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## How Secrets Reach Hosts

### Mechanism 1: Colmena File Transfer

During `just deploy`, Colmena:

1. Reads all `.age` files from `/etc/nixos/secrets/`
2. Includes them in the Nix closure
3. Transfers to target hosts via SSH
4. Places them in the Nix store

**Key Point:** ALL `.age` files go to ALL hosts, regardless of which host needs them. This is safe because they're encrypted.

### Mechanism 2: Selective Decryption

Each host can ONLY decrypt secrets that include its key in `secrets.nix`:

```nix
# In secrets.nix
hosts = {
  zephyr = "age1l4v...";   # Zephyr's SSH host key converted to age
  forge = "age1xyz...";    # Forge's SSH host key converted to age
  nexus = "age1abc...";    # Nexus's SSH host key converted to age
  sentry = "age1def...";   # Sentry's SSH host key converted to age
};

# Example: XMRig API token needed on 3 hosts
"xmrig-api-token.age".publicKeys = [
  users.j_kro      # You (can decrypt manually)
  hosts.zephyr     # Zephyr can decrypt
  hosts.nexus      # Nexus can decrypt
  hosts.sentry     # Sentry can decrypt
  # NOT hosts.forge - Forge doesn't need this secret
];
```

**Result:** When Forge builds, it receives `xmrig-api-token.age` but CANNOT decrypt it (not in its publicKeys). The file remains encrypted and unused.

---

## Per-Host Configuration

### Using the Central Registry (Recommended)

The `agenix-secrets-registry` module provides category-based selection:

```nix
# In hosts/zephyr/configuration.nix
{
  services.agenix-secrets-registry = {
    enable = true;
    aiServices = true;      # AI API keys (HuggingFace, LM Studio, etc.)
    monitoring = true;      # Grafana, Sentry
    storage = true;         # Garage S3, RPC
    mining = true;          # XMRig API tokens
    cloud = true;           # Tailscale, Cloudflare, Akash
    selfHosting = true;     # Nextcloud, Vaultwarden, GlitchTip
  };
}
```

```nix
# In hosts/nexus/configuration.nix (storage + mining node)
{
  services.agenix-secrets-registry = {
    enable = true;
    mining = true;          # XMRig API tokens
    storage = true;         # Garage S3 cluster (Nexus is a storage node)
  };

  # Override specific secret permissions for mining service
  age.secrets.xmrig-always-api-token = {
    mode = "440";
    owner = "mining";
    group = "mining";
  };
}
```

```nix
# In hosts/sentry/configuration.nix (monitoring node)
{
  services.agenix-secrets-registry = {
    enable = true;
    mining = true;          # XMRig API token
  };

  # Override specific secret permissions for mining service
  age.secrets.xmrig-api-token = {
    mode = "440";
    owner = "mining";
    group = "mining";
  };
}
```

```nix
# In hosts/forge/configuration.nix (compute + mining node)
# Note: No secrets currently configured. Add registry when needed.
# For future use (Akash provider):
# services.agenix-secrets-registry = {
#   enable = true;
#   cloud = true;           # Tailscale, Cloudflare, Akash
# };
```

### Manual Declaration (For Special Cases)

```nix
# Direct age.secrets declaration in host config
age.secrets.my-special-secret = {
  file = "${inputs.self}/secrets/my-special-secret.age";
  mode = "440";
  owner = "service-user";
  group = "service-group";
};
```

---

## Current Secret Distribution

| Secret | Zephyr | Forge | Nexus | Sentry | Purpose |
|--------|--------|-------|-------|--------|---------|
| **AI Services** ||||||||
| huggingface-token.age | ✅ | ❌ | ❌ | ❌ | Hugging Face API |
| lm-studio-api-key.age | ✅ | ❌ | ❌ | ❌ | LM Studio local API |
| zai-api-key.age | ✅ | ❌ | ❌ | ❌ | ZAI coding API |
| pollinations-api-key.age | ✅ | ❌ | ❌ | ❌ | Pollinations AI |
| kilo-api-key.age | ✅ | ❌ | ❌ | ❌ | Kilo AI service |
| context7-api-key.age | ✅ | ❌ | ❌ | ❌ | Context7 docs |
| spacebot-telegram-token.age | ✅ | ❌ | ❌ | ❌ | Spacebot Telegram |
| **Mining** ||||||||
| xmrig-api-token.age | ✅ | ❌ | ✅ | ✅ | XMRig control (all Ryzen nodes) |
| xmrig-always-api-token.age | ✅ | ❌ | ❌ | ❌ | Always-on instance |
| xmrig-flexible-api-token.age | ✅ | ❌ | ❌ | ❌ | Pause-able instance |
| **Storage** ||||||||
| garage-rpc-secret.age | ✅ | ❌ | ✅ | ✅ | Garage cluster auth |
| garage-s3-secret-key.age | ✅ | ❌ | ❌ | ❌ | Garage S3 admin |
| **Cloud/Infra** ||||||||
| tailscale-api-key.age | ✅ | ❌ | ❌ | ❌ | Tailscale auth |
| cloudflared-token.age | ✅ | ❌ | ❌ | ❌ | Cloudflare tunnel |
| akash-provider-key.age | ✅ | ❌ | ❌ | ❌ | Akash GPU provider |
| switch-admin.age | ✅ | ❌ | ❌ | ❌ | Network switches |
| **Monitoring** ||||||||
| grafana-admin.age | ✅ | ❌ | ❌ | ❌ | Grafana dashboard |
| sentry-dsn.age | ✅ | ❌ | ❌ | ❌ | Error tracking |
| **Self-Hosted** ||||||||
| nextcloud-admin.age | ✅ | ❌ | ❌ | ❌ | Nextcloud admin |
| vaultwarden-admin-token.age | ✅ | ❌ | ❌ | ❌ | Vaultwarden admin |
| glitchtip-db-password.age | ✅ | ❌ | ❌ | ❌ | GlitchTip DB |
| glitchtip-secret-key.age | ✅ | ❌ | ❌ | ❌ | GlitchTip Django |

---

## Adding Secrets To New Hosts

### Scenario: Adding a Secret to an Existing Host

```bash
# 1. Get the host's SSH public key in age format
ssh forge "sudo cat /etc/ssh/ssh_host_ed25519_key.pub" | ssh-to-age
# Output: age1xyz...

# 2. Add host to secrets.nix (if not already there)
hosts.forge = "age1xyz...";

# 3. Add host to secret's publicKeys
"my-secret.age".publicKeys = [
  users.j_kro
  hosts.zephyr
  hosts.forge     # Add Forge here
];

# 4. Re-encrypt the secret
RULES=/etc/nixos/secrets.nix agenix -r -i ~/.age/key.txt -e secrets/my-secret.age

# 5. Deploy to Forge
just deploy --on forge
```

### Scenario: Adding a New Host to the Cluster

```bash
# 1. Collect new host's SSH key
ssh new-host "sudo cat /etc/ssh/ssh_host_ed25519_key.pub" | ssh-to-age

# 2. Add to secrets.nix hosts section
hosts.new-host = "age1newkey...";

# 3. For each secret the new host needs, add to publicKeys
"shared-secret.age".publicKeys = [
  users.j_kro
  hosts.zephyr
  hosts.new-host    # Add to all needed secrets
];

# 4. Re-encrypt ALL secrets
RULES=/etc/nixos/secrets.nix agenix -r -i ~/.age/key.txt

# 5. Deploy to new host
just deploy --on new-host
```

---

## Verifying Secret Deployment

### Check Which Secrets a Host Can Access

```bash
# On the host
ls -la /run/agenix/

# Or use the validation script
python3 skills/agenix-secrets/scripts/validate.py --verbose
```

### Check Secret Distribution Matrix

```bash
python3 skills/agenix-secrets/scripts/list_secrets.py --matrix
```

### Test Decryption

```bash
# Test a specific secret
sudo cat /run/agenix/my-secret

# Verify permissions
stat /run/agenix/my-secret
```

---

## Troubleshooting

### Secret Not Appearing on Host

**Symptoms:** `/run/agenix/my-secret` doesn't exist

**Possible Causes:**
1. Host key not in secret's `publicKeys` in `secrets.nix`
2. Secret not declared in host's `age.secrets.*`
3. Secret not re-encrypted after adding host key

**Solution:**
```bash
# 1. Check secrets.nix includes host
grep "hosts.$(hostname)" secrets.nix

# 2. Check secret is declared
grep "age.secrets.my-secret" hosts/$(hostname)/configuration.nix

# 3. Re-encrypt and redeploy
RULES=/etc/nixos/secrets.nix agenix -r -i ~/.age/key.txt
just deploy --on $(hostname)
```

### Permission Denied Accessing Secret

**Symptoms:** `Permission denied` when reading `/run/agenix/*`

**Solution:**
```nix
# Check age.secrets declaration has correct owner/group
age.secrets.my-secret = {
  file = "${inputs.self}/secrets/my-secret.age";
  mode = "440";       # Readable by owner and group
  owner = "service-user";
  group = "service-group";  # ALWAYS include group
};
```

### Build Fails with "attribute missing"

**Symptoms:** `error: attribute 'xxx.age' missing`

**Cause:** Secret in `secrets.nix` but file doesn't exist, OR only one path entry exists

**Solution:**
```bash
# 1. Check .age file exists
ls -la secrets/xxx.age

# 2. Check BOTH path entries in secrets.nix
grep "xxx.age" secrets.nix
# Should see BOTH:
#   "xxx.age".publicKeys = [...]
#   "secrets/xxx.age".publicKeys = [...]
```

---

## Security Best Practices

1. **✅ DO commit .age files** - They're encrypted and safe for reproducibility
2. **❌ NEVER commit** plaintext secrets, private keys, or unencrypted backups
3. **✅ ALWAYS use host keys** for production - enables automated builds
4. **✅ ALWAYS specify mode, owner, AND group** in age.secrets declarations
5. **✅ Validate before deploying** - Run `validate.py` to catch issues
6. **✅ Rotate secrets regularly** - See `docs/security/secrets-rotation.md`
7. **✅ Use descriptive names** - `service-api-key.age` not `key1.age`

---

## Related Documentation

- `skills/agenix-secrets/SKILL.md` - Complete skill documentation
- `skills/agenix-secrets/README.md` - Quick reference and scripts
- `skills/agenix-secrets/HOST_KEY_SETUP_GUIDE.md` - Host key setup
- `docs/security/secrets-rotation.md` - Rotation procedures
- `docs/security/SECURITY_AUDIT_REPORT.md` - Security audit findings
