# Environment

Environment variables, external dependencies, and setup notes.

**What belongs here:** Required env vars, external API keys/services, dependency quirks.
**What does NOT belong here:** Service ports/commands (use `.factory/services.yaml`).

---

## NixOS Flake

- System: x86_64-linux
- Flake inputs: nixpkgs (unstable), home-manager, colmena, agenix, niri, nixpkgs-xr, and others
- All hosts built from same flake with different configuration modules
- Deployment via Colmena (NFS-based, no git push needed)

## Secrets

- **Agenix** encrypts secrets in `/etc/nixos/secrets/*.age`
- Decrypted at runtime to `/run/agenix/*`
- ZAI API key: `/run/agenix/zai-api-key`
- All tools reference these paths or env vars derived from them

## K8s Access

- kubectl configured via /etc/kubernetes/admin.conf
- Accessible from Zephyr (control plane node)
- All 4 nodes: zephyr, nexus, forge, sentry

## Commands

```bash
just check     # Validate flake (fast)
just build     # Build for local host
just switch    # Apply to local host
just deploy    # Deploy to all hosts
just status    # Git + cluster status
```
