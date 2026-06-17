---
last-verified: 2026-06-12
verified-by: Sisyphus
verification-method: just docs-audit + cluster inspection
expires: 2026-06-19
---
# Infrastructure Audit — 2026-06-12

## Cluster Overview

4-node NixOS + K3s cluster.

| Host | Role | RAM | GPUs | Primary Workloads |
|------|------|-----|------|--------------------|
| Zephyr (10.1.1.110) | Control plane, NFS server, workstation | 31GB | 2× NVIDIA | Gaming, control plane, some inference |
| **Nexus (10.1.1.120)** | **Primary server (DEFAULT for workloads)** | **46GB** | 1× NVIDIA | AI Gateway, Qdrant, Knowledge Fabric, SearXNG, monitoring |
| Forge (10.1.1.130) | GPU compute | 15GB | 2× NVIDIA + 2× AMD | Mining, GPU tasks |
| Sentry (10.1.1.140) | Monitoring + inference | 31GB | 1× AMD RX 5600 XT | Observability stack, Vulkan inference |

**CNI:** Flannel (VXLAN, UDP 8472). **K3s:** v1.34.5+k3s1.

**Critical Rule:** Schedule ALL non-infra workloads to Nexus (46GB). Zephyr is OOM-prone.

## Sovereign Service Mesh (Central Bus)

**Status:** Operational on Nexus.

**AI Gateway** at 10.15.67.242:8080 is the single entry point for all AI traffic.

**Components:**
- AI Gateway (central bus with RRF middleware)
- Qdrant (vector DB)
- Knowledge Fabric API (currently stub)
- SearXNG (search)
- Valkey (cache)

All `.lan` domains route through Caddy on Zephyr/Nexus with central-auth (oauth2-proxy + Casdoor).

**Grafana:** K8s only (monitoring namespace on Sentry, NodePort 32102). NixOS grafana module is dead code.

## MCP Infrastructure

Multiple MCP servers (kubernetes, nixos-cluster, searxng, casdoor, git, etc.) available via stdio and SSE.

**Hermes, OpenCode, OmP, Pi** all configured to use local MCP servers.

## Documentation Rules (Enforced)

- All claims in `docs/LIVE/` must be verifiable.
- No document >14 days old without fresh `last-verified` stamp.
- Contradictions must be resolved immediately.
- Pocock Rule: If cluster reality diverges from a plan, update the plan.


## Security Posture

**Audit Date:** 2026-06-17  
**Status:** Remediated (structural fixes applied, keys pending rotation)

### Credential Management
- Secrets encrypted with sops-nix/agenix (age key at `/etc/nixos/.age/key.txt`)
- SSH key lives at `~/.ssh/id_ed25519` -- not inside the repo
- Pre-commit `gitleaks` hook blocks credential commits
- `.gitignore` hardened against plaintext secret files

### Exposed Credentials (Found in Audit, Pending Rotation)
- `env-vars` -- live API keys (Anthropic, ZAI, Gemini, Context7) -- removed from tracking
- `secrets/context7/api-key.age` -- plaintext Context7 key -- removed from tracking
- `secrets/casdoor/mcp-gateway-credentials.env` -- plaintext Casdoor SSO creds -- removed

### Firewall
- NFS ports restricted to eth0 (cluster subnet)
- Tailscale trusted interface
- SSH hardened: no passwords, no root, fail2ban, key-only
- Kernel hardening: rp_filter, syncookies, source routing disabled


## YubiKey PIV Layout

Two YubiKeys, both provisioned identically:

| Slot | Purpose | YubiKey Nano (in zephyr) | YubiKey NFC (daily carry) |
|------|---------|--------------------------|---------------------------|
| **9a** | age-plugin-yubikey (encryption) | `nano` -- no PIN, cached touch | `nfc` -- PIN once, cached touch |
| **9c** | SSH CA (certificate signing) | ECC P-256 -- no PIN, touch always | ECC P-256 -- PIN once, touch always |
| **mgmt** | PIV admin | Changed + PIN-protected | Changed + PIN-protected |

**Backups (age-encrypted in repo):**
- `secrets/infra/yubikey-nano-mgmt-key.age` / `yubikey-nfc-mgmt-key.age`
- `secrets/infra/yubikey-ca-key-backup.age` (encrypted to both YubiKeys + cluster key)
- `secrets/infra/sealed-secrets-controller-key.age` (same 3 recipients)

## Sealed Secrets

Sealed Secrets controller v0.37.0 deployed to `kube-system`. Controller key backed up with 3 age recipients (Nano, NFC, cluster key).

**K8s secrets workflow:**
```bash
kubeseal --cert cert.pem --format yaml < secret.yaml > sealed.yaml
kubectl apply -f sealed.yaml
# No NixOS rebuild needed
```

Current SealedSecrets:
- `kubernetes-manifests/auth/casdoor-mcp-sealed.yaml` (MCP gateway credentials)

## Dual SSH CA

Two CAs trusted on all cluster hosts:
1. **ed25519** at `/etc/ssh/ca_key` (file-based, sops-nix backed, legacy)
2. **ECC P-256** in YubiKey PIV slot 9c (hardware-backed, requires touch)

Sign with the file key:
```bash
/etc/nixos/scripts/ssh-sign-cert.sh
```
Decrypt the YubiKey CA backup (if needed):
```bash
age -d secrets/infra/yubikey-ca-key-backup.age > /tmp/ca-key.pem
```
### Next Steps
1. Rotate all exposed credentials
2. Run `git filter-repo` to purge secrets from git history
3. Force push to all remotes (origin, central, gitea)

## Security Posture

**Audit Date:** 2026-06-17  
**Status:** Remediated (structural fixes applied, keys pending rotation)

### Credential Management
- Secrets encrypted with sops-nix/agenix (age key at `/etc/nixos/.age/key.txt`)
- SSH key lives at `~/.ssh/id_ed25519` -- not inside the repo
- Pre-commit `gitleaks` hook blocks credential commits
- `.gitignore` hardened against plaintext secret files

### Exposed Credentials (Found in Audit, Pending Rotation)
- `env-vars` -- live API keys (Anthropic, ZAI, Gemini, Context7) -- removed from tracking
- `secrets/context7/api-key.age` -- plaintext Context7 key -- removed from tracking
- `secrets/casdoor/mcp-gateway-credentials.env` -- plaintext Casdoor SSO creds -- removed

### Firewall
- NFS ports restricted to eth0 (cluster subnet)
- Tailscale trusted interface
- SSH hardened: no passwords, no root, fail2ban, key-only
- Kernel hardening: rp_filter, syncookies, source routing disabled


## YubiKey PIV Layout

Two YubiKeys, both provisioned identically:

| Slot | Purpose | YubiKey Nano (in zephyr) | YubiKey NFC (daily carry) |
|------|---------|--------------------------|---------------------------|
| **9a** | age-plugin-yubikey (encryption) | `nano` -- no PIN, cached touch | `nfc` -- PIN once, cached touch |
| **9c** | SSH CA (certificate signing) | ECC P-256 -- no PIN, touch always | ECC P-256 -- PIN once, touch always |
| **mgmt** | PIV admin | Changed + PIN-protected | Changed + PIN-protected |

**Backups (age-encrypted in repo):**
- `secrets/infra/yubikey-nano-mgmt-key.age` / `yubikey-nfc-mgmt-key.age`
- `secrets/infra/yubikey-ca-key-backup.age` (encrypted to both YubiKeys + cluster key)
- `secrets/infra/sealed-secrets-controller-key.age` (same 3 recipients)

## Sealed Secrets

Sealed Secrets controller v0.37.0 deployed to `kube-system`. Controller key backed up with 3 age recipients (Nano, NFC, cluster key).

**K8s secrets workflow:**
```bash
kubeseal --cert cert.pem --format yaml < secret.yaml > sealed.yaml
kubectl apply -f sealed.yaml
# No NixOS rebuild needed
```

Current SealedSecrets:
- `kubernetes-manifests/auth/casdoor-mcp-sealed.yaml` (MCP gateway credentials)

## Dual SSH CA

Two CAs trusted on all cluster hosts:
1. **ed25519** at `/etc/ssh/ca_key` (file-based, sops-nix backed, legacy)
2. **ECC P-256** in YubiKey PIV slot 9c (hardware-backed, requires touch)

Sign with the file key:
```bash
/etc/nixos/scripts/ssh-sign-cert.sh
```
Decrypt the YubiKey CA backup (if needed):
```bash
age -d secrets/infra/yubikey-ca-key-backup.age > /tmp/ca-key.pem
```
### Next Steps
1. Rotate all exposed credentials
2. Run `git filter-repo` to purge secrets from git history
3. Force push to all remotes (origin, central, gitea)
## Verification

Run `just docs-audit` (which runs `docs/meta/VERIFICATION-SUITE/run.sh`).

This file is the **single source of truth** for cluster state. All other documentation must align with it.
