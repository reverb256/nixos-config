# AI Coding Tools - Quick Reference

## 🚀 Deploy to Kubernetes

```bash
cd /etc/nixos/kubernetes-manifests/ai-coding-tools
./deploy.sh
```

## 💻 Daily Usage

### Claude Code

```bash
# Interactive (exactly like CLI)
./claude-k8s.sh

# Quick prompt
./claude-k8s.sh "explain this code"

# Use specific pod
./claude-k8s.sh --pod claude-code-xxxxx "help me debug"
```

### OpenCode

```bash
# Interactive
./opencode-k8s.sh

# Quick prompt
./opencode-k8s.sh "refactor this function"
```

## 📊 Check Status

```bash
# All pods
kubectl get pods -n ai-inference -l component=ai-coding-tool

# Claude Code only
kubectl get pods -n ai-inference -l app=claude-code

# OpenCode only
kubectl get pods -n ai-inference -l app=opencode

# Autoscaling status
kubectl get hpa -n ai-inference
```

## 🔍 Debugging

```bash
# Pod logs
kubectl logs -n ai-inference claude-code-xxxxx

# Pod details
kubectl describe pod -n ai-inference claude-code-xxxxx

# Exec into pod
kubectl exec -it -n ai-inference claude-code-xxxxx -- /bin/bash

# Metrics
kubectl exec -n ai-inference claude-code-xxxxx -- curl -s localhost:9090/metrics
```

## 🎯 Key Features

✅ **Same config as CLI** - Mounts ~/.claude and ~/.opencode
✅ **Preserves history** - All conversations saved to same location
✅ **MCP servers** - All your existing MCP servers work
✅ **Auto-scales 1-5 pods** - Based on active conversations
✅ **Load balancing** - Automatically uses least busy pod
✅ **Session affinity** - Stay with same pod during conversation

## 📈 Autoscaling

```
Claude Code: 1 → 5 pods
  Scale up:   When avg 3+ sessions/pod
  Scale down: After 5 min low activity

OpenCode:    1 → 3 pods
  Scale up:   When CPU > 70%
  Scale down: After 3 min low activity
```

## 🔧 Configuration

All configs mounted from host:
- `~/.claude/` → `/home/j_kro/.claude/`
- `~/.opencode/` → `/home/j_kro/.opencode/`
- `~/.claude.json` → `/home/j_kro/.claude.json`

Changes to local files immediately visible in pods!

## 🆘 Troubleshooting

**Pod can't start?**
```bash
kubectl describe pod -n ai-inference claude-code-xxxxx
# Check events section for errors
```

**Config not visible?**
```bash
kubectl exec -n ai-inference claude-code-xxxxx -- ls -la /home/j_kro/.claude
# Should show your config files
```

**Autoscaling not working?**
```bash
kubectl describe hpa claude-code-hpa -n ai-inference
# Check conditions and metrics
```

## 📚 Documentation

- `README.md` - Architecture and design
- `SUMMARY.md` - Complete documentation
- `QUICKSTART.md` - This file

## 🎉 You're Ready!

```bash
./deploy.sh
./claude-k8s.sh "hello from kubernetes!"
```
