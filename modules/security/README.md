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

## Encrypted Secrets (sops-nix)

The cluster uses [sops-nix](https://github.com/Mic92/sops-nix) for secret management.
Secrets are encrypted with age/YubiKey via SOPS and decrypted at boot.

### Architecture

```
secrets/*.yaml          ← Encrypted secret files by category (ai/, k8s/, cloud/, etc.)
sops-secrets-registry   ← Declares which secrets deploy to which hosts/files
hosts/*/configuration.nix ← Enables specific secret categories per host
```

### Secret Lifecycle

1. **Create**: Add encrypted `.yaml` file to `secrets/<category>/` directory
2. **Register**: Add to `modules/system/sops-secrets-registry.nix`
3. **Deploy**: Enable in host config: `services.sops-secrets-registry.{category} = true`
4. **Access**: Decrypted secrets appear at `/run/secrets/<secret-name>`

### Secret Categories

| Category | Hosts |
|----------|-------|
| `ai` | Zephyr, Nexus |
| `k8s` | All K8s nodes |
| `cloud` | Zephyr |
| `monitoring` | Sentry |
| `mining` | Zephyr, Forge, Sentry |
| `infra` | All nodes |
| `automation` | Nexus |
| `storage` | Zephyr |
| `ci` | Nexus |

### Adding a New Secret

1. Create encrypted YAML file in `secrets/<category>/`:
   ```bash
   cd /etc/nixos
   # Edit with your $EDITOR, sops encrypts automatically
   sops secrets/ai/my-new-key.yaml
   ```

2. Declare in registry (`modules/system/sops-secrets-registry.nix`):
   ```nix
   my-new-key = {
     sopsFile = "\${inputs.self}/secrets/ai/my-new-key.yaml";
     mode = "0400";
     owner = "root";
     group = "root";
   };
   ```

3. Reference in host config:
   ```nix
   myNewKeyFile = "/run/secrets/my-new-key";
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
