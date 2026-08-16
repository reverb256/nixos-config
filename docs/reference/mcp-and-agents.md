# MCP infrastructure and agent conventions

**Last Verified:** 2026-08-16
**Status:** Reference
**Owner:** j_kro

## MCP servers

| Environment | Servers |
|-------------|---------|
| In-cluster | kubernetes-mcp (SSE :8080 on nexus), nixos-cluster-mcp (DaemonSet, SSE :8081 all nodes) |
| Claude Code | `nix run /etc/nixos#kubernetes-mcp-server`, `nix run /etc/nixos#nixos-cluster-mcp` |
| Hermes | SSE for kubernetes, stdio for others |
| OpenCode / OmP / PI | see their `mcp.json` under `~/.config/opencode`, `~/.omp`, `~/.pi` |

Registry: `modules/services/mcp-server-registry.nix` is the single source of truth.

## Local model endpoints

| Provider | URL | Model |
|----------|-----|-------|
| local-vllm | 10.1.1.110:8040 | Qwen3.5-2B-AWQ (Zephyr 3060 Ti) |
| local-llama-zephyr | 10.1.1.110:1237 | Qwen3.6-35B-A3B (Zephyr 3090) |
| local-llama-sentry | 10.1.1.140:1235 | Qwen3.5-4B (Sentry ROCm) |

## AI agent coding principles (non-negotiable)

1. TDD is mandatory — tests before implementation; no test, no merge.
2. Fresh context over compaction — checkpoint and restart when context degrades.
3. Vertical slicing — every task cuts across all layers.
4. Two-stage review — spec compliance first, code quality second.
5. Push/pull standards — implementers pull conventions on demand; reviewers get them inline.
6. Alignment before planning — grill-me before writing plans.

Hermes injects these rules into dispatched subagents; subagents do not need to
carry the skills themselves.
