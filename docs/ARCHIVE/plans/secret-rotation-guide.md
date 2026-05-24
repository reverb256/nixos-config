# Secret Rotation Guide

**Last Verified:** 2026-05-14 — ⚠️ 9 days old, approaching staleness threshold (7 days). Re-verify before relying.
**Purpose:** Document how to rotate each secret that was previously hardcoded in git plaintext in Nix K8s modules.

## Overview

Six secrets were migrated from hardcoded values in `kubernetes/modules/*.nix` to agenix-encrypted files. Each secret now has an entry in `modules/system/agenix-secrets-registry.nix` and a placeholder K8s Secret with empty `stringData`.

The deployment flow:
1. `agenix -e secrets/<name>.age` — encrypt the new value
2. `just deploy` — NixOS rebuild deploys the agenix config
3. `kubectl-apply-k8s-secrets` — systemd service reads `/run/agenix/<name>` and `kubectl apply`s it
4. Restart the pod — picks up the new secret from the K8s Secret

---

## Secret 1: Tailscale OAuth

| Field | Value |
|-------|-------|
| **File** | `kubernetes/modules/tailscale.nix` |
| **Agenix path** | `secrets/tailscale-oauth.age` |
| **Agenix key** | `tailscale-oauth` |
| **K8s Secret** | `tailscale-prod/operator-oauth` |
| **Fields** | `client_id`, `client_secret` |

### Rotation steps

```bash
# 1. Generate new Tailscale OAuth credentials
#    Visit https://login.tailscale.com/admin/settings/oauth
#    Create a new OAuth client with the appropriate scopes

# 2. Create a temp file with the new values
cat > /tmp/tailscale-oauth.txt << 'EOF'
client_id=<new-client-id>
client_secret=tskey-client-<new-key>
EOF

# 3. Encrypt with agenix (uses /keys/<your-age-key>.pub)
agenix -e secrets/tailscale-oauth.age < /tmp/tailscale-oauth.txt

# 4. Clean up temp file
shred -u /tmp/tailscale-oauth.txt

# 5. Deploy and apply
just deploy
kubectl-apply-k8s-secrets

# 6. Restart the tailscale-operator pod
kubectl rollout restart -n tailscale-prod deployment/operator
```

### How to generate
- Go to https://login.tailscale.com/admin/settings/oauth
- Create a new OAuth client with device write capability
- Copy the `client_id` and `client_secret`

---

## Secret 2: Mission Control OIDC

| Field | Value |
|-------|-------|
| **File** | `kubernetes/modules/mission-control.nix` |
| **Agenix path** | `secrets/mission-control-oidc.age` |
| **Agenix key** | `mission-control-oidc` |
| **K8s Secret** | `orchestration/mission-control-oidc` |
| **Fields** | `client-id`, `cookie-secret` |

### Rotation steps

```bash
# 1. Generate new values
CLIENT_ID=$(openssl rand -hex 12)
COOKIE_SECRET=$(openssl rand -hex 16)

# 2. Create a temp file
cat > /tmp/mission-control-oidc.txt << EOF
client-id=$CLIENT_ID
cookie-secret=$COOKIE_SECRET
EOF

# 3. Encrypt
agenix -e secrets/mission-control-oidc.age < /tmp/mission-control-oidc.txt

# 4. Clean up
shred -u /tmp/mission-control-oidc.txt

# 5. Deploy and apply
just deploy
kubectl-apply-k8s-secrets

# 6. Update the Casdoor app with new client-id/cookie-secret
#    Visit https://auth.lan/applications/mission-control
```

### How to generate
- `client-id`: 24 hex characters (`openssl rand -hex 12`)
- `cookie-secret`: 32 hex characters (`openssl rand -hex 16`)
- ⚠️ Must also update the corresponding Casdoor application config

---

## Secret 3: Open WebUI OAuth Client Secret

| Field | Value |
|-------|-------|
| **File** | `kubernetes/modules/ai-inference.nix` |
| **Agenix path** | `secrets/openwebui-oidc-client-secret.age` |
| **Agenix key** | `openwebui-oidc-client-secret` |
| **K8s Secret** | `ai-inference/open-webui-secrets` |
| **Field** | `oauth-client-secret` |
| **Env var** | `OAUTH_CLIENT_SECRET` (via `valueFrom.secretKeyRef`) |

### Rotation steps

```bash
# 1. Generate new client secret
NEW_SECRET=$(openssl rand -hex 20)

# 2. Encrypt with agenix
echo -n "$NEW_SECRET" | agenix -e secrets/openwebui-oidc-client-secret.age

# 3. Deploy and apply
just deploy
kubectl-apply-k8s-secrets

# 4. Update the Casdoor Open WebUI app
#    Visit https://auth.lan/applications/openwebui
#    Set the Client Secret to match the new value

# 5. Restart Open WebUI
kubectl rollout restart -n ai-inference deployment/open-webui
```

### How to generate
- 40 hex characters: `openssl rand -hex 20`
- ⚠️ Must match the Client Secret configured in Casdoor for the `openwebui` application

---

## Secret 4: Frostbite Gazette Postgres

| Field | Value |
|-------|-------|
| **File** | `kubernetes/modules/frostbite-gazette.nix` |
| **Agenix path** | `secrets/frostbite-postgres.age` |
| **Agenix key** | `frostbite-postgres` |
| **K8s Secret** | `ai-inference/frostbite-secrets` |
| **Field** | `postgres-password` |

### Rotation steps

```bash
# 1. Generate new password
NEW_PASS=$(openssl rand -base64 24)

# 2. Encrypt with agenix
echo -n "$NEW_PASS" | agenix -e secrets/frostbite-postgres.age

# 3. Deploy and apply
just deploy
kubectl-apply-k8s-secrets

# 4. Restart the postgres StatefulSet
kubectl rollout restart -n ai-inference statefulset/frostbite-postgres

# 5. Update any services that connect with the new password
```

### How to generate
- Base64-encoded 24 bytes: `openssl rand -base64 24`
- ⚠️ Rotating postgres passwords requires updating the database user password first (via `ALTER USER`) before updating the K8s Secret, or delete the postgres PVC and re-initialize

---

## Secret 5: Kagent Postgres

| Field | Value |
|-------|-------|
| **File** | `kubernetes/modules/kagent.nix` |
| **Agenix path** | `secrets/kagent-postgres.age` |
| **Agenix key** | `kagent-postgres` |
| **K8s Secret** | `kagent/kagent-postgresql` |
| **Field** | `POSTGRES_PASSWORD` |

### Rotation steps

```bash
# 1. Generate new password
NEW_PASS=$(openssl rand -base64 24)

# 2. Encrypt with agenix
echo -n "$NEW_PASS" | agenix -e secrets/kagent-postgres.age

# 3. Deploy and apply
just deploy
kubectl-apply-k8s-secrets

# 4. Restart postgres
kubectl rollout restart -n kagent statefulset/kagent-postgresql

# 5. Restart kagent controller
kubectl rollout restart -n kagent deployment/kagent-controller
```

### How to generate
- Base64-encoded 24 bytes: `openssl rand -base64 24`
- ⚠️ Same caveat as frostbite — postgres password rotation requires updating the DB user first

---

## Secret 6: Haven OIDC

| Field | Value |
|-------|-------|
| **File** | `kubernetes/modules/haven.nix` |
| **Agenix path** | `secrets/haven-oidc.age` |
| **Agenix key** | `haven-oidc` |
| **K8s Secret** | `haven/haven-oidc` |
| **Fields** | `client-id`, `cookie-secret` |

### Rotation steps

```bash
# 1. Generate new values
CLIENT_ID=$(openssl rand -hex 12)
COOKIE_SECRET=$(openssl rand -hex 16)

# 2. Create temp file
cat > /tmp/haven-oidc.txt << EOF
client-id=$CLIENT_ID
cookie-secret=$COOKIE_SECRET
EOF

# 3. Encrypt
agenix -e secrets/haven-oidc.age < /tmp/haven-oidc.txt

# 4. Clean up
shred -u /tmp/haven-oidc.txt

# 5. Deploy and apply
just deploy
kubectl-apply-k8s-secrets

# 6. Restart Haven
kubectl rollout restart -n haven deployment/haven
```

### How to generate
- `client-id`: 24 hex characters (`openssl rand -hex 12`)
- `cookie-secret`: 32 hex characters (`openssl rand -hex 16`)
- ⚠️ Haven does not support OIDC natively — these are used by the Caddy `forward_auth` proxy. Update Casdoor app if needed.

---

## Quick-Reference: All Secrets

| # | Secret Name | Agenix File | K8s Namespace | K8s Secret Name | Fields |
|---|-------------|-------------|---------------|-----------------|--------|
| 1 | `tailscale-oauth` | `secrets/tailscale-oauth.age` | `tailscale-prod` | `operator-oauth` | `client_id`, `client_secret` |
| 2 | `mission-control-oidc` | `secrets/mission-control-oidc.age` | `orchestration` | `mission-control-oidc` | `client-id`, `cookie-secret` |
| 3 | `openwebui-oidc-client-secret` | `secrets/openwebui-oidc-client-secret.age` | `ai-inference` | `open-webui-secrets` | `oauth-client-secret` |
| 4 | `frostbite-postgres` | `secrets/frostbite-postgres.age` | `ai-inference` | `frostbite-secrets` | `postgres-password` |
| 5 | `kagent-postgres` | `secrets/kagent-postgres.age` | `kagent` | `kagent-postgresql` | `POSTGRES_PASSWORD` |
| 6 | `haven-oidc` | `secrets/haven-oidc.age` | `haven` | `haven-oidc` | `client-id`, `cookie-secret` |

## Apply After Rotation

After encrypting new values, always run:

```bash
# 1. Deploy the config (makes agenix files available)
just deploy

# 2. Apply secrets to K8s
kubectl-apply-k8s-secrets

# 3. Restart affected pods
kubectl rollout restart -n <namespace> <deployment|statefulset>/<name>
```

## Pre-commit Checklist

Before committing any secret changes, verify:

- [ ] No plaintext secrets exist in any `.nix` file under `kubernetes/modules/`
- [ ] Each migrated secret has an entry in `modules/system/agenix-secrets-registry.nix`
- [ ] Each K8s Secret has a comment pointing to the agenix file path
- [ ] Each `.age` file exists in `secrets/` directory (or is noted as a TODO)
- [ ] The `kubectl-apply-k8s-secrets` service handles the new secret
