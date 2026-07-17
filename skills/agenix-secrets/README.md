# Agenix Secrets Manager - Complete Skill Documentation

## Overview

This skill provides comprehensive management of age-encrypted secrets across multiple NixOS hosts (zephyr, forge, nexus, sentry). It handles the complete workflow from creating encrypted secrets to deploying them across your infrastructure.

## What This Skill Does

- ✅ Add new secrets (single-host or multi-host)
- ✅ Setup host keys for automatic decryption
- ✅ Re-encrypt secrets after key changes
- ✅ Validate configuration consistency
- ✅ List secrets and their distribution
- ✅ Debug secret deployment issues
- ✅ Guide through multi-host setup

## Skill Architecture

```
agenix-secrets/
├── SKILL.md                 # Main skill documentation
├── README.md               # This file - overview
├── scripts/                # Automation scripts
│   ├── README.md          # Script usage guide
│   ├── add_secret.py      # Add single-host secret
│   ├── add_secret_multihost.py  # Add multi-host secrets
│   ├── setup_host_keys.py # Setup host keys
│   ├── rekey_secrets.py   # Re-encrypt all secrets
│   ├── validate.py        # Validate configuration
│   ├── list_secrets.py    # Show secret distribution
│   └── test_secrets.py    # Test decryption
└── evals/
    └── evals.json         # Test cases for skill validation
```

## How It Works

### The Agenix Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         YOUR WORKFLOW                              │
│                                                                     │
│  1. Create encrypted secret file (.age)                             │
│     ↓                                                               │
│  2. Register in secrets.nix (who can decrypt)                      │
│     ↓                                                               │
│  3. Declare in host configuration.nix (age.secrets.*)               │
│     ↓                                                               │
│  4. Rebuild host (secrets decrypt to /run/agenix/*)                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         WHAT HAPPENS                               │
│                                                                     │
│  secrets.nix ──> agenix encrypts ──> secret.age                     │
│      │                              │                               │
│      │                              ▼                               │
│      │                       encrypted file                         │
│      │                              │                               │
│      │                              ▼                               │
│      └──> configuration.nix ──> build ──> /run/agenix/secret       │
│                                       (decrypted at runtime)        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Concepts

**Secret Types:**
- **User secrets**: Encrypted with your age key only
- **Host secrets**: Encrypted with host SSH keys (auto-decrypt)
- **Shared secrets**: Encrypted with multiple host/user keys

**File Locations:**
- `/etc/nixos/secrets/*.age` - Encrypted secret files
- `/etc/nixos/secrets.nix` - Maps secrets to public keys
- `/etc/nixos/hosts/{host}/configuration.nix` - Declares age.secrets.*
- `/run/agenix/*` - Decrypted secrets at runtime

## When to Use This Skill

**Trigger Keywords:**
- "secret", "password", "token", "api key", "credential"
- "encrypted", "agenix", ".age file"
- "secrets.nix", "age.secrets"
- "/run/agenix" paths

**Trigger Scenarios:**
- Adding new API keys or tokens
- Setting up new hosts
- Rotating encryption keys
- Debugging secret deployment
- Auditing secret distribution

## Scripts Quick Reference

| Script | Purpose | Example |
|--------|---------|---------|
| `bootstrap.sh` | Initial setup | `./skills/agenix-secrets/bootstrap.sh` |
| `common.py` | Shared utilities | Imported by other scripts |
| `add_secret.py` | Single-host secret | `python3 scripts/add_secret.py my-key "value"` |
| `add_secret_multihost.py` | Multi-host secrets | `python3 scripts/add_secret_multihost.py shared "value" --hosts zephyr,forge` |
| `setup_host_keys.py` | Setup host keys | `python3 scripts/setup_host_keys.py --all-known-hosts` |
| `validate.py` | Validate config | `python3 scripts/validate.py --verbose` |
| `list_secrets.py` | Show distribution | `python3 scripts/list_secrets.py --matrix` |
| `rekey_secrets.py` | Re-encrypt all | `python3 scripts/rekey_secrets.py` |
| `test_secrets.py` | Test decrypt | `python3 scripts/test_secrets.py my-key` |

## Quick Start

### First-Time Setup

Run the bootstrap script to initialize your environment:

```bash
# 1. Run bootstrap (one-time setup)
./skills/agenix-secrets/bootstrap.sh

# 2. Follow prompts to configure dependencies and setup
```

The bootstrap script will:
- Install dependencies (agenix, ssh-to-age)
- Initialize configuration file
- Validate your age key
- Validate secrets.nix
- Guide you through next steps

## Common Workflows

### Workflow 1: Add a New Secret

```bash
# 1. Add the secret
python3 scripts/add_secret.py my-api-key "sk-abc123"

# 2. Validate
python3 scripts/validate.py

# 3. Rebuild
sudo nixos-rebuild switch --flake .#zephyr

# 4. Use the secret
cat /run/agenix/my-api-key
```

### Workflow 2: Share Secret Across Hosts

```bash
# 1. Add to multiple hosts
python3 scripts/add_secret_multihost.py \
  db-password "pass123" \
  --hosts zephyr,forge,nexus

# 2. Validate
python3 scripts/validate.py

# 3. Rebuild all hosts
sudo nixos-rebuild switch --flake .#zephyr
sudo nixos-rebuild switch --flake .#forge
sudo nixos-rebuild switch --flake .#nexus
```

### Workflow 3: Setup Multi-Host

```bash
# 1. Setup all host keys
python3 scripts/setup_host_keys.py --all-known-hosts

# 2. Re-encrypt existing secrets
python3 scripts/rekey_secrets.py

# 3. Update secrets.nix entries to include host keys
# (Edit secrets.nix manually)

# 4. Rebuild all hosts
for host in zephyr forge nexus sentry; do
  sudo nixos-rebuild switch --flake .#$host
done
```

## Testing

The skill includes 8 test cases covering:

1. **add-single-secret**: Adding a single-host secret
2. **setup-host-keys**: Setting up host keys
3. **shared-secret-multihost**: Sharing secrets across hosts
4. **debug-missing-attribute**: Debugging common errors
5. **validate-configuration**: Validating configuration
6. **list-secrets-distribution**: Listing secrets
7. **add-new-host**: Adding a new host to the cluster
8. **rotate-user-key**: Rotating user encryption keys

Run tests with the skill-creator framework.

## Security Best Practices

1. **✅ DO commit .age files**: They're encrypted and safe to track in git for reproducibility
2. **❌ NEVER commit**: Decrypted files, private keys, or plaintext backups
3. **Keep private key secure**: Your `~/.age/key.txt` is sensitive - never share it
4. **Use restrictive permissions**: Always use `mode = "440"`, plus `owner` AND `group`
5. **Validate before deploying**: Run `validate.py` before rebuilding
6. **Rotate keys regularly**: Re-encrypt after adding/removing hosts
7. **Use host keys for production**: Enables automatic decryption at build time
8. **Document secret purpose**: Add comments in secrets.nix
9. **Use multi-recipient encryption**: Encrypt with both user AND host keys for redundancy

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| "attribute missing" | Secret not in secrets.nix | Add both path entries |
| "path does not exist" | Wrong directory | Run from /etc/nixos |
| "No recipient keys" | Empty publicKeys | Add user or host keys |
| "Permission denied" | Wrong owner/group | Fix in configuration.nix |

**Need host key setup?** See [HOST_KEY_SETUP_GUIDE.md](./HOST_KEY_SETUP_GUIDE.md) for complete instructions on enabling automatic decryption.

## Advanced Patterns

### Per-Environment Secrets
```nix
# Development - only zephyr
"api-key-dev.age".publicKeys = [users.j_kro hosts.zephyr];
"api-key-prod.age".publicKeys = [users.j_kro hosts.forge hosts.nexus];
```

### Best Practice: Always Include Group
```nix
# ALWAYS specify mode, owner, AND group
age.secrets.my-api-key = {
  file = "${inputs.self}/secrets/my-api-key.age";
  mode = "440";       # Read-only for owner
  owner = "j_kro";   # User who owns the file
  group = "users";   # Group access (always include!)
};
```

### Conditional Secret Loading
```nix
age.secrets.special = lib.mkIf (config.networking.hostName == "zephyr") {
  file = "${inputs.self}/secrets/special.age";
  mode = "440";
  owner = "j_kro";
  group = "users";
};
```

## Contributing

When adding new features:
1. Update SKILL.md documentation
2. Add script to scripts/ directory
3. Make it executable: `chmod +x script.py`
4. Add test case to evals/evals.json
5. Update this README

## Resources

- [Agenix GitHub](https://github.com/ryantm/agenix)
- [Age Encryption](https://age-encryption.org/)
- [NixOS Secrets](https://nixos.org/manual/nixos/stable/options.html#opt-age.secrets)

## License

Part of the NixOS configuration. Follows the same license as the main configuration.
