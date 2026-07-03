# Secret Rotation Schedule

**Purpose:** Ensure regular rotation of all secrets to minimize risk from potential compromise.

**Last Updated:** 2026-05-15  
**Next Scheduled Rotation:** 2026-08-15 (Quarterly)

---

## Secret Categories

### 1. Agenix Secrets (NixOS) - `/etc/nixos/secrets/`

| Secret | Type | Rotation Period | Last Rotated | Next Due | Owner |
|--------|------|-----------------|--------------|----------|-------|
| `huggingface-token.age` | API Key | Quarterly | - | 2026-08-15 | j_kro |
| `zai-api-key.age` | API Key | Quarterly | - | 2026-08-15 | j_kro |
| `nvidia-api-key.age` | API Key | Quarterly | - | 2026-08-15 | j_kro |
| `github-token.age` | Access Token | Monthly | - | 2026-06-15 | j_kro |
| `tailscale-auth-key.age` | Auth Key | Quarterly | - | 2026-08-15 | j_kro |
| `cluster-ca-key.age` | CA Key | Yearly | - | 2027-05-15 | j_kro |
| `ssh-host-key-*.age` | SSH Key | Yearly | - | 2027-05-15 | j_kro |

**Rotation Procedure:**
```bash
# 1. Generate new secret
# 2. Re-encrypt with agenix
age -R recipients.age -o secret.age new-secret-value

# 3. Commit to git
git add secrets/
git commit -m "security: rotate <secret-name>"

# 4. Deploy to all nodes
just deploy

# 5. Verify services still work
# 6. Update rotation log below
```

---

### 2. Kubernetes Secrets

| Secret | Namespace | Type | Rotation Period | Last Rotated | Next Due | Owner |
|--------|-----------|------|-----------------|--------------|----------|-------|
| `casdoor-postgres-secret` | auth | Database | Quarterly | - | 2026-08-15 | j_kro |
| `oauth2-proxy-secrets` | auth | OIDC Client | Quarterly | - | 2026-08-15 | j_kro |
| `ai-inference-gateway-secrets` | ai-inference | API Keys | Quarterly | - | 2026-08-15 | j_kro |
| `grafana-admin-secret` | monitoring | Admin Password | Quarterly | - | 2026-08-15 | j_kro |
| `github-token` | mcp | Access Token | Monthly | - | 2026-06-15 | j_kro |

**Rotation Procedure:**
```bash
# 1. Generate new secret value
kubectl create secret generic new-secret --from-literal=key=value --dry-run=client -o yaml | kubectl apply -f -

# 2. Update secret in NixOS config (if managed by Nix)
# 3. Deploy
just deploy

# 4. Restart dependent pods
kubectl rollout restart deployment/<deployment-name> -n <namespace>

# 5. Verify application works
# 6. Delete old secret (if applicable)
```

---

### 3. Casdoor OIDC Applications

| App Name | Client ID | Secret Type | Rotation Period | Last Rotated | Next Due |
|----------|-----------|-------------|-----------------|--------------|----------|
| `mcp-client` | mcp-client | Client Secret | Quarterly | - | 2026-08-15 |
| `app-grafana` | fa39ccce16fbc8ad4d23 | Client Secret | Quarterly | - | 2026-08-15 |
| `app-gitea` | app-gitea | Client Secret | Quarterly | - | 2026-08-15 |
| `app-openwebui` | openwebui | Client Secret | Quarterly | - | 2026-08-15 |

**Rotation Procedure:**
1. Login to Casdoor UI (auth.lan)
2. Navigate to Apps → Select app
3. Generate new client secret
4. Update Kubernetes secret or NixOS config
5. Restart dependent services

---

## Rotation Log

| Date | Secret | Type | Performed By | Notes |
|------|--------|------|--------------|-------|
| 2026-05-15 | All secrets | Policy created | j_kro | Initial rotation schedule created |

---

## Emergency Rotation

In case of suspected compromise:

1. **Immediate** (within 1 hour):
   - Rotate affected secret
   - Check audit logs for unauthorized access
   - Notify affected parties

2. **Short-term** (within 24 hours):
   - Review all related access logs
   - Update firewall rules if needed
   - Document incident

3. **Long-term** (within 1 week):
   - Full security audit
   - Update security procedures
   - Review and improve monitoring

---

## Compliance Notes

- **PCI-DSS:** Requires quarterly rotation for production secrets
- **SOC2:** Requires documented rotation policy and audit trail
- **Best Practice:** More frequent rotation for high-value targets (tokens, keys)

## Monitoring

Secret expiration is monitored via:
- Prometheus alerts for certificate expiry
- Grafana dashboard: "Secret Rotation Status"
- Weekly automated reminder via n8n workflow

---

> Snapshot from August 2026 cleanup; verify current state via `/etc/nixos/SOPS-NIX.md`.

## See Also — SOPS-NIX (canonical on this host)

For canonical sops-nix status, key file location (`/etc/nixos/.age/key.txt`),
registry module structure (`/etc/nixos/modules/system/sops-secrets-registry.nix`),
current recipients (`/etc/nixos/.sops.yaml`), and recovery workflow, see
`/etc/nixos/SOPS-NIX.md`.

Quick facts that hold on this NixOS host (zephyr):
- Registry `services.sops-secrets-registry.enable` defaults to `false` on
  all 5 hosts (forge, nexus, sentry, zephyr, krash3); the registry's
  `mkIf` block is currently inert and `config.sops.secrets` evaluates to
  `[]` until a host opts in.
- 0/135 existing encrypted files decrypt locally today (legacy
  recipients pre-date the single-pubkey `.sops.yaml` policy). The
  `/etc/nixos/.sops.yaml` already names the local pubkey, so new
  encryptions will decrypt on zephyr.
- After any `age-keygen` / `sops updatekeys` operation, sync the user
  key to the canonical location:
  `sudo cp ~/.age/key.txt /etc/nixos/.age/key.txt && sudo chown root:root /etc/nixos/.age/key.txt && sudo chmod 600 /etc/nixos/.age/key.txt`.
