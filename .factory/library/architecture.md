# Architecture

How the AI tool ecosystem works on this NixOS cluster.

## Components

```
┌─────────────────────────────────────────────────────────────┐
│                    User Tools (5)                            │
│  Droid/Factory │ OpenCode │ Crush │ Claude Code │ (any)     │
└───────┬────────────┬────────┬──────────┬──────────┬────────┘
        │            │        │          │          │
        ▼            ▼        ▼          │          ▼
   ┌─────────┐  ┌────────┐  ┌──────┐   │    ┌──────────┐
   │ Z.AI    │  │ Local  │  │Z.AI  │   │    │ Z.AI     │
   │ API     │  │Gateway │  │API   │   │    │ API      │
   └─────────┘  └────┬───┘  └──────┘   │    └──────────┘
                     │                   │
                     ▼                   ▼
              ┌──────────────┐   ┌──────────────┐
              │ K8s Gateway  │   │ Claude Code  │
              │ (FastAPI)    │   │ Router       │
              │ Port 8080    │   │ Port 3456    │
              └──────┬───────┘   └──────────────┘
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
    ┌──────────┐ ┌────────┐ ┌───────┐
    │llama.cpp │ │ Z.AI   │ │ Qdrant│
    │(Local)   │ │(Cloud) │ │(RAG)  │
    └──────────┘ └────────┘ └───────┘
```

## Data Flows

1. **Droid/Factory** -> Z.AI API directly (Anthropic-compatible endpoint) OR through gateway
2. **OpenCode** -> Local gateway (primary) -> llama.cpp (local) -> Z.AI (fallback)
3. **Crush** -> Z.AI API directly
4. **Claude Code** -> Claude Code Router (systemd) -> Z.AI API
5. **Any tool with MCP** -> MCP servers (zai-mcp-server, web-search-prime, web-reader, zread, searxng)

## Three-Tier Model Strategy

| Tier | Local Model | Cloud Fallback | Claude Mapping |
|------|------------|---------------|----------------|
| Orchestrator | qwen3.5-35b-a3b | glm-5 | Opus |
| Worker | qwen3.5-9b-opus-distilled | glm-4.7 | Sonnet |
| Validator | qwen3.5-4b | glm-4.5-air | Haiku |

## Secrets Architecture

- **Agenix** encrypts secrets in `/etc/nixos/secrets/*.age`
- Decrypted at runtime to `/run/agenix/*`
- ZAI API key: `/run/agenix/zai-api-key` (decrypted on Zephyr)
- All tools should reference this path or env vars derived from it

## Key Invariants

- No plaintext API keys in git-tracked files
- All NixOS changes must pass `nix flake check`
- Gateway runs in K8s (not systemd)
- Claude Code Router runs as systemd on Zephyr
- Tools that need the API key read from `/run/agenix/zai-api-key` or env vars
