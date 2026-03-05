# Setting Up Automatic Secret Decryption with Host Keys

This guide walks you through setting up host keys so your NixOS hosts can automatically decrypt secrets at build time, without requiring your private age key.

## Why Set Up Host Keys?

**Without host keys (current state):**
- ❌ Requires your private key (`~/.age/key.txt`) to rebuild
- ❌ Manual intervention needed on each build
- ❌ Can't automate deployments
- ❌ Security risk: private key must be accessible

**With host keys:**
- ✅ Automatic decryption at build time
- ✅ No private key needed on hosts
- ✅ Automated deployments work
- ✅ Better security: hosts only decrypt their own secrets

## Prerequisites

You need one of these tools:
- `ssh-to-age` installed locally, OR
- SSH access to your hosts with `ssh-to-age` available via `nix-shell`

## Quick Start (Automated)

### Step 1: Collect Host Keys

Run the helper script to collect all host keys:

```bash
cd /etc/nixos
./skills/agenix-secrets/scripts/get_host_keys.sh
```

Follow the prompts to collect keys from:
- zephyr
- forge
- nexus
- sentry

The script saves keys to `/tmp/agenix-host-keys.txt`

### Step 2: Add Host Keys to secrets.nix

Edit `/etc/nixos/secrets.nix` and uncomment/add the host entries:

```nix
hosts = {
  zephyr = "age1l4v...";  # From /tmp/agenix-host-keys.txt
  forge = "age1xyz...";   # From /tmp/agenix-host-keys.txt
  nexus = "age1abc...";   # From /tmp/agenix-host-keys.txt
  sentry = "age1def...";  # From /tmp/agenix-host-keys.txt
};
```

### Step 3: Re-encrypt Secrets with Host Keys

```bash
cd /etc/nixos
RULES=/etc/nixos/secrets.nix /nix/store/.../agenix -r -i ~/.age/key.txt
```

Or use the helper script:
```bash
python3 skills/agenix-secrets/scripts/rekey_secrets.py
```

### Step 4: Update Secret Recipients

For each secret in `secrets.nix`, add the hosts that need access:

```nix
# Example: Shared secret on zephyr and forge
"api-key.age".publicKeys = [
  users.j_kro      # Your key (for management)
  hosts.zephyr     # Zephyr can auto-decrypt
  hosts.forge      # Forge can auto-decrypt
];
"secrets/api-key.age".publicKeys = [
  users.j_kro
  hosts.zephyr
  hosts.forge
];
```

### Step 5: Rebuild Each Host

```bash
# Zephyr
sudo nixos-rebuild switch --flake .#zephyr

# Forge
sudo nixos-rebuild switch --flake .#forge

# Nexus
sudo nixos-rebuild switch --flake .#nexus

# Sentry
sudo nixos-rebuild switch --flake .#sentry
```

## Manual Method (Step-by-Step)

### For Each Host:

1. **Get the host's SSH public key in age format:**

   ```bash
   # SSH to the host
   ssh zephyr

   # Convert SSH host key to age format
   sudo cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age
   ```

   Output example:
   ```
   age1l4vzephyrkey1234567890abcdefghijklmnopqrstuvwxyz
   ```

2. **Add to secrets.nix:**

   ```nix
   hosts = {
     zephyr = "age1l4vzephyrkey123...";
   };
   ```

3. **Repeat for all hosts** (forge, nexus, sentry)

4. **Re-encrypt all secrets:**

   ```bash
   cd /etc/nixos
   RULES=/etc/nixos/secrets.nix agenix -r -i ~/.age/key.txt
   ```

5. **Update each secret's publicKeys** to include the hosts

6. **Rebuild each host**

## Verifying Setup

After setup, verify with:

```bash
# Check configuration
python3 skills/agenix-secrets/scripts/validate.py

# List secrets and which hosts can access them
python3 skills/agenix-secrets/scripts/list_secrets.py --by-host

# Test decryption (should work without your private key)
sudo nixos-rebuild build --flake .#zephyr
```

## Current Host Assignment

Based on your infrastructure:

| Host | Purpose | Secrets Needed |
|------|---------|----------------|
| **zephyr** | AI/Gaming (RTX 3090) | All AI service keys |
| **forge** | Build server | Build/service credentials |
| **nexus** | Services | Service credentials |
| **sentry** | Monitoring | Monitoring credentials |

## Example: Multi-Host Secret

```nix
# Secret that multiple hosts need
"shared-service-key.age".publicKeys = [
  users.j_kro      # You (for management)
  hosts.zephyr     # Zephyr
  hosts.forge      # Forge
  hosts.nexus      # Nexus
  # NOT sentry (doesn't need this secret)
];
```

## Troubleshooting

### "ssh-to-age: command not found"

**Solution:** Install via nix-shell:
```bash
nix-shell -p ssh-to-age
```

Or add to your NixOS configuration:
```nix
environment.systemPackages = [ pkgs.ssh-to-age ];
```

### "attribute 'hosts.xxx' missing"

**Solution:** Add the host to the `hosts` section in secrets.nix:
```nix
hosts = {
  zephyr = "age1l4v...";
  # Add missing host here
};
```

### Secrets still require private key

**Solution:** Make sure you:
1. Re-encrypted secrets after adding host keys
2. Added the host to the secret's `publicKeys` list
3. Rebuilt the host

### Can't SSH to host

**Solution:** Check host is reachable:
```bash
ping zephyr
ssh zephyr "hostname"
```

## Security Considerations

✅ **Host keys are public**: SSH host keys are already public
✅ **No private keys on hosts**: Hosts only have their own SSH private key
✅ **Principle of least privilege**: Each host only gets secrets it needs
✅ **Rotatable**: Can rekey if a host is compromised

⚠️ **Warning**: If a host is compromised:
1. Rotate the compromised secret
2. Re-encrypt with new keys
3. Rebuild affected hosts

## Next Steps After Setup

1. **Remove your private key from hosts** (if present):
   ```bash
   # Make sure age.identityPaths only points to your key
   ```

2. **Test automated builds**:
   ```bash
   # Should work without your private key
   sudo nixos-rebuild build --flake .#zephyr
   ```

3. **Set up CI/CD**:
   - Hosts can now build without access to your private key
   - Secrets decrypt automatically during builds

4. **Document secret assignments**:
   - Keep track of which secrets go on which hosts
   - Update this document as your infrastructure changes

## Checklist

- [ ] Collect host keys from all 4 hosts
- [ ] Add hosts section to secrets.nix
- [ ] Re-encrypt all secrets with host keys
- [ ] Update each secret's publicKeys to include hosts
- [ ] Rebuild all hosts
- [ ] Verify automatic decryption works
- [ ] Test that private key is no longer needed
- [ ] Document which secrets are on which hosts

## Getting Help

If you encounter issues:

1. **Run validation**:
   ```bash
   python3 skills/agenix-secrets/scripts/validate.py --verbose
   ```

2. **Check secret distribution**:
   ```bash
   python3 skills/agenix-secrets/scripts/list_secrets.py --matrix
   ```

3. **Review logs**:
   ```bash
   journalctl -xeu nixos-rebuild
   ```

4. **Test specific secret**:
   ```bash
   python3 skills/agenix-secrets/scripts/test_secrets.py secret-name
   ```
