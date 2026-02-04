# NixOS Cluster - AI Agent Dashboard

**Status:** ✅ Healthy | **Backend:** Podman | **Builds:** Distributed (51 Cores)
**Last Audit:** 2026-02-04 (See `docs/SYSTEM_REALITY_CHECK.md`)

## ⚡ Quick Actions
| Context | Command | Description |
|---------|---------|-------------|
| **Deploy** | `just cluster-deploy` | Deploy to all nodes (GitOps: infra branch) |
| **Update** | `just cluster-update` | Update flake inputs and deploy |
| **Check** | `nix flake check` | Validate configuration syntax |
| **Audit** | `statix check .` | Run static analysis |

## 📍 Key Locations
| Component | File Path | Status |
|-----------|-----------|--------|
| **Cluster Config** | `flake.nix` | 4 Hosts |
| **Secrets** | `secrets/` | Agenix Encrypted |
| **OpenClaw** | `modules/openclaw-declarative-container.nix` | Podman (Rootless) |
| **Mining** | `modules/mining.nix` | Localhost-only API |
| **AI Storage** | `modules/openclaw-storage.nix` | AIStor (S3 Compatible) |
| **Local LLM** | `modules/lmstudio-docker.nix` | Podman Container |

## 🏗️ Architecture
*   **Container Engine:** Podman (Declarative, Rootless)
*   **Networking:** Tailscale Mesh (100.x.x.x)
*   **Security:** Services bind 127.0.0.1, exposed via Nginx only
*   **Build System:** Distributed builds enabled over `ssh-ng`

## 📚 Documentation Index
*   [System Reality Check & Audit Log](docs/SYSTEM_REALITY_CHECK.md) - **READ THIS FIRST**
*   [Deployment Instructions](docs/DEPLOYMENT_INSTRUCTIONS.md)
*   [Security Policy](docs/security-policy.md)
*   [Tailscale Setup](docs/TAILSCALE_SETUP.md)

## ⚠️ Recent Changes (2026-02-04)
1.  **Mining Security:** API ports now bound to localhost.
2.  **Podman Migration:** OpenClaw and LM Studio modules rewritten for Podman.
3.  **Distributed Builds:** Enabled for nexus, forge, sentry.

> **Note to Agents:** When modifying services, ensure they bind to `127.0.0.1` and use `virtualisation.oci-containers` (Podman) instead of Docker.
