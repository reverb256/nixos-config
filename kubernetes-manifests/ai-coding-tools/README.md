# AI Coding Tools on Kubernetes

## Current Setup Analysis

### Claude Code
- **Config**: `~/.claude/` and `~/.claude.json`
- **MCP Servers**:
  - zai-mcp-server (Z.AI API)
  - web-reader (web scraping)
  - zread (GitHub repo reader)
  - web-search-prime (search)
  - context7 (documentation)
- **Mode**: Interactive CLI with 4,500+ startups

### OpenCode
- **Config**: `~/.opencode/config.json`
- **Provider**: LM Studio (local) on `http://127.0.0.1:8080/v1`
- **Model**: magnum-opus-35b-a3b-i1 (Qwen3.5-35B IQ4_XS)
- **Mode**: Interactive CLI

## Kubernetes Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Shared Storage (NFS/longhorn)          │   │
│  │  - /home/j_kro/.claude (history, plugins, plans)    │   │
│  │  - /home/j_kro/.opencode (config, node_modules)    │   │
│  │  - /home/j_kro/.claude.json (settings)             │   │
│  └─────────────────────────────────────────────────────┘   │
│                         ▲         ▲                          │
│                         │         │                          │
│  ┌──────────────────────┘         └──────────────────────┐  │
│  │                                                            │
│  │  ┌──────────────────┐          ┌──────────────────┐    │
│  │  │  Claude Code     │          │    OpenCode      │    │
│  │  │  Deployment      │          │   Deployment     │    │
│  │  │  (1-10 pods)     │          │  (1-10 pods)     │    │
│  │  │                  │          │                  │    │
│  │  │  - Mount configs │          │  - Mount configs │    │
│  │  │  - MCP servers   │          │  - Connect to   │    │
│  │  │  - History PV    │          │    LM Studio    │    │
│  │  └──────────────────┘          └──────────────────┘    │
│  │                                                            │
│  │  ┌──────────────────────────────────────────────────┐  │
│  │  │         Metrics Exporter (Shared)               │  │
│  │  │  - active_conversations (per tool)              │  │
│  │  │  - session_duration                             │  │
│  │  │  - tokens_used                                  │  │
│  │  └──────────────────────────────────────────────────┘  │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   HPA                                │   │
│  │  Scale 1-10 pods based on:                          │   │
│  │  - Active conversations (custom metric)             │   │
│  │  - CPU/Memory usage                                 │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

External Services:
┌──────────────────────┐        ┌──────────────────────┐
│   LM Server          │        │   AI Inference       │
│   (127.0.0.1:8080)   │◄───────┤   Gateway            │
│                      │        │   (llama.cpp)         │
└──────────────────────┘        └──────────────────────┘
```

## Access Methods

### 1. Interactive CLI (kubectl exec)
```bash
# Claude Code
kubectl exec -it -n ai-coding claude-code-xxxxx -- claude-code

# OpenCode
kubectl exec -it -n ai-coding opencode-xxxxx -- opencode
```

### 2. Shell Wrapper (Recommended)
```bash
# Claude Code
./claude-k8s.sh "help me with this code"

# OpenCode
./opencode-k8s.sh "explain this function"
```

### 3. Web UI (Future)
- Expose via Ingress
- Browser-based terminal (xterm.js)
- WebSocket connection to pods

## Storage Strategy

### Option 1: Read-Write Many (RWX) PVC
- Use Longhorn or NFS
- All pods share same config/history
- **Pros**: True multi-writer, simple
- **Cons**: Performance overhead

### Option 2: Read-Only + Sync
- ConfigMap for read-only config
- PVC for writeable data (history)
- **Pros**: Better performance
- **Cons**: Complex sync logic

### Option 3: Per-Pod PVC + StatefulSet
- Each pod gets own PVC
- StatefulSet for stable identities
- **Pros**: Best performance, no conflicts
- **Cons**: History fragmented across pods

**Recommended**: Option 1 (RWX PVC) for simplicity
