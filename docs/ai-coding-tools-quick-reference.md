# AI Coding Tools - Quick Reference
**Last Updated**: 2026-03-21

## 🚀 Quick Start

### Understanding the Deployment

**Important**: The pods provide **home directory access**, not the tools themselves. The actual Claude Code and OpenCode tools run on the **host system** (via NixOS).

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Pods (one per node)                               │
│  • Mount /home/j_kro from host                              │
│  • Provide remote access to config files from any node      │
│  • Simple busybox containers (no NixOS binaries)            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Host System (where tools actually run)                      │
│  • Claude Code: /run/current-system/sw/bin/claude           │
│  • OpenCode: /home/j_kro/.nix-profile/bin/opencode         │
│  • Config: ~/.claude/, ~/.opencode/                         │
└─────────────────────────────────────────────────────────────┘
```

### Access Patterns

```bash
# From the host where you're working
claude                  # Run Claude Code directly
opencode                # Run OpenCode directly

# From a different node (via SSH)
ssh zephyr              # Connect to node with tools
claude                  # Run Claude Code on that node

# Access config files via Kubernetes pods
claude-k8s /bin/sh      # Open shell in pod (has /home/j_kro mounted)
```

## 📍 Current Status

| Tool | Pod | Node | Status | Access |
|------|-----|------|--------|--------|
| Claude Code | `claude-code-d4cc8f78-k5rtz` | Zephyr | ✅ Running (2/2) | From any node |
| OpenCode | `opencode-6f7694494f-84fdk` | Zephyr | ✅ Running (2/2) | From any node |

**Note**: Pods run on Zephyr but are accessible from ALL 4 nodes via wrapper scripts.

## 🔧 Wrapper Scripts Location

```bash
/usr/local/bin/claude-k8s    # Claude Code wrapper
/usr/local/bin/opencode-k8s  # OpenCode wrapper
```

Source: `/etc/nixos/kubernetes-manifests/ai-coding-tools/`

## 📋 What the Wrappers Do

1. **Find running pod** automatically
2. **Show status** and connection info
3. **Execute commands** in the pod
4. **Handle errors** gracefully

## 🎯 Common Commands

### Check Pod Status
```bash
claude-k8s              # Show Claude Code pod status
opencode-k8s            # Show OpenCode pod status
```

### Run Tools (on Host)
```bash
# Claude Code (from any node with NixOS)
claude

# OpenCode (from any node with NixOS)
opencode
```

### Access Config Files (via Pods)
```bash
# Open shell in pod (has /home/j_kro mounted)
claude-k8s /bin/sh
opencode-k8s /bin/sh

# List config files from pod
claude-k8s /bin/ls -la /home/j_kro/.claude
opencode-k8s /bin/ls -la /home/j_kro/.opencode

# View history from pod
claude-k8s /bin/cat /home/j_kro/.claude/history.jsonl | tail -5

# Check config from pod
opencode-k8s /bin/cat /home/j_kro/.opencode/config.json
```

### Direct Pod Access
```bash
# List all pods
kubectl get pods -n ai-coding -o wide

# Exec into specific pod
kubectl exec -it -n ai-coding claude-code-<pod-name> -- /bin/sh
kubectl exec -it -n ai-coding opencode-<pod-name> -- /bin/sh
```

## 🌐 Multi-Node Access

The wrappers work from **any node**:

```bash
# On Zephyr (where pods run)
ssh zephyr
claude-k8s

# On Nexus (accesses pods on Zephyr remotely)
ssh nexus
claude-k8s

# On Forge (accesses pods on Zephyr remotely)
ssh forge
claude-k8s

# On Sentry (accesses pods on Zephyr remotely)
ssh sentry
claude-k8s
```

## 📊 Pod Information

```bash
# List all AI coding pods
kubectl get pods -n ai-coding

# Watch pod status
kubectl get pods -n ai-coding -w

# Describe pod
kubectl describe pod -n ai-coding claude-code-d4cc8f78-k5rtz

# View logs
kubectl logs -n ai-coding claude-code-d4cc8f78-k5rtz -c claude-code-wrapper
kubectl logs -n ai-coding opencode-6f7694494f-84fdk -c opencode-wrapper
```

## 🛠️ Troubleshooting

### Wrapper not found?
```bash
# Check symlink exists
ls -la /usr/local/bin/claude-k8s
ls -la /usr/local/bin/opencode-k8s

# If missing, recreate:
sudo ln -sf /etc/nixos/kubernetes-manifests/ai-coding-tools/claude-access.sh /usr/local/bin/claude-k8s
sudo ln -sf /etc/nixos/kubernetes-manifests/ai-coding-tools/opencode-access.sh /usr/local/bin/opencode-k8s
```

### No pods running?
```bash
# Check pods
kubectl get pods -n ai-coding

# Check deployments
kubectl get deployments -n ai-coding

# Restart if needed
kubectl rollout restart deployment/claude-code -n ai-coding
kubectl rollout restart deployment/opencode -n ai-coding
```

### Can't connect to pod?
```bash
# Check pod status
kubectl get pods -n ai-coding -o wide

# Check pod logs for errors
kubectl logs -n ai-coding -l app=claude-code --tail=50

# Test from pod
kubectl exec -n ai-coding claude-code-d4cc8f78-k5rtz -- ps aux
```

## 📝 Configuration Locations

| Tool | Config Path | Pod Path |
|------|-------------|----------|
| Claude Code | `/home/j_kro/.claude/` | `/home/j_kro/.claude/` |
| OpenCode | `/home/j_kro/.opencode/` | `/home/j_kro/.opencode/` |

**Important**: Config is stored on Zephyr's filesystem and mounted into the pod.

## 🔄 Updating Configuration

Changes made in the pod are immediately reflected on the host:

```bash
# Inside pod
claude-k8s /bin/bash
cd /home/j_kro
echo "test" >> .claude/test.txt
exit

# On host (Zephyr)
cat /home/j_kro/.claude/test.txt  # File exists!
```

## 🎉 Summary

- ✅ **Claude Code**: Running and accessible via `claude-k8s`
- ✅ **OpenCode**: Running and accessible via `opencode-k8s`
- ✅ **Multi-node**: Accessible from all 4 nodes
- ✅ **Persistent**: Config stored on Zephyr, mounted into pods
- ✅ **Simple**: Just use the wrapper commands!

## 📚 Documentation

- `docs/ai-coding-tools-multi-node-deployment.md` - Multi-node options
- `docs/ai-inference-status-2026-03-21.md` - Gateway status
- `kubernetes-manifests/ai-coding-tools/` - Deployment configs
