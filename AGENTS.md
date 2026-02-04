# NixOS Cluster - AI Agent Dashboard

**Status:** ✅ Healthy | **Backend:** Podman | **Builds:** Distributed (51 Cores)
**Last Audit:** 2026-02-04 (See `docs/SYSTEM_REALITY_CHECK.md`)
**Agenix Key:** `age1pn55e68h5twm8ksrm29pzf4w5t8wdznmy0sqg5gvk094punpctq06q8zn` (Generated Feb 4, 2026)

## ⚡ Quick Actions
| Context | Command | Description |
|---------|---------|-------------|
| **Deploy** | `just prep && just deploy` | Copy age keys + deploy to all nodes |
| **Push** | `just push` | Push changes + deploy to current host |
| **Update** | `just update` | Update flake + deploy all |
| **Check** | `nix flake check` | Validate configuration syntax |

## 📍 Key Locations
| Component | File Path | Status |
|-----------|-----------|--------|
| **Cluster Config** | `flake.nix` | 4 Hosts |
| **Secrets** | `secrets/` | Agenix Encrypted |
| **OpenClaw** | `modules/openclaw-declarative-container.nix` | Podman (Rootless) |
| **Mining** | `modules/mining.nix` | Localhost-only API |
| Mining Troubleshooting | `docs/MINING_TROUBLESHOOTING.md` | Mining fixes and debugging guide |
| **AI Storage** | `modules/openclaw-storage.nix` | AIStor (S3 Compatible) |
| **Local LLM** | `modules/lmstudio-docker.nix` | Podman Container |

## 🏗️ Architecture
*   **Container Engine:** Podman (Declarative, Rootless)
*   **Networking:** Tailscale Mesh (100.x.x.x)
*   **Security:** Services bind 127.0.0.1, exposed via Nginx only
*   **Build System:** Distributed builds enabled over `ssh-ng`
*   **Secret Management:** Agenix with age key at `/root/.config/sops/age/keys.txt`

## 📚 Documentation Index
*   [System Reality Check & Audit Log](docs/SYSTEM_REALITY_CHECK.md) - **READ THIS FIRST**
*   [Deployment Instructions](docs/DEPLOYMENT_INSTRUCTIONS.md)
*   [Security Policy](docs/security-policy.md)
*   [Tailscale Setup](docs/TAILSCALE_SETUP.md)

## ⚠️ Recent Changes (2026-02-04)
1.  **Mining Security:** API ports now bound to localhost.
2.  **Podman Migration:** OpenClaw and LM Studio modules rewritten for Podman.
3.  **Distributed Builds:** Enabled for nexus, forge, sentry.
4.  **Agenix Secret Management:** 
    *   New age key generated and deployed
    *   All secrets extracted from `/run/agenix` and re-encrypted
    *   Key location: `/root/.config/sops/age/keys.txt`
5.  **NVIDIA Power Limit:** lolminer-nvidia set to 250W on zephyr

> **Note to Agents:** When modifying services, ensure they bind to `127.0.0.1` and use `virtualisation.oci-containers` (Podman) instead of Docker.

## 🔐 Agenix Secret Management

### Generating New Age Keys

**Generating a new age key:**
```bash
nix shell nixpkgs#age -c age-keygen -o /root/.config/sops/age/keys.txt
```

**Getting age public key from SSH ed25519:**
```bash
ssh-keygen -y -f ~/.ssh/id_ed25519 | ssh-to-age
```

### Encrypting/Decrypting Files

**Encrypting a file with age:**
```bash
age -r age1pn55e68h5twm8ksrm29pzf4w5t8twdznmy0sqg5gvk094punpctq06q8zn -o /path/to/output /path/to/input
```

**Decrypting:**
```bash
AGE_KEY=/root/.config/sops/age/keys.txt age -d -i /root/.config/sops/age/keys.txt -o - /path/to/file.age
```

### SSH Key to Age Public Key

```bash
ssh-keygen -y -f ~/.ssh/id_ed25519 | ssh-to-age
```

### Key History

- **2026-02-04:** New age key `age1pn55e68h5twm8ksrm29pzf4w5t8wdznmy0sqg5gvk094punpctq06q8zn` generated after old keys were lost
- Secrets were extracted from `/run/agenix` on zephyr (still in memory from running services)
- All secrets re-encrypted with the new key
