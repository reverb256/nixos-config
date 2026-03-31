# User Testing

Testing surface discovery, resource cost classification, and tool requirements for validation.

## Validation Surface

This mission has **three testing surfaces**:

### Surface 1: Filesystem / CLI (primary)
- **Tool**: bash (curl, rg, test, git)
- **What**: Verify config files, code changes, secrets, git state
- **No browser needed** - all verification is CLI-based

### Surface 2: API Endpoints (secondary)
- **Tool**: curl
- **What**: Gateway health, model list, Claude Code Router health
- **Endpoints**:
  - `http://127.0.0.1:8080/health` (AI Gateway)
  - `http://127.0.0.1:8080/v1/models` (Model list)
  - `http://localhost:3456/health` (Claude Code Router)

### Surface 3: Gateway Tests (automated)
- **Tool**: pytest via nix-shell
- **Command**: `nix-shell /etc/nixos/modules/services/ai-inference/ai_inference_gateway/shell.nix --run "pytest tests/ -v"`
- **21 test files, Python 3.13, no K8s needed**

## Validation Concurrency

- **Max concurrent validators**: 5
- **Memory per validator**: ~100MB (lightweight - mostly file reads and curl)
- **Machine resources**: 32 cores, 31GB RAM (but ~22GB used - memory pressure on Zephyr)
- **Available headroom**: ~8GB * 0.7 = 5.6GB for validators

## Required Skills

- No agent-browser or tuistory needed
- Standard bash/curl for all validation
