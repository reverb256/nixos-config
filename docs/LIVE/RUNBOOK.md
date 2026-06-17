---
last-verified: 2026-06-12
verified-by: Sisyphus
verification-method: just docs-audit
expires: 2026-06-19
---
# Runbook

## Common Operations

**Cluster Status**
```bash
just status
just health
just docs-audit
```

**Deploy Changes**
```bash
just switch          # Local (Zephyr)
just deploy nexus    # Specific host
just deploy all      # Full cluster
```

**Documentation**
```bash
just docs-audit      # Verify all LIVE docs
just docs-freshen    # Refresh stale sections
```

**Critical Rules**
- Never schedule non-infra workloads on Zephyr (OOM risk)
- Update `docs/LIVE/INFRASTRUCTURE-AUDIT.md` on any infrastructure change
- All PRs touching modules/ or hosts/ must pass `just docs-audit`
- If cluster reality diverges from docs, update the docs (Pocock Rule)


## Security

### Before committing
```bash
gitleaks protect --staged          # Check for credentials in staged changes
```

### If credentials are accidentally committed
1. Immediately rotate the exposed credential
2. Remove file from git: `git rm --cached <file>`
3. Update `.gitignore` to prevent recurrence
4. Run `git filter-repo --path <file> --invert-paths` to purge history
5. Force push to all remotes
6. Notify collaborators to re-clone

### Verify no secrets in working tree
```bash
gitleaks detect --source . --no-git  # Scan entire working tree
```


### YubiKey operations

**List PIV slots:**
```bash
ykman piv info --device SERIAL
ykman piv certificates --device SERIAL
```

**Use YubiKey for age decryption:**
```bash
nix shell nixpkgs#age nixpkgs#age-plugin-yubikey -c age -d file.age
```

**Sign SSH cert with YubiKey CA (via file backup):**
```bash
/etc/nixos/scripts/ssh-sign-cert.sh [key] [principal] [validity]
```

**Create a SealedSecret:**
```bash
kubectl create secret generic name --namespace ns \
  --from-literal=key=value --dry-run=client -o yaml \
  | kubeseal --cert /path/to/cert.pem --format yaml \
  > sealed.yaml
```

### Key paths
- Age key: `/etc/nixos/.age/key.txt` (600, gitignored)
- SSH key: `~/.ssh/id_ed25519` (outside repo)
- Encrypted secrets: `secrets/*.age` and `secrets/*.yaml`


## Security

### Before committing
```bash
gitleaks protect --staged          # Check for credentials in staged changes
```

### If credentials are accidentally committed
1. Immediately rotate the exposed credential
2. Remove file from git: `git rm --cached <file>`
3. Update `.gitignore` to prevent recurrence
4. Run `git filter-repo --path <file> --invert-paths` to purge history
5. Force push to all remotes
6. Notify collaborators to re-clone

### Verify no secrets in working tree
```bash
gitleaks detect --source . --no-git  # Scan entire working tree
```


### YubiKey operations

**List PIV slots:**
```bash
ykman piv info --device SERIAL
ykman piv certificates --device SERIAL
```

**Use YubiKey for age decryption:**
```bash
nix shell nixpkgs#age nixpkgs#age-plugin-yubikey -c age -d file.age
```

**Sign SSH cert with YubiKey CA (via file backup):**
```bash
/etc/nixos/scripts/ssh-sign-cert.sh [key] [principal] [validity]
```

**Create a SealedSecret:**
```bash
kubectl create secret generic name --namespace ns \
  --from-literal=key=value --dry-run=client -o yaml \
  | kubeseal --cert /path/to/cert.pem --format yaml \
  > sealed.yaml
```

### Key paths
- Age key: `/etc/nixos/.age/key.txt` (600, gitignored)
- SSH key: `~/.ssh/id_ed25519` (outside repo)
- Encrypted secrets: `secrets/*.age` and `secrets/*.yaml`

## Emergency Procedures

**NFS Issues**
- Check `just check-nfs`
- Restart NFS services on Zephyr if remotes cannot read config

**K8s Issues**
- `kubectl get nodes`
- Check Alloy, Prometheus, Loki on Sentry

See `docs/ARCHIVE/` for historical context only. All current procedures live in this file or INFRASTRUCTURE-AUDIT.md.
