# Secret Registry and AI Inference Documentation

## Agenix Secrets Registry (`modules/system/agenix-secrets-registry.nix`)

### Overview

The agenix-secrets-registry is the single source of truth for encrypted secrets
across the cluster. It maps static secret definitions (encrypted `.age` files)
to runtime paths (`/run/agenix/<name>`) and controls which secrets are deployed
to which hosts.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Secrets Lifecycle                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. CREATE                                               │
│     agenix -e secrets/my-secret.age                     │
│     (encrypts with host public keys from secrets.nix)   │
│                                                          │
│  2. REGISTER                                             │
│     Add declaration to agenix-secrets-registry.nix:     │
│     age.secrets.my-secret = {                            │
│       file = "${inputs.self}/secrets/my-secret.age";    │
│       mode = "400"; owner = "root"; group = "root";     │
│     };                                                   │
│                                                          │
│  3. DEPLOY                                               │
│     Enable in host config:                               │
│     services.agenix-secrets-registry.{category} = true; │
│     (Colmena transfers + agenix decrypts at activation)  │
│                                                          │
│  4. ACCESS                                               │
│     Decrypted at: /run/agenix/my-secret                  │
│     Reference: config.age.secrets.my-secret.path        │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Static Secret Mapping vs Runtime Paths

The registry has two layers:

1. **Static mapping** (`secrets.nix`): Maps each `.age` file to the set of
   host public keys that can decrypt it. This is the access control layer.

2. **Runtime declarations** (`agenix-secrets-registry.nix`): Declares
   `age.secrets.<name>` with file path, permissions (mode/owner/group),
   and categorization (aiServices, mining, kubernetes, etc.).

3. **Host enablement**: Each host enables only the secret categories it needs
   via `services.agenix-secrets-registry.* = true`. This prevents unnecessary
   secret deployment.

### Secret Categories

| Category | Description | Secrets Included | Hosts |
|----------|-------------|-----------------|-------|
| `aiServices` | AI provider API keys | ZAI, NVIDIA, Pollinations, HF tokens | Zephyr, Nexus |
| `monitoring` | Monitoring stack | Grafana, Prometheus, AlertManager | Currently unused |
| `storage` | Storage services | Garage S3 secret key | Zephyr |
| `mining` | Mining services | XMRig API tokens, pool credentials | Zephyr, Forge, Sentry |
| `cloud` | Cloud services | Cloudflare tunnel, Context7 API key | Zephyr |
| `kubernetes` | K8s cluster | k3s cluster join token | All K8s nodes |
| `selfHosting` | Self-hosted apps | Vaultwarden, Spacebot tokens | Per-service hosts |

### Adding a New Secret

1. **Create the encrypted file**:
   ```bash
   cd /etc/nixos
   # Edit the secret (will create if not exists)
   agenix -e secrets/my-new-secret.age
   ```

2. **Add public key mapping** in `secrets.nix`:
   ```nix
   "secrets/my-new-secret.age".publicKeys = [
     users.j_kro
     hosts.zephyr
     hosts.nexus
   ];
   ```

3. **Declare in registry** (`modules/system/agenix-secrets-registry.nix`):
   ```nix
   # Add to the appropriate category block:
   my-new-secret = {
     file = "${inputs.self}/secrets/my-new-secret.age";
     mode = "400";
     owner = "root";
     group = "root";
   };
   ```

4. **Enable on host** (in host's services module):
   ```nix
   services.agenix-secrets-registry = {
     enable = true;
     aiServices = true;  # or whichever category
   };
   ```

5. **Reference in config**:
   ```nix
   someService.tokenFile = config.age.secrets.my-new-secret.path;
   ```

### Overriding Secret Permissions

Host-specific overrides are done in the host's config:
```nix
age.secrets.my-secret = lib.mkForce {
  mode = "440";
  owner = "j_kro";
  group = "users";
};
```

### Secret Files Inventory

All encrypted secrets are stored in `/etc/nixos/secrets/*.age` (32 files).

## AI Inference Service (`modules/services/ai-inference/`)

### Overview

The AI Inference Service provides a production-ready gateway for LLM API access
across the cluster. It offers OpenAI-compatible and Anthropic-compatible API
endpoints with intelligent routing, RAG, caching, and monitoring.

### Submodule Architecture

```
modules/services/ai-inference/
├── default.nix          ← Main module entry point (options + config)
├── gateway.nix          ← Gateway systemd service configuration
├── router.nix           ← Intelligent model routing logic
├── auth.nix             ← Authentication (none/tailscale/api-key modes)
├── qdrant.nix           ← Qdrant vector database for RAG
├── redis-cache.nix      ← Redis for rate limiting and caching
├── monitor.nix          ← Prometheus metrics endpoint
├── health-monitor.nix   ← Backend health monitoring
├── ai_inference_gateway/ ← Python gateway application source
│   ├── middleware/       ← Request processing pipeline
│   ├── rag/              ← RAG engine implementation
│   ├── routing/          ← Model routing and fallback
│   └── mcp_servers/      ← MCP server implementations
└── README.md            ← Detailed feature documentation
```

### Request Flow

```
Client Request
    │
    ▼
┌──────────────────────────────────┐
│  Gateway (port 8080)             │
│  1. Auth check                   │
│  2. Security filter (PII, size)  │
│  3. Rate limiting                │
│  4. Route to appropriate backend │
└──────────┬───────────────────────┘
           │
     ┌─────┼──────────────────┐
     │     │                  │
     ▼     ▼                  ▼
┌────────┐ ┌─────────┐ ┌──────────┐
│ Local  │ │ ZAI     │ │Pollina-  │
│llama-cp│ │(Zhipu)  │ │tions     │
│(1235)  │ │Cloud API│ │Cloud API │
└────────┘ └─────────┘ └──────────┘
     │
     ▼
┌──────────────────────────────────┐
│  Response Pipeline               │
│  - Circuit breaker tracking      │
│  - Metrics collection            │
│  - Optional RAG enrichment       │
└──────────────────────────────────┘
```

### Authentication Model

Three modes configured via `services.ai-inference.auth.mode`:

| Mode | Description | Use Case |
|------|-------------|----------|
| `"none"` | No authentication | LAN-only, development |
| `"api-key"` | Bearer token auth | Production with external access    };gn  - CS----------ss    };gn��────cf��─   ┌─────┼───�
�         ation | LAN-dules/services/ai-inference/
├── default.nix      kgs.lib via `servicUTPUT.ttry po- "$TEXai-inf
: in `modules/defauw��────┌──�f declarations*i}k pele language = l-infer}�─sl
Dn      kes).

## AI Infe| ` │     │    ──┌──�f declarae| ` │     │ Infr   ←nes/defa� mcp_CtPs-regis-inference/
�rCloud AI Infe| ` �b.types.str;
         MODEL_Pd─�=$(cat "$"u│
│  - s).

## AI Infe|─�| ` �b.ty)mcp_ - 4)D4u f [gface.co/ggerganov/wh �───�        R       MODEL_    M       R       MO�─← Qdrant vector^[[:space:]]*//;sNo audio recorded" --entS        ``

### Aut��      oduction-ready gateway for LLM APICt��      oUIC    oducti# Secret Categr  MO�─← Qdrr:spaeAn                                                     descriptiometheu                 lig2��─┌� |
| `"api-�─tiv w

The AI Inference Service proviyv"api-� s).

## AIo
| O�──�ontrge                 IC���─┼Ctg�│
└─�.

## 000000053i# or ty-���dg**:
      pping�─┼Ct
Enable on          ib.mk�� |