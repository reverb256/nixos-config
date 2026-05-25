# Model Routing Harmonization Plan

**Last Verified:** 2026-05-18
**Status:** Draft

## Goal

Route ALL CLI tools (Hermes, Claude Code, OpenCode, OMP) through the AI Inference Gateway for unified model access, while preserving each tool's unique capabilities.

## Current State

### Gateway Backends (already running at nexus:30880/v1)

| Backend | Source | Models Available | Status |
|---------|--------|-----------------|--------|
| `zai` | Z.AI Coding Plan API | GLM-4.7, GLM-5-turbo, GLM-5.1, GLM-4.7-flash, etc. | ✅ |
| `opencode-go` | OpenCode Go middleware | deepseek-v4-flash, deepseek-v4-pro, kimi-k2, minimax | ✅ |
| `nvidia` | NVIDIA NIM API | 40+ models (Nemotron, Qwen, DeepSeek, LLama, etc.) | ✅ |
| `kilo` | Kilo API | Free/limited models | ✅ |
| `llama-sentry` | Sentry:1235 | Qwen3.5-4B-Q4_K_M.gguf (local) | ✅ Running |
| `llama-3060ti` | Nexus:8040 | qwen3.5-2b-awq | ❌ CrashLoopBackOff |
| `llama-3090` | Zephyr:1237 | Qwen3.6-35B-A3B IQ4_XS | ❌ OOM |

### Tool Routing (current)

| Tool | Primary Model | Connects To | Gateway? | Aux Models |
|------|--------------|-------------|----------|------------|
| Hermes | glm-5-turbo | Z.AI (direct) | Fallback only | embedding via HF |
| Claude Code | glm-4.7 (sonnet) | Z.AI Anthropic API | ❌ Direct | haiku: glm-4.5-air, opus: glm-5.1 |
| OpenCode | deepseek-v4-flash | Gateway :30880 | ✅ | small: nvidia/nemotron-3-nano-30b |
| OMP | glm-5.1 | Gateway :8080 | ✅ | Multiple GLM/NVIDIA models |

## Target Architecture

```
All Tools ──► AI Inference Gateway (nexus:30880/v1)
                  │
                  ├── zai ──────────► GLM-4.7, GLM-5.1, GLM-5-turbo
                  ├── opencode-go ──► deepseek-v4-flash, deepseek-v4-pro
                  ├── nvidia ───────► Nemotron, Qwen, DeepSeek, Llama (40+)
                  ├── kilo ─────────► Free models (fallback)
                  ├── llama-sentry ──► Qwen3.5-4B (local)
                  ├── llama-3090 ────► Qwen3.6-35B (local) [FIX]
                  └── llama-3060ti ──► qwen3.5-2b (local) [FIX]
```

## Per-Tool Configuration

### Hermes (~/.hermes/config.yaml, managed by hermes-cli.nix)

```
model: opencode-go/deepseek-v4-flash    # Preferred primary model

providers:
  gateway:                               # PRIMARY — routes everything
    base_url: http://nexus:30880/v1
    api_key_env: ZAI_API_KEY
    model: opencode-go/deepseek-v4-flash
  zai:                                   # FALLBACK — direct to Z.AI
    base_url: https://api.z.ai/api/coding/paas/v4
    api_key_env: ZAI_API_KEY

fallback_providers:
  - gateway
  - zai
  - nvidia                               # Direct if gateway down
```

### Claude Code (~/.claude/settings.json)

Claude Code speaks Anthropic API. The gateway speaks OpenAI API. No translation layer exists.

**Keep direct Z.AI route.** No change needed:
```
ANTHROPIC_BASE_URL: https://api.z.ai/api/anthropic
haiku: glm-4.5-air
sonnet: glm-4.7
opus: glm-5.1
```

**Future:** If gateway adds Anthropic-compatible endpoint, switch to:
```
ANTHROPIC_BASE_URL: http://nexus:30880/v1/anthropic
```

### OpenCode (~/.opencode/config.json)

Already routes through gateway. **Minor update needed:**
- Change `baseURL` from `http://10.1.1.110:30880/v1` to `http://nexus:30880/v1` (use hostname, not IP)
- Keep `opencode-go/deepseek-v4-flash` as primary
- Keep `nvidia/nemotron-3-nano-30b-a3b` as small_model

### OMP (~/.omp/agent/models.json)

Already routes through gateway. **Minor update:**
- Change `baseUrl` from `http://10.1.1.110:8080/v1` to `http://nexus:30880/v1`
- Keep model definitions (already comprehensive)

## Auxiliary Model Considerations

| Tool | Aux Needs | Current | Target |
|------|-----------|---------|--------|
| Hermes | Embedding (RAG) | HF local model | Gateway embedding endpoint if available, else keep local |
| Claude Code | Tool calling, vision | Via Z.AI Anthropic | Unchanged (Anthropic protocol) |
| OpenCode | Small model for simple tasks | nvidia/nemotron-3-nano-30b-a3b via gateway | Same, confirmed working |
| OMP | Multiple model tiers | All through gateway | Same, confirmed working |

## Implementation Order

### Phase 1: Fix Broken Backends (now)
1. **vLLM Nexus**: Add TORCHINDUCTOR_CACHE_DIR env var
2. **Zephyr 3090**: Reduce -ngl from 99 to ~60

### Phase 2: Gateway Config (next)
3. Pin gateway to nexus (nodeSelector)
4. Bump replicas to 2 for HA
5. Update backend URLs to use service names not IPs
6. Add gateway Anthropic endpoint consideration

### Phase 3: Tool Configs (next)
7. Update hermes-cli.nix template: gateway primary, deepseek default
8. Update OpenCode config URLs
9. Update OMP config URLs
10. Nix deploy: `just check && just switch && just deploy`

### Phase 4: Validation
11. Test each tool can reach all model sources through gateway
12. Verify fallback chain works (gateway → zai → nvidia)
13. Verify 2 fixed backends are stable

## Key Constraints
- Claude Code stays on Z.AI Anthropic API (protocol mismatch with gateway)
- Gateway must be healthy before tool configs switch to it
- All secrets (ZAI_API_KEY, NVIDIA_API_KEY, OPENCODE_GO_API_KEY) already in K8s secrets
- Gateway nodeSelector: nexus only (46GB RAM, avoid Zephyr OOM)
