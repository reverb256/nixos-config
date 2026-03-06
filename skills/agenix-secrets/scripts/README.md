# Agenix Secrets Manager - Automation Scripts

This directory contains helper scripts for managing agenix secrets across multiple NixOS hosts.

## Quick Reference

| Script | Purpose |
|--------|---------|
| `add_secret.py` | Add a single secret to one host |
| `add_secret_multihost.py` | Add secrets to multiple hosts |
| `setup_host_keys.py` | Setup host keys for automatic decryption |
| `rekey_secrets.py` | Re-encrypt all secrets with new keys |
| `validate.py` | Validate configuration consistency |
| `list_secrets.py` | Show secrets and which hosts can access them |
| `test_secrets.py` | Test decryption of a specific secret |

## Usage Examples

### add_secret.py - Add a single secret

Simple case: add a secret for one host (zephyr only):

```bash
python3 scripts/add_secret.py \
  my-api-key \
  "sk-abc123xyz" \
  --owner j_kro
```

### add_secret_multihost.py - Multi-host secret management

**Shared secret** (same value on multiple hosts):

```bash
python3 scripts/add_secret_multihost.py \
  shared-db-password \
  "db-pass-123" \
  --hosts zephyr,forge,nexus \
  --owner j_kro
```

**Per-host secrets** (unique value per host):

```bash
python3 scripts/add_secret_multihost.py \
  host-specific-key \
  "key-for-{hostname}" \
  --hosts zephyr,forge,nexus \
  --per-host
```

This creates:
- `host-specific-key-zephyr.age` with value "key-for-zephyr"
- `host-specific-key-forge.age` with value "key-for-forge"
- `host-specific-key-nexus.age` with value "key-for-nexus"

### setup_host_keys.py - One-time host key setup

**Setup local host:**

```bash
python3 scripts/setup_host_keys.py --local
```

**Setup remote host:**

```bash
python3 scripts/setup_host_keys.py --host zephyr
```

**Setup all hosts in cluster:**

```bash
python3 scripts/setup_host_keys.py --all-known-hosts
```

**Manual key specification:**

```bash
python3 scripts/setup_host_keys.py \
  --host zephyr=age1l4vzephyrkey... \
  --host forge=age1l4vforgekey...
```

### rekey_secrets.py - Re-encrypt all secrets

After adding new host keys or changing user keys:

```bash
python3 scripts/rekey_secrets.py
```

### validate.py - Configuration validation

**Basic validation:**

```bash
python3 scripts/validate.py
```

**Verbose output:**

```bash
python3 scripts/validate.py --verbose
```

**Test decryption (sample one secret):**

```bash
python3 scripts/validate.py --test-one
```

**Test decryption (all secrets):**

```bash
python3 scripts/validate.py --test-decrypt
```

### list_secrets.py - Show secret distribution

**List by secret name (default):**

```bash
python3 scripts/list_secrets.py
```

**List by host:**

```bash
python3 scripts/list_secrets.py --by-host
```

**Show deployment matrix:**

```bash
python3 scripts/list_secrets.py --matrix
```

**Summary only:**

```bash
python3 scripts/list_secrets.py --summary-only
```

### test_secrets.py - Test decryption

Test a specific secret can be decrypted:

```bash
python3 scripts/test_secrets.py my-api-key
```

## Common Workflows

### Workflow 1: Initial multi-host setup

```bash
# 1. Setup host keys for all hosts
python3 scripts/setup_host_keys.py --all-known-hosts

# 2. Re-encrypt existing secrets with host keys
python3 scripts/rekey_secrets.py

# 3. Validate configuration
python3 scripts/validate.py --verbose

# 4. Rebuild each host
sudo nixos-rebuild switch --flake .#zephyr
sudo nixos-rebuild switch --flake .#forge
# ... etc
```

### Workflow 2: Add a new shared secret

```bash
# 1. Add the secret to multiple hosts
python3 scripts/add_secret_multihost.py \
  shared-token \
  "token-value" \
  --hosts zephyr,forge,nexus

# 2. Validate
python3 scripts/validate.py

# 3. Rebuild affected hosts
sudo nixos-rebuild switch --flake .#zephyr
sudo nixos-rebuild switch --flake .#forge
sudo nixos-rebuild switch --flake .#nexus
```

### Workflow 3: Add a new host to existing secrets

```bash
# 1. Add new host's key to secrets.nix
python3 scripts/setup_host_keys.py --host new-host

# 2. Edit secrets.nix to add hosts.new-host to each secret's publicKeys
# (This step is manual - open secrets.nix and add hosts.new-host)

# 3. Re-encrypt all secrets
python3 scripts/rekey_secrets.py

# 4. Add age.secrets.* to new host's configuration.nix
# (Use add_secret_multihost.py or manually add)

# 5. Rebuild new host
sudo nixos-rebuild switch --flake .#new-host
```

### Workflow 4: Rotate user key

```bash
# 1. Update user key in secrets.nix
# Edit secrets.nix and change users.j_kro = "..."

# 2. Re-encrypt all secrets
python3 scripts/rekey_secrets.py

# 3. Test decryption with new key
python3 scripts/validate.py --test-decrypt

# 4. Rebuild all hosts
```

## Troubleshooting

### Script not found

Make sure you're running from `/etc/nixos`:

```bash
cd /etc/nixos
python3 scripts/validate.py
```

### Permission denied

Make scripts are executable:

```bash
chmod +x scripts/*.py
```

### ssh-to-age not found

Install it in your shell:

```bash
nix-shell -p ssh-to-age
```

Or add to your NixOS configuration.

### agenix command not found

Install agenix:

```bash
nix-shell -p agenix
```

Or ensure it's in your NixOS configuration (it should be if you're using secrets).

## File Locations Reference

| Path | Purpose |
|------|---------|
| `/etc/nixos/secrets.nix` | Secret-to-key mappings |
| `/etc/nixos/secrets/*.age` | Encrypted secret files |
| `/etc/nixos/hosts/{host}/configuration.nix` | Per-host secret declarations |
| `/run/agenix/*` | Decrypted secrets at runtime |
| `~/.age/key.txt` | Your private age key |

## Security Notes

1. **Private key**: Your `~/.age/key.txt` is sensitive. Keep it secure.
2. **Host keys**: SSH host keys are less secure than dedicated age keys but more convenient.
3. **Secrets at rest**: Encrypted with multiple recipients for redundancy.
4. **Secrets at runtime**: Decrypted to `/run/agenix/*` (RAM only, not disk).
5. **Git safety**: ✅ DO commit `.age` files - they're encrypted and safe for reproducibility
6. **secrets.nix**: Safe to commit (contains only public keys).
7. **Always specify group**: Always include `mode`, `owner`, AND `group` in declarations.
