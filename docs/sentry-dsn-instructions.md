# Sentry DSN Secret - Creation Instructions

## Status
**Missing**: The `sentry-dsn.age` encrypted file does not exist.

## Current Configuration
- **Declared in**: `secrets.nix` (lines 115-122)
- **Declared in**: `modules/system/agenix-secrets-registry.nix` (lines 164-169)
- **Monitoring secrets**: Currently DISABLED on zephyr (`monitoring = false`)
- **Expected location**: `/etc/nixos/secrets/sentry-dsn.age`

## How to Create

### 1. Get Your Sentry DSN
- Log into your Sentry account (https://sentry.io)
- Navigate to: Settings → Projects → [Your Project] → Client Keys (DSN)
- Copy the DSN URL (looks like: `https://[key]@o[org].ingest.sentry.io/[project]`)

### 2. Encrypt the Secret
```bash
cd /etc/nixos
agenix -e secrets/sentry-dsn.age
```
Paste your Sentry DSN when prompted, then save the file.

### 3. Verify the File
```bash
ls -la secrets/sentry-dsn.age
```

### 4. Re-enable Monitoring Secrets
Edit `/etc/nixos/hosts/zephyr/configuration.nix`:
```nix
services.agenix-secrets-registry = {
  enable = true;
  aiServices = true;
  monitoring = true;  # Change back to true
  # ... rest of config
};
```

### 5. Rebuild
```bash
sudo nixos-rebuild switch --flake .#zephyr
```

## What This Secret Is Used For
- **Service**: AI Inference Gateway (modules/services/ai-inference/gateway.nix)
- **Purpose**: Error tracking and monitoring for AI inference services
- **Runtime location**: `/run/agenix/sentry-dsn`

## Why It Was Disabled
The encrypted file was missing, causing agenix activation to fail with:
```
[agenix] WARNING: encrypted file .../secrets/sentry-dsn.age does not exist!
```

This was a critical blocker that prevented all system rebuilds.

## Notes
- The DSN is sensitive - don't commit the unencrypted value
- Each Sentry project has a unique DSN
- You can rotate the DSN from the Sentry dashboard if needed
- Age encryption uses your public key from `/etc/nixos/.age/key.txt`

## Created
2026-03-17 - During x86-64-v3 migration debugging
