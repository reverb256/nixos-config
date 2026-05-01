# K8s MCP Server — Cluster Orchestration via Model Context Protocol

**Date:** 2026-05-01 | **Status:** Approved | **Branch:** main

## Objective

Provide MCP-based Kubernetes orchestration accessible from all AI tools (Claude Code, Hermes, OpenCode, etc.) both locally and in-cluster.

## Architecture

```
containers/kubernetes-mcp-server (base — Go binary)
├── Standard K8s tools (kubectl_get, logs, pods_list, helm, etc.)
├── Modular toolsets (core/helm/kiali/kubevirt)
├── Dual transport: stdio (local) + SSE/HTTP (remote)
│
nixos-cluster extension (custom Python FastMCP)
├── cluster_status — nodes + pods + resources + health
├── safe_scale — scale with pod explosion prevention guards
├── deploy_host — nixos-rebuild switch / Colmena deploy
├── check_nix_store — verify /nix/store refs on target nodes
├── debug_pod — describe + events + logs for failing pods
├── edit_manifest — Nix edit + flake check + commit + deploy pipeline
└── forge_secrets — fix forge kubectl-apply-k8s-secrets connectivity
```

## Components

### 1. Base: containers/kubernetes-mcp-server
- Go binary, packaged via Nix flake input
- Stdio transport for Claude Code local sessions
- SSE transport for in-cluster agents (Hermes, etc.)
- Read-only by default, write operations require explicit enable
- Toolsets: core (required), helm (optional)

### 2. Extension: nixos-cluster-mcp (Python FastMCP)
- Thin Python MCP server using FastMCP library
- Wraps `just` commands, `kubectl`, and cluster-specific logic
- Enforces safety rules (pod explosion, zephyr OOM, node capacity)
- Runs as stdio alongside base server, or as HTTP/SSE for remote access

### 3. Integration: mcp-registry
- Register both servers in existing mcp-registry project
- NixOS module enables them per-host

## Transport

| Consumer | Transport | Location |
|----------|-----------|----------|
| Claude Code (workstation) | stdio | Local process on zephyr |
| Hermes (K8s pod) | SSE/HTTP | In-cluster service |
| OpenCode (K8s pod) | SSE/HTTP | Same endpoint |

## Deployment

1. Base server: Nix package + local kubeconfig for stdio, K8s Deployment for SSE
2. Extension: Nix package + systemd/user service for stdio, K8s Deployment for SSE
3. Both registered in mcp-registry for any AI tool to discover

## Security

- Base server: RBAC ServiceAccount with scoped permissions
- Extension: Runs with kubectl access from host (hostNetwork + kubeconfig)
- SSE endpoint behind Caddy ingress with API key auth (existing Casdoor JWT)
- No cluster-admin — least-privilege per toolset

## Files to Create/Modify

| File | Purpose |
|------|---------|
| `packages/kubernetes-mcp-server.nix` | Nix package for base Go binary |
| `packages/nixos-cluster-mcp/` | Python FastMCP extension |
| `modules/services/kubernetes-mcp.nix` | NixOS service module (stdio) |
| `kubernetes/modules/infrastructure.nix` | K8s deployment (SSE) |
| `/data/projects/own/mcp-registry/` | Register both servers |
