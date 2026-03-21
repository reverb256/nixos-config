# AI Coding Tools - Multi-Node Deployment Options
**Date**: 2026-03-21
**Goal**: Make Claude Code and OpenCode available on all 4 cluster nodes

## Current Status

**Deployment**: Single-node (Zephyr only)
- **Reason**: HostPath volumes mount `/home/j_kro` which only exists on Zephyr
- **Access**: Use wrapper scripts from any node (pods run on Zephyr, accessible cluster-wide)

## Quick Access Commands

```bash
# From any node in the cluster
claude-k8s                  # Show status and usage info
claude-k8s /bin/bash        # Open shell in Claude pod
claude-k8s /run/current-system/sw/bin/claude --help

opencode-k8s                # Show status and usage info
opencode-k8s /bin/bash      # Open shell in OpenCode pod
```

## Multi-Node Deployment Options

### Option 1: Keep Single-Node (Current) ⭐ **RECOMMENDED**

**Pros**:
- ✅ Simplest setup
- ✅ Works perfectly right now
- ✅ No storage complexity
- ✅ Accessible from any node via kubectl

**Cons**:
- ❌ All traffic goes to Zephyr
- ❌ Single point of failure

**Implementation**: Already done! Just use the wrapper scripts.

---

### Option 2: Per-Node Deployments

Create separate deployment for each node with local home directories.

**Pros**:
- ✅ True multi-node deployment
- ✅ No shared storage needed
- ✅ Better isolation

**Cons**:
- ❌ Config not shared between nodes
- ❌ More complex deployment
- ❌ Different home directories on each node

**Implementation**:
```yaml
# For each node (forge, nexus, sentry)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: claude-code-forge
  namespace: ai-coding
spec:
  replicas: 1
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: forge
      volumes:
      - name: home-dir
        hostPath:
          path: /home/j_kro  # Must exist on Forge!
          type: Directory
```

**Requirements**:
- Create `/home/j_kro` on each node
- Sync config between nodes
- Deploy 4 separate deployments

---

### Option 3: Shared Storage (NFS/Garage)

Use shared filesystem accessible from all nodes.

**Pros**:
- ✅ True multi-node
- ✅ Shared config and history
- ✅ Single deployment

**Cons**:
- ❌ Requires NFS or shared storage setup
- ❌ Network dependency
- ❌ Performance overhead

**Implementation**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: home-dir-pvc
  namespace: ai-coding
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: nfs  # Or garage-nfs

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: claude-code
  namespace: ai-coding
spec:
  replicas: 4  # One per node
  template:
    spec:
      volumes:
      - name: home-dir
        persistentVolumeClaim:
          claimName: home-dir-pvc
      # Remove nodeSelector to allow scheduling on any node
```

**Requirements**:
- NFS server or shared storage
- ReadWriteMany PVC support
- Network configuration

---

### Option 4: Pod Distruption Budget + Anti-Affinity

Allow single deployment with replicas spread across nodes.

**Pros**:
- ✅ Kubernetes manages distribution
- ✅ High availability
- ✅ Simple deployment

**Cons**:
- ❌ Still need shared storage
- ❌ More complex configuration
- ❌ Requires /home/j_kro on all nodes or PVC

**Implementation**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: claude-code
  namespace: ai-coding
spec:
  replicas: 4
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - claude-code
              topologyKey: kubernetes.io/hostname
      # Use PVC or ensure /home/j_kro exists on all nodes
```

---

### Option 5: Image with Baked Configuration

Build container images with config embedded.

**Pros**:
- ✅ No external storage dependency
- ✅ True multi-node
- ✅ Portable

**Cons**:
- ❌ Config updates require rebuilding images
- ❌ Can't persist history easily
- ❌ More complex build process

**Implementation**:
```dockerfile
FROM busybox:1.36
# Copy config during image build
COPY .claude.json /root/.claude.json
COPY .claude/ /root/.claude/
```

---

## Recommendation

**For now: Use Option 1 (Single-Node)**

**Why**:
1. Already working perfectly
2. Accessible from any node via wrapper scripts
3. No additional complexity
4. /home/j_kro only exists on Zephyr anyway

**When to consider multi-node**:
- Need high availability (Zephyr goes down)
- Need to distribute load across nodes
- Have shared storage infrastructure ready

## Wrapper Script Usage

### Claude Code
```bash
# Show status
claude-k8s

# Open interactive session
claude-k8s /run/current-system/sw/bin/claude

# Execute command
claude-k8s /bin/ls -la /home/j_kro/.claude

# Open shell
claude-k8s /bin/bash
```

### OpenCode
```bash
# Show status
opencode-k8s

# Open interactive session
opencode-k8s /home/j_kro/.nix-profile/bin/opencode

# Execute command
opencode-k8s /bin/ls -la /home/j_kro/.opencode

# Open shell
opencode-k8s /bin/bash
```

## Access from Any Node

The wrapper scripts work from **any node** in the cluster:

```bash
# On Zephyr
ssh zephyr
claude-k8s

# On Nexus
ssh nexus
claude-k8s  # Works! Accesses pods on Zephyr

# On Forge
ssh forge
claude-k8s  # Works! Accesses pods on Zephyr

# On Sentry
ssh sentry
claude-k8s  # Works! Accesses pods on Zephyr
```

## Making It Truly Multi-Node (Future)

If you want to proceed with multi-node deployment, here's the checklist:

### Phase 1: Storage
- [ ] Set up NFS/Garage shared storage
- [ ] Create ReadWriteMany PVC
- [ ] Test read/write performance

### Phase 2: Home Directory
- [ ] Create /home/j_kro on all nodes OR use PVC
- [ ] Sync existing config to shared storage
- [ ] Test config access from all nodes

### Phase 3: Deployment
- [ ] Remove nodeSelector from deployments
- [ ] Add podAntiAffinity rules
- [ ] Scale to 4 replicas
- [ ] Verify one pod per node

### Phase 4: Testing
- [ ] Test from each node
- [ ] Verify config persistence
- [ ] Test failover scenarios
- [ ] Monitor performance

## Current Access Summary

| Node | Pod Location | Access Method | Works? |
|------|-------------|---------------|---------|
| Zephyr | Local | kubectl/wrapper | ✅ Yes |
| Nexus | Remote (Zephyr) | kubectl/wrapper | ✅ Yes |
| Forge | Remote (Zephyr) | kubectl/wrapper | ✅ Yes |
| Sentry | Remote (Zephyr) | kubectl/wrapper | ✅ Yes |

**Result**: All nodes can access the tools, even though pods only run on Zephyr.

## Next Steps

1. **Immediate**: Start using the wrapper scripts
   ```bash
   claude-k8s    # From any node
   opencode-k8s  # From any node
   ```

2. **If needed**: Implement shared storage (Option 3)

3. **Future**: Consider multi-node when HA is required

## Files

- `/usr/local/bin/claude-k8s` → Claude Code wrapper
- `/usr/local/bin/opencode-k8s` → OpenCode wrapper
- `/etc/nixos/kubernetes-manifests/ai-coding-tools/` → Deployment configs
