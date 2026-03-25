# NixOS Cluster - Claude Code Context

## WHAT
NixOS flake-based 4-host Linux cluster (Zephyr, Nexus, Forge, Sentry) for AI inference, GPU computing, storage, and monitoring.

**Tech stack**: NixOS flakes, Kubernetes v1.35.0, Colmena, Just, Serena tools

**Current Branch**: `feature/x86-64-v3-migration` (main: `main`)

---

## COMMANDS
```bash
just check             # Validate flake (quick, no build)
just check-nfs         # Verify NFS mount health on all hosts
just build             # Build configuration for local host
just switch            # Apply to local host (auto-pauses CPU mining)
just deploy            # Deploy to all hosts via Colmena (NFS-based, no sync)
just deploy <host>     # Deploy to specific host (zephyr|nexus|forge|sentry)
just status            # Show cluster status
```

### Kubernetes Commands
```bash
kubectl get nodes                        # Node status
kubectl get pods --all-namespaces        # All pods
kubectl get pv,pvc -A                    # Persistent volumes
just cluster-status                      # Host + K8s status combined
```

---

## PROJECT STRUCTURE
```
/etc/nixos/
├── flake.nix              # Main flake with host definitions
├── colmena.nix            # Multi-host deployment (NFS-based architecture)
├── justfile               # CI/CD commands (no sync needed - NFS mount)
├── hosts/                 # Per-host configs (zephyr, nexus, forge, sentry)
│   └── <hostname>/configuration.nix
├── modules/               # Reusable modules (auto-imported via default.nix)
│   ├── profiles/          # Hardware, role, network profiles
│   ├── system/            # System-level modules
│   ├── services/          # Background services
│   └── compute-market/    # GPU resource marketplace
├── kubernetes-manifests/  # K8s manifests for migrated services
├── docs/                  # Comprehensive documentation
├── AGENTS.md              # Universal patterns for ALL agents
├── STATUS.md              # Real-time cluster health
└── .claude/               # Claude-specific files (agents, skills, settings)
```

**Architecture**: All remote hosts mount `/run/nixos-shared` (NFS from Zephyr) - no config sync needed

---

## CONVENTIONS

### Critical Safety Rules
- **IMPORTANT**: Use `lib.mkOptionDefault` in shared modules (NEVER direct assignment)
  - Direct assignment breaks SSH on all nodes
  - See @AGENTS.md Critical Safety Constraints for examples

- **CRITICAL**: KUBERNETES POD EXPLOSION PREVENTION
  - **NEVER apply nodeSelector without checking target node capacity FIRST**
    ```bash
    # BEFORE any nodeSelector change:
    kubectl top nodes
    kubectl describe node <target> | grep -A 5 "Allocated resources"
    kubectl get pods -n <namespace> --no-headers | wc -l
    ```
  - **ALWAYS check replica set count before deployment changes**

- **CRITICAL: WORKLOAD SCHEDULING - ZEPHYR OOM PREVENTION**
  - **ZEPHYR HAS CONSTANT OUM EXHAUSTION (31GB RAM, control plane + AI + gaming)**
  - **DEFAULT ALL NON-INFRASTRUCTURE, NON-MINING WORKLOADS TO NEXUS (46GB RAM)**
  - **Valid scheduling targets:**
    - **Nexus** (46GB RAM): Default for ALL workloads except:
      - Infrastructure (control plane, Calico, storage, monitoring)
      - Mining (must be on nodes with GPUs: forge, nexus, zephyr)
    - **Zephyr** (31GB RAM): ONLY infrastructure + mining
      - Control plane: kube-apiserver, etcd, kube-scheduler, kube-controller-manager
      - CNI: Calico components
      - Mining: gpu-miner-zephyr, xmrig-zephyr (RTX 3090 GPU)
      - NO OTHER WORKLOADS
    - **Forge** (15GB RAM): GPU mining only (2x NVIDIA + 2x AMD)
    - **Sentry** (31GB RAM): Monitoring, logging
  - **NEVER schedule stateless services, AI workloads, or applications to zephyr**
  - **Use nodeSelector or nodeAffinity to enforce nexus scheduling:**
    ```yaml
    spec:
      template:
        spec:
          nodeName: nexus  # Force scheduling to nexus
          # OR use affinity:
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
              - matchExpressions:
                - key: kubernetes.io/hostname
                  operator: In
                  values:
                  - nexus
    ```
    ```bash
    # IF > 20 replica sets exist, CLEAN UP FIRST
    kubectl get replicasets -A --no-headers | wc -l
    kubectl get replicasets -A -o json | jq -r '.items[] | select(.status.replicas==0) | "\(.metadata.namespace)/\(.metadata.name)"' | xargs -I {} kubectl delete replicetset {}
    ```
  - **NEVER scale deployments without checking current state**
    ```bash
    # Check BEFORE scaling:
    kubectl get deploy -A -o jsonpath='{range .items[?(@.spec.replicas>3)]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}'
    ```
  - **USE `--replicas=0` BEFORE deleting deployments**
    ```bash
    # CORRECT order:
    kubectl scale deploy <name> --replicas=0
    kubectl delete deploy <name>
    ```
  - **NEVER use `--all` flags with kubectl delete/scale**
    - Can cascade out of control creating hundreds of pods
    - Be SPECIFIC: `kubectl delete pods -n <namespace> -l <label>`
  - **Node scheduling priority: NEXUS > FORGE > SENTRY > ZEPHYR**
    - Zephyr has EXTREME RAM exhaustion at all times
    - **ALWAYS** use nodeSelector to force non-critical workloads to Nexus
    - Only infrastructure on Zephyr: calico-node, nix-node, nvidia-plugin, csi-node-driver
  - **Set revisionHistoryLimit: 2** (not default 10) on ALL deployments
    - Prevents accumulation of old replica sets
  - **Set maxSurge: 0** in RollingUpdate (not default 1)
    - Prevents creating extra pods during updates
  - **See**: `kubernetes-manifests/PREVENT_POD_EXPLOSION.md` for complete rules

- **CRITICAL**: NEVER background nixos-rebuild or similar long-running commands
  - Commands like `nixos-rebuild test`, `colmena apply` MUST show real-time output
  - User needs to see build progress, errors, and ETA
  - Backgrounding hides output and causes confusion

- **CRITICAL**: NEVER use Volcano scheduler for general workloads
  - Volcano is for batch/HPC/AI jobs with explicit PodGroup configuration
  - Use `default-scheduler` for stateless services (Deployments, StatefulSets)
  - Volcano requires RBAC setup for PodGroups or all deployments fail
  - See: `docs/kubernetes/volcano-scheduler-incident-2026-03-22.md`

- **CRITICAL**: Control plane restart order (if absolutely necessary)
  1. kube-apiserver (last to stop, first to start)
  2. kube-scheduler
  3. kube-controller-manager
  4. kubelet
  5. **NEVER restart etcd** unless absolutely necessary (breaks cluster)
  - etcd SIGTERM → kube-apiserver hangs → cascade failure

### Code Style
- 2-space indentation, trailing semicolons
- kebab-case for files and modules
- Line length 80-100 chars (soft limit 120)

---

## WORKFLOW

### Standard Deployment
1. Make changes on Zephyr (source of truth)
2. `nix flake check` (validate options, syntax)
3. `git add` new files (Nix only packages git-tracked files!)
4. `git commit`
5. `just deploy` (applies to all hosts via Colmena, uses NFS mount)

### Pre-commit Validation
**Always run** `nix flake check` to catch non-existent options before committing.
- Catches option typos (e.g., Home Manager incidents)
- Fast validation (<5 seconds)
- Prevents broken deployments

### Testing Checklist
| File Changed | Test On |
|--------------|---------|
| `modules/networking/*` | zephyr AND nexus |
| `modules/system/ssh.nix` | ALL 4 nodes |
| `modules/system/users.nix` | ALL 4 nodes |
| `modules/default.nix` | Entire cluster |

### Stop Immediately If
- SSH breaks on any node → Document incident, wait for human
- Multiple nodes affected → STOP ALL WORK
- `nix flake check` fails → Fix errors before committing

---

## SERENA TOOLS

**Use Serena for:**
- Understanding module structure (`get_symbols_overview()`)
- Finding symbol definitions (`find_symbol()`)
- Tracing references (`find_referencing_symbols()`)
- Multi-step refactoring or cross-file analysis

**Use standard tools for:**
- Simple file reading (`Read`)
- Basic pattern matching (`Grep`)
- File discovery (`Glob`)

---

## KUBERNETES TROUBLESHOOTING

### Common Issues & Quick Fixes

**Issue: Pods stuck in ContainerCreating or ImagePullBackOff**
```bash
kubectl describe pod <pod-name> -n <namespace>  # Check events
kubectl logs <pod-name> -n <namespace>          # Check logs
```

**Issue: Pods not scheduling (Insufficient resources)**
```bash
kubectl describe nodes | grep -A 5 "Allocated resources"  # Check resource usage
kubectl top pods -A                                         # Check pod resource usage
```

**Issue: GPU resources unavailable (nvidia.com/gpu)**
```bash
# Check GPU registration
kubectl describe node <node-name> | grep nvidia.com/gpu

# Check nvidia-device-plugin logs
kubectl logs -n kube-system -l name=nvidia-device-plugin

# If GPUs show 0 capacity: Restart kubelet on that node
ssh <node> "sudo systemctl restart kubelet"
```

**Issue: Too many zombie pods (ContainerStatusUnknown)**
```bash
# Count unknown pods
kubectl get pods -A --field-selector=status.phase==Unknown

# Bulk delete failed pods
kubectl delete pods -A --field-selector=status.phase==Failed --force --grace-period=0
```

**Issue: Deployment creating hundreds of replicas**
```bash
# Check deployment replica count
kubectl get deployment <deployment-name> -n <namespace> -o jsonpath='{.spec.replicas}'

# Scale down immediately
kubectl scale deployment <deployment-name> -n <namespace> --replicas=0

# Check if using volcano-scheduler (switch to default-scheduler)
kubectl patch deployment <deployment-name> -n <namespace> \
  -p '{"spec":{"template":{"spec":{"schedulerName":"default-scheduler"}}}}'
```

**Issue: kubectl timeout or connection refused**
```bash
# Check API server status
ssh zephyr "sudo systemctl status kube-apiserver"

# Check etcd status (API server backend)
ssh zephyr "sudo systemctl status etcd"

# If both down: Restart in correct order
ssh zephyr "sudo systemctl restart kube-apiserver"  # Auto-recovers etcd dependency
```

### Prevention Measures

**1. Use Default Scheduler for Regular Workloads**
```yaml
spec:
  template:
    spec:
      schedulerName: default-scheduler  # NOT volcano-scheduler
```

**2. Set Explicit Resource Limits**
```yaml
resources:
  requests:
    cpu: "2"
    memory: "1Gi"
  limits:
    cpu: "4"      # Must comply with LimitRange
    memory: "3Gi"
```

**3. Prevent Replica Explosions**
```yaml
spec:
  replicas: 1                     # ALWAYS set explicit count
  revisionHistoryLimit: 3         # Limit old replica sets
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0                 # Don't create extra pods
      maxUnavailable: 1
```

**4. Run All GPU Workloads in Kubernetes**
- No external systemd GPU miners (bypasses K8s resource awareness)
- All GPU processes visible to nvidia-device-plugin
- Prevents "OutOfnvidia.com/gpu" even when GPUs appear free

**5. Apply Secrets Before Deployments**
```bash
# Always apply secrets first
kubectl apply -f kubernetes-manifests/n8n/
kubectl apply -f kubernetes-manifests/glitchtip/

# Then deploy workloads
kubectl apply -f kubernetes-manifests/ai-inference/
```

---

## REFERENCE DOCUMENTS

### Must-Read (First Time)
**@AGENTS.md** — Universal patterns for ALL AI agents
- Quick start commands
- Critical safety rules (mkOptionDefault)
- Multi-host deployment patterns
- Kubernetes workflows

**@STATUS.md** — Real-time cluster health
- Kubernetes control plane status (v1.35.0, 4 nodes)
- Service inventory and migration progress
- Known issues and recent changes
- Quick commands for cluster management

### Architecture & Decisions
**@DECISION_LOG.md** — Architectural decisions (19 decisions recorded)
- Control plane: Keepalived VIP vs HAProxy
- Storage: Garage evolution (3-way → 2-way → single-node)
- Networking: Caddy vs NGINX, CIDR migration
- Compute: GPU marketplace, centralized proxy

**@ROADMAP.md** — Kubernetes migration (9-week plan)
- Current status: Phase 4-7 complete (95% overall)
- 7 implementation phases
- GPU passthrough strategy
- Service migration patterns

### Incident Documentation
**docs/kubernetes/volcano-scheduler-incident-2026-03-22.md** — Complete incident report
- Root cause: Volcano PodGroup authorization + GPU resource management
- Impact: 2058 non-running pods, deployment failures cluster-wide
- Resolution: Switched to default-scheduler, killed external GPU processes
- Prevention: Scheduler selection guidelines, zombie pod prevention

### Services & Features
**docs/compute-market.md** — GPU Resource Marketplace
- Unified auction engine for GPU allocation
- Bidders: Mining, Kubernetes, Akash, Gaming
- Prometheus metrics and Grafana dashboard

**docs/akash-cloudflare-integration.md** — Akash provider automation
- 6 automation features (DNS, cache, metrics, health)
- Complete usage guide and security considerations
- Time savings: ~200 hours/year for 10 active tenants

**docs/CUDA_TROUBLESHOOTING.md** — CUDA setup and fixes
- CUDA enablement on NVIDIA hosts
- Common issues (cuda_compat, allowUnsupportedSystem)
- Multi-GPU configuration

### Agent Configuration
**.claude/agents/multi-host-validator.md** — Multi-host impact validation
- Checklist for editing `modules/` directory
- Prevents SSH breakage and multi-host incidents

**.claude/skills/add-service/SKILL.md** — Service addition workflow
- Step-by-step systemd service creation
- Module structure and best practices

**.claude/skills/nix-rebuild/SKILL.md** — Safe rebuild patterns
- Troubleshooting build failures
- Rollback procedures

### Documentation Index
**@DOCUMENTATION_INDEX.md** — Complete documentation catalog
- All documentation files organized by purpose
- Quick reference for operations, architecture, integration

---

## CLUSTER CONTEXT

### Hosts
| Host | IP | Role | GPUs |
|------|-----|------|------|
| **Zephyr** | 10.1.1.110 | Control plane, AI workstation, gaming | 2× NVIDIA (RTX 3090, 3060 Ti) |
| **Nexus** | 10.1.1.120 | Storage, GPU compute | 1× NVIDIA (RTX 3060 Ti) |
| **Forge** | 10.1.1.130 | Multi-GPU mining, AI | 2× NVIDIA (RTX 4060) + 2× AMD (RX 5700 XT) |
| **Sentry** | 10.1.1.140 | Monitoring, logging | 1× AMD (RX 5600 XT) |

**Total Resources**: 78 cores, 123GB RAM, 7 GPUs, 8.4TB storage

### Kubernetes Status
- **Version**: v1.35.0
- **Nodes**: 4/4 Ready (Zephyr, Nexus, Forge, Sentry)
- **Control Plane**: 3-node HA (Zephyr, Nexus, Sentry) with Keepalived VIP
- **Migration Progress**: 95% complete (Phases 1-7)
- **Key Services**: Caddy Ingress, GlitchTip, SearXNG, n8n, home-assistant

### Key Features
- **GPU Marketplace**: Dynamic GPU allocation (mining/K8s/Akash/gaming)
- **Gaming Detection**: GameMode + K8s integration with auto-mining pause
- **Akash Provider**: Cloudflare integration with 6 automation features
- **Monitoring**: Prometheus + Grafana with Caddy metrics
- **Storage**: NFS shared storage, local-path provisioner, Garage S3

---

## RELATED RESOURCES

### Quick Status
- **Cluster Health**: `just status` or `just cluster-status`
- **NFS Health**: `just check-nfs`
- **Git Status**: `just status` (shows untracked files on all nodes)

### Documentation
- **Full Catalog**: `@DOCUMENTATION_INDEX.md`
- **Hookify Rules**: `.claude/hookify-*.md` for deployment safety
- **Archive**: `docs/archive/` for historical documentation

### Skills Available
- **kubernetes-specialist** — Day-to-day K8s operations
- **kubernetes-architect** — Architecture patterns
- **akash** — Akash Network provider operations
- **add-service** — systemd service creation
- **nix-rebuild** — Safe rebuild patterns

---

**Version**: 5.1 | **Updated**: 2026-03-22
**Changes**:
- Added critical safety rules for Volcano scheduler (use default-scheduler for general workloads)
- Added control plane restart order (etcd is last resort)
- Added comprehensive Kubernetes troubleshooting section
- Added incident documentation reference for Volcano scheduler outage
- Documented zombie pod prevention and GPU resource management best practices
