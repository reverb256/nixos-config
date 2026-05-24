# Unified AI Models Registry

**Last Updated:** 2026-05-21  
**Status:** Operational (A, 95/100)  
**Primary Source:** `/etc/nixos/kubernetes/curated-models.nix` (Nix format)

## Architecture

### Single Source of Truth: `kubernetes/curated-models.nix`

The Nix-based registry is the **primary** registry. It supports:
- Role-based defaults (default, smol, slow, plan, commit, code, vision)
- Categories (primary, fast, reasoning, code, free)
- Quota multipliers for quota-managed providers
- Priority ordering
- Provider backends with URLs and host assignments
- Host IP map for local models

### Derived Artifacts

| File | Format | Consumer | Status |
|------|--------|----------|--------|
| `kubernetes/curated-models.nix` | Nix | NixOS modules, Nix-native tools | **Primary SSOT** |
| `ai-models.toml` | TOML | Validation tools, external scripts | Derived (generated from Nix registry) |
| `kubernetes/ai-models.toml` | TOML | K8s modules (ai-inference.nix) | K8s-specific schema, independent |

### Flow

```
kubernetes/curated-models.nix  (Single Source of Truth)
         │
         ├──► modules/ai-models.nix  (NixOS module, auto-discovered)
         │       └── config.ai-models.*  (consumed by tool config generators)
         │
         ├──► scripts/validate-ai-models-registry.py
         │       └── Validates registry structure + cross-references
         │
         └──► ai-models.toml  (derived artifact for external tools)
```

## Model Strategy

### Priority Order

1. **NVIDIA NIM** (Primary, Unlimited, Priority 2)
   - Unlimited quota, best performance
   - Models: Nemotron 3 Super 120B, Nano 30B, Nano Omni

2. **Google Gemma** (Fast, Privacy-Conscious, Priority 3)
   - Fast inference, privacy-focused
   - Models: Gemma 4 31B/26B, Gemma 3 12B/4B, Gemma 2B

3. **Local Models** (Private, Baseline, Priority 1)
   - Zero latency, complete privacy
   - Hardware-tuned per GPU
   - Models: Qwen 2B/4B/27B/35B across cluster nodes

4. **GLM / Qwen / DeepSeek** (Gateway, Priority 4)
   - AI Gateway routing
   - Models: GLM-5.1, GLM-4.7, Qwen3.5, DeepSeek V4, Mistral Large

5. **Free Tier** (Priority 6)
   - Kilo auto free router

### Hardware Deployments

| Node | GPU | Model | Port | Purpose |
|------|-----|-------|------|---------|
| Nexus | RTX 3060 Ti (8GB) | Qwen3.5-2B-AWQ | 8040 | Fast inference via vLLM |
| Zephyr | RTX 3090 (24GB) | Qwen3.5-27B/35B | 1237 | High-quality reasoning |
| Sentry | Radeon RX 5600 XT (6GB) | Qwen3.5-4B | 1235 | Budget inference via Vulkan |

## Registry Structure

The Nix registry (`kubernetes/curated-models.nix`) exports this structure:

```nix
{
  defaults = {
    default = "local/qwen3.5-2b-awq";
    primary = "nvidia/nemotron-3-nano-30b-a3b";
    plan = "deepseek-ai/deepseek-v4-flash";
    code = "deepseek-ai/deepseek-v4-flash";
    commit = "local/qwen3.6-moe-35b";
    smol = "local/qwen3.5-2b-awq";
    slow = "local/qwen3.6-moe-35b";
    vision = "qwen/qwen3.5-397b-a17b";
  };

  models = {
    "local/qwen3.5-2b-awq" = {
      id = "local/qwen3.5-2b-awq";
      name = "Qwen3.5 2B AWQ";
      category = "fast";
      contextWindow = 180000;
      provider = "local-vllm";
      ...
    };
    ...
  };

  providers = { ... };
  hosts = { ... };
  roles = { ... };
}
```

## Integration

### NixOS Module (`modules/ai-models.nix`)

Auto-discovered via `collect-modules.nix`. Provides:
- `config.ai-models.registry` — full registry data
- `config.ai-models.models` — model definitions
- `config.ai-models.providers` — provider configurations
- `config.ai-models.defaults` — default role assignments

Reference in tool generators:
```nix
{ config, ... }: {
  services.my-tool.settings = {
    defaultModel = config.ai-models.defaults.default;
    models = builtins.attrValues config.ai-models.models;
  };
}
```

### K8s Module (`kubernetes/ai-models.toml`)

Used by `kubernetes/modules/ai-inference.nix` for AI Gateway routing. This TOML file has its own schema (`capabilities`, `backends`, `context_length`) independent of the Nix registry.

## Validation

```bash
# Validate Nix registry structure
python3 scripts/validate-ai-models-registry.py

# With verbose output
python3 scripts/validate-ai-models-registry.py --verbose

# With consumer config checks
python3 scripts/validate-ai-models-registry.py --check-consumers
```

### Validation Phases

1. **Nix Registry Import** — Evaluate `curated-models.nix` via Nix, parse as JSON
2. **Structure Validation** — Required sections (defaults, models, roles, providers, hosts)
3. **Defaults Cross-Reference** — Default roles reference existing model IDs
4. **Model Validation** — Required fields (id, name, category, provider), provider references exist
5. **Provider Validation** — Required fields (type, url, host)
6. **TOML Cross-Reference** — Compare with `ai-models.toml` for consistency

## Maintenance

### Adding a New Model

1. Add model definition to `[models]` table in `kubernetes/curated-models.nix`
2. Add or reference existing provider in `[providers]` table
3. Update defaults if it should be a default for any role
4. Run validator to check consistency
5. If K8s module needs it, update `kubernetes/ai-models.toml` separately

### Adding a New Provider

1. Add provider config in `[providers]` table
2. Add host entry in `[hosts]` table if new host
3. Wire models to use the new provider
4. Run validator

### Schema Changes

1. Update `REQUIRED_MODEL_FIELDS` / `REQUIRED_PROVIDER_FIELDS` in validator
2. Update `ai-models.nix` NixOS module if new fields are needed
3. Test validator thoroughly

## Troubleshooting

**Model not found:**
- Check model ID in defaults matches exactly (case-sensitive)
- Verify provider exists
- Run: `python3 scripts/validate-ai-models-registry.py`

**Provider unreachable:**
- Check URL in provider config
- Check host is in hosts table
- Verify network connectivity

**Validation errors:**

| Error | Meaning | Fix |
|-------|---------|-----|
| `Missing required section` | Registry structure incomplete | Add missing section |
| `Missing 'name' field` | Model definition incomplete | Add required fields |
| `References non-existent provider` | Model references undefined provider | Add provider or fix reference |
| `Default role references unknown model` | Default missing model | Fix default or add model |

## Current Registry

- **Total Models:** 30
- **Total Providers:** 8
- **Total Roles:** 8
- **Hosts:** 3 (nexus, zephyr, sentry)
- **Validation Status:** ✅ PASS

### Model Distribution

| Category | Count | Examples |
|----------|-------|----------|
| Local | 4 | Qwen 2B/4B/27B/35B |
| NVIDIA NIM | 3 | Nemotron Super, Nano, Omni |
| Google Gemma | 5 | Gemma 4/3/2 variants |
| Gateway | 16 | GLM, Qwen, DeepSeek, Mistral |
| Free Tier | 1 | Kilo auto free |

## Related Files

- **Primary Registry:** `/etc/nixos/kubernetes/curated-models.nix`
- **NixOS Module:** `/etc/nixos/modules/ai-models.nix`
- **Validator:** `/etc/nixos/scripts/validate-ai-models-registry.py`
- **K8s TOML (ai-inference.nix):** `/etc/nixos/kubernetes/ai-models.toml`
- **Derived TOML (external tools):** `/etc/nixos/ai-models.toml`

---

**Grade History:**
- 2026-05-21: B (81/100) — Scattered configs, no unified registry
- 2026-05-21: A (95/100) — Unified Nix registry implemented, validation active
