# Security Modules

Security modules handle authentication, certificate trust, encrypted secrets,
and cluster-wide security hardening across the NixOS cluster.

## Module Inventory

### Top-Level Security (`modules/security/`)

| Module | Purpose | Used By |
|--------|---------|---------|
| `agent-firewall.nix` | nftables cgroup-based network restrictions for AI agents | Zephyr |
| `caddy-ca.nix` | Trust Caddy internal CA for cluster ingress TLS | Zephyr, Nexus |
| `pam-vaultwarden.nix` | PAM auth using Vaultwarden credentials | Reserved (not active) |
| `aistor-secrets.nix` | Declarative AIStor/MinIO credential management | Nexus |

### System Security (`modules/system/security.nix`)

Comprehensive hardening module installing security tools (Fail2Ban, USBGuard,
Firejail, Lynis) and providing baseline system hardening. Imported via
`modules/default.nix` on hosts that need it (primarily Forge).

### Cluster Audit (`security.clusterAudit`)

Host-level security audit configuration enabling:
- **Firewall enforcement** (`enableFirewall`)
- **Tailscale SSH** (`enableTailscaleSSH`) — remote access via Tailscale identity
- **Service hardening** (`bindServicesToLocalhost`)

Currently enabled on Zephyr (control plane + workstation).

### Kubernetes Security (`security.kubernetes`)

Runtime monitoring and security policies for Kubernetes:
- K8s admission policies (block `:latest` tags, enforce resource limits)
- Network policies for pod isolation
- RBAC configuration
- Security context defaults

## Certificate Infrastructure

### Caddy Internal CA

The cluster uses Caddy's internal CA for TLS on internal services:
- `caddy-ca.nix` adds the Caddy root CA to the system trust store
- Certificate at `certs/caddy-root-ca.crt`
- Used for HTTPS ingress to cluster services (search.lan, ai.lan, etc.)
- Zen Browser and system tools trust these certificates

### Cluster CA (`services.cluster-ca`)

Internal CA using CFSSL for cluster service certificates:
- Runs on control plane nodes (Zephyr, Nexus, Sentry)
- Issues certificates for K8s components, etcd, and internal services
- CA API available on port 8888

## Encrypted Secrets (Agenix)

### Architecture

```
secrets/*.age           ← Encrypted secret files (committed to git)
secrets.nix             ← Maps secrets to host public keys (who can decrypt)
agenix-secrets-registry ← Declares which secrets deploy to which hosts
hosts/*/configuration.nix ← Enables specific secret categories per host
```

### Secret Lifecycle

1. **Create**: `agenix -e secrets/my-secret.age` (encrypts with host public keys)
2. **Register**: Add to `modules/system/agenix-secrets-registry.nix`
3. **Deploy**: Enable in host config: `services.agenix-secrets-registry.{category} = true`
4. **Access**: Decrypted secrets appear at `/run/agenix/<secret-name>`

### Secret Categories

| Category | Secrets | Hosts |
|----------|---------|-------|
| `aiServices` | ZAI API key, HF token, NVIDIA API key, Pollinations key | Zephyr, Nexus |
| `monitoring` | Prometheus, Grafana, AlertManager secrets | Unused currently |
| `storage` | Garage S3 API key | Zephyr |
| `mining` | XMRig API tokens, pool credentials | Zephyr, Forge, Sentry |
| `cloud` | Cloudflare tunnel token, Context7 API key | Zephyr |
| `kubernetes` | k3s cluster token | All K8s nodes |
| `selfHosting` | Vaultwarden, Spacebot tokens | Per-service hosts |

### Adding a New Secret

1. Create encrypted file:
   ```bash
   cd /etc/nixos
   agenix -e secrets/my-new-secret.age
   ```

2. Add public key mapping in `secrets.nix`:
   ```nix
   "secrets/my-new-secret.age".publicKeys = [ zephyr nexus ];
   ```

3. Declare in registry (`modules/system/agenix-secrets-registry.nix`):
   ```nix
   my-new-secret = {
     file = "${inputs.self}/secrets/my-new-secret.age";
     mode = "400";
     owner = "root";
     group = "root";
   };
   ```

4. Reference in host config:
   ```nix
   config.age.secrets.my-new-secret.path  # → "/run/agenix/my-new-secret"
   ```

## PAM Integration

`pam-vaultwarden.nix` provides system authentication via Vaultwarden
credentials. Currently reserved (not active on any host). When enabled,
it supports:
- Login, SSH, su, sudo authentication
- Fallback to system passwords
- Vaultwarden URL configuration

## Supply Chain Security

The cluster enforces supply chain protections:
- **Package cooldowns**: 7-day age requirement for npm/bun/uv packages
  (see `services.supply-chain-cooldowns`)
- **Container image pinning**: No `:latest` tags (enforced by K8s admission policy)
- **CI/CD pinning**: GitHub Actions pinned to commit SHAs
- **Flake updates**: Auto-update validates input age before updating nixpkgs
