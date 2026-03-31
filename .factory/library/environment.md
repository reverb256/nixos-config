# Environment

Environment variables, external dependencies, and setup notes.

**What belongs here:** Required env vars, external API keys/services, dependency quirks.
**What does NOT belong here:** Service ports/commands (use `.factory/services.yaml`).

---

## Z.AI API

All AI tools use the same Z.AI API key managed via agenix:
- Encrypted: `/etc/nixos/secrets/zai-api-key.age`
- Runtime: `/run/agenix/zai-api-key` (decrypted on Zephyr only)
- API base URLs:
  - Anthropic-compatible: `https://api.z.ai/api/anthropic`
  - Coding plan (OpenAI-compatible): `https://api.z.ai/api/coding/paas/v4`
  - MCP endpoints: `https://api.z.ai/api/mcp/{service}/mcp`

## Python Environment

- Python 3.13
- Gateway test shell: `nix-shell /etc/nixos/modules/services/ai-inference/ai_inference_gateway/shell.nix`
- Test runner: pytest with asyncio support

## Tool Config Locations

| Tool | Config Location | Managed By |
|------|----------------|------------|
| Droid/Factory | `~/.factory/settings.json`, `~/.factory/mcp.json` | Factory platform |
| OpenCode | `~/.config/opencode/opencode.json` | NixOS (env.etc) or manual |
| Crush | `~/.config/crush/crush.json` | NixOS (env.etc) or manual |
| Claude Code | `~/.claude/settings.json`, `~/.config/claude/mcp.json` | Claude Code |
| AI Gateway | K8s deployment env vars | NixOS module |

## NixOS Rebuild Commands

```bash
just check     # Validate flake (fast, no build)
just switch    # Apply to local host (Zephyr)
just deploy    # Deploy to all hosts via Colmena
```
