# NixOS Cluster - Claude Code Context

## ⚠️ CRITICAL: THIS IS NIXOS

**This is NOT a typical Linux distribution.** This is **NixOS** - a purely declarative Linux distribution where the entire operating system configuration is defined in `/etc/nixos/` and rebuilt via `nixos-rebuild switch`.

### 🔴 MANDATORY: NixOS Configuration Rules

**✅ CORRECT (Declarative):**
- Edit `/etc/nixos/configuration.nix` or `/etc/nixos/modules/*.nix`
- Run `nixos-rebuild switch` to apply changes
- All system state defined in Nix expressions (reproducible, rollback-capable)

**❌ FORBIDDEN (Imperative):**
- **NEVER** install packages with `nix-env -iA package` (breaks declarative model)
- **NEVER** modify `/etc/nix` directly (it's the Nix store - immutable, managed by Nix)
- **NEVER** use `systemctl start/enable` for persistent services (use NixOS config instead)
- **NEVER** edit files in `/etc` outside of NixOS management (won't survive rebuilds)

**Consequences of Breaking These Rules:**
- System becomes unreproducible (declarative + imperative = chaos)
- Rollbacks break (imperative changes can't be rolled back)
- Configuration drift (hard to maintain, impossible to debug)
- Deployments fail (NixOS expects all state in configuration)

---

## WHAT
NixOS flake-based 4-host Linux cluster (Zephyr, Nexus, Forge, Sentry) for AI inference, GPU computing, storage, and monitoring.

**Tech stack**: NixOS flakes, Kubernetes v1.35.0, Colmena, Just, Serena tools

**Current Branch**: `feature/x86-64-v3-migration` (main: `main`)

---

## ⚠️ CRITICAL SAFETY RULES

### NixOS Declarative Model (MANDATORY)

**ALL system changes MUST go through NixOS configuration:**

| Action | ✅ CORRECT (NixOS) | ❌ WRONG (Imperative) |
|--------|-------------------|---------------------|
| Install packages | Edit `environment.systemPackages` in config.nix | `nix-env -iA package` |
| Enable services | Edit `services.<name>.enable = true` in config.nix | `systemctl enable <service>` |
| Start services | `nixos-rebuild switch` (starts enabled services) | `systemctl start <service>` |
| Create users | Edit `users.users.<name>` in config.nix | `useradd <name>` |
| Configure system | Edit `/etc/nixos/modules/*.nix` | Edit `/etc/<files>` directly |
| Apply changes | `nixos-rebuild switch` or `just deploy` | Direct system modifications |

**Why This Matters:**
- **Reproducibility:** Same config → same system every time
- **Rollback:** Every rebuild creates a new generation (can boot into any previous one)
- **Documentation:** Config is self-documenting (all state in one place)
- **Safety:** `nixos-rebuild test` applies changes temporarily (can revert on reboot)

### Emergency Overrides (RARE)

**Only use these if NixOS config is broken and you need SSH access:**
```bash
# TEMPORARY service start (won't survive reboot)
systemctl start sshd

# ONE-OFF commands (no persistent state)
systemctl daemon-reload
systemctl restart kube-apiserver  # Restart control plane (temporary)
```

**After emergency fix:** IMMEDIATELY update NixOS config to match running state.

### NixOS Store (/nix vs /etc/nixos)

**CRITICAL DISTINCTION:**

| Path | Purpose | Mutable? | Managed By |
|------|---------|----------|-----------|
| `/etc/nixos/` | **NixOS configuration** (source code) | ✅ Yes | You (edit files) |
| `/nix` or `/etc/nix` | **Nix store** (built packages) | ❌ No | Nix (immutable) |
| `/etc/nixos/` | **Your system config** | ✅ Yes | Declarative |
| `/nix/var/nix/profiles/system-*` | **System generations** | ❌ No | NixOS (read-only) |

**Key Points:**
- `/etc/nixos/` = Source code (like `/usr/src/linux`)
- `/nix` = Binary store (like `/usr/bin` but immutable)
- **NEVER** edit `/nix` directly (it's rebuilt from `/etc/nixos/`)
- **ALWAYS** edit `/etc/nixos/` then run `nixos-rebuild switch`

**Example:**
```bash
# ✅ CORRECT: Edit source, rebuild system
vim /etc/nixos/modules/services/my-service.nix
nixos-rebuild switch  # Builds new generation, activates it

# ❌ WRONG: Try to edit Nix store
vim /nix/store/...-my-service-.../bin/my-service  # Can't save (read-only filesystem)
```

### NixOS Generations and Rollback

**Every `nixos-rebuild switch` creates a new generation:**

```bash
# View all generations
nixos-rebuild list-generations

# Sample output:
# Generation 150 (Mar 25 10:00) → Current
# Generation 149 (Mar 24 15:30) → Previous
# Generation 148 (Mar 23 09:00) → Older

# Rollback to previous generation
nixos-rebuild rollback

# Rollback to specific generation
nixos-rebuild switch --profile /nix/var/nix/profiles/system-150-link

# Delete old generations (cleanup)
nix-collect-garbage -d
```

**Boot Menu:**
- GRUB2 shows all generations (can boot into any previous one)
- Useful for disaster recovery (if config breaks system)

---

## NixOS-Specific Conventions

### Declarative System Configuration

**ALL system state must be defined in NixOS modules:**

```nix
# ✅ CORRECT: Define service in NixOS module
{ config, pkgs, ... }: {
  services.my-service = {
    enable = true;
    settings.port = 8080;
  };
  systemd.services.my-service = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStart = "${pkgs.my-package}/bin/my-service";
  };
}
```

**Then rebuild the system:**
```bash
nixos-rebuild switch  # Builds new generation, activates it, updates boot menu
```

**❌ WRONG: Imperative service management**
```bash
# DO NOT DO THIS - Changes won't survive reboot
systemctl start my-service
systemctl enable my-service
# ❌ Breaks declarative model, can't be rolled back
```

### Package Management

**✅ CORRECT: Declare packages in configuration**
```nix
# hosts/zephyr/configuration.nix
{ config, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
  ];
}
```

**❌ WRONG: Imperative package installation**
```bash
# DO NOT DO THIS - Breaks reproducibility
nix-env -iA nixos.vim
nix-channel --update && nix-env -iA nixos.git
# ❌ Package only installed for current user, not declarative
```

### Configuration Files

**✅ CORRECT: Generate config files in NixOS**
```nix
{ config, pkgs, ... }: {
  environment.etc."my-service/config.yaml".text = ''
    port: 8080
    debug: false
  '';
}
```

**❌ WRONG: Manually edit config files**
```bash
# DO NOT DO THIS - Changes will be overwritten on next rebuild
vim /etc/my-service/config.yaml
# ❌ File regenerated from NixOS config on every rebuild
```

### User Management

**✅ CORRECT: Define users in NixOS**
```nix
{ config, pkgs, ... }: {
  users.users.myuser = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
  };
}
```

**❌ WRONG: Imperative user creation**
```bash
# DO NOT DO THIS - User won't survive rebuild
useradd myuser
# ❌ Users are managed declaratively in NixOS
```

---

## CONVENTIONS

### mkOptionDefault (MANDATORY for extensible options)

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

**⚠️ CRITICAL:** All system configuration MUST be in `/etc/nixos/`. The entire OS is rebuilt from these files.

```
/etc/nixos/
├── flake.nix              # Main flake (defines packages, devshells, NixOS configs)
├── colmena.nix            # Multi-host deployment (NFS-based, no git push needed)
├── justfile               # CI/CD commands (no sync needed - NFS mount)
├── hosts/                 # Per-host configs (zephyr, nexus, forge, sentry)
│   └── <hostname>/configuration.nix  # NixOS config for each host
├── modules/               # Reusable modules (auto-imported via default.nix)
│   ├── profiles/          # Hardware, role, network profiles
│   ├── system/            # System-level modules (systemd, networking, etc.)
│   ├── services/          # Background services (K8s, monitoring, etc.)
│   └── compute-market/    # GPU resource marketplace
├── kubernetes-manifests/  # K8s manifests for migrated services
├── docs/                  # Comprehensive documentation
├── AGENTS.md              # Universal patterns for ALL agents
├── STATUS.md              # Real-time cluster health
└── .claude/               # Claude-specific files (agents, skills, settings)
```

**🔴 FORBIDDEN PATHS (Never Edit):**
- `/etc/nix` - Nix store (immutable, managed by Nix, contains all packages)
- `/nix` - Alternative Nix store path (same as above)
- Any imperative package installation locations

**✅ CORRECT WORKFLOW:**
1. Edit `/etc/nixos/modules/` or `/etc/nixos/hosts/<hostname>/configuration.nix`
2. Test: `nixos-rebuild test` (applies to current host, can rollback)
3. Commit: `git add` && `git commit`
4. Deploy: `just deploy` (applies to all hosts via Colmena)
```

**Architecture**: All remote hosts mount `/run/nixos-shared` (NFS from Zephyr) - no config sync needed

---

## NixOS-SPECIFIC CONVENTIONS

### Declarative System Configuration

**ALL system state must be defined in NixOS modules:**

```nix
# ✅ CORRECT: Define service in NixOS module
{ config, pkgs, ... }: {
  services.my-service = {
    enable = true;
    settings.port = 8080;
  };
  systemd.services.my-service = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStart = "${pkgs.my-package}/bin/my-service";
  };
}
```

**Then rebuild the system:**
```bash
nixos-rebuild switch  # Builds new generation, activates it, updates boot menu
```

**❌ WRONG: Imperative service management**
```bash
# DO NOT DO THIS - Changes won't survive reboot
systemctl start my-service
systemctl enable my-service
# ❌ Breaks declarative model, can't be rolled back
```

### Package Management

**✅ CORRECT: Declare packages in configuration**
```nix
# hosts/zephyr/configuration.nix
{ config, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
  ];
}
```

**❌ WRONG: Imperative package installation**
```bash
# DO NOT DO THIS - Breaks reproducibility
nix-env -iA nixos.vim
nix-channel --update && nix-env -iA nixos.git
# ❌ Package only installed for current user, not declarative
```

### Configuration Files

**✅ CORRECT: Generate config files in NixOS**
```nix
{ config, pkgs, ... }: {
  environment.etc."my-service/config.yaml".text = ''
    port: 8080
    debug: false
  '';
}
```

**❌ WRONG: Manually edit config files**
```bash
# DO NOT DO THIS - Changes will be overwritten on next rebuild
vim /etc/my-service/config.yaml
# ❌ File regenerated from NixOS config on every rebuild
```

### User Management

**✅ CORRECT: Define users in NixOS**
```nix
{ config, pkgs, ... }: {
  users.users.myuser = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
  };
}
```

**❌ WRONG: Imperative user creation**
```bash
# DO NOT DO THIS - User won't survive rebuild
useradd myuser
# ❌ Users are managed declaratively in NixOS
```

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

### Kubernetes Naming Conventions (MANDATORY)

**✅ CORRECT: Use DNS names for service discovery**
```yaml
# Kubernetes internal services
service-name.namespace.svc.cluster.local  # Full FQDN
service-name.namespace.svc.cluster        # Short form
service-name                               # Same namespace only

# External services (via Ingress or ExternalName)
search.reverb256.ca                        # Caddy Ingress
ai-inference-gateway.ai-inference.svc.cluster.local
```

**❌ WRONG: Hardcoded IP addresses**
```yaml
# DO NOT DO THIS - Breaks when IPs change
http://10.0.0.192:8080                      # ClusterIP (not accessible from host)
http://10.1.1.100:30880                      # VIP (should use DNS instead)
```

**Why This Matters:**
- **Maintainability:** IPs change on redeployment, DNS names are stable
- **Portability:** Configs work across environments (dev/staging/prod)
- **Self-Documenting:** DNS names describe the service (e.g., `ai-inference-gateway`)
- **Service Discovery:** Kubernetes DNS automatically tracks service endpoints
- **HA Support:** DNS can resolve to multiple endpoints (VIP, round-robin)

**Examples:**
```nix
# ✅ CORRECT: Use service DNS in NixOS configs
services.my-service = {
  settings.apiUrl = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080";
};

# ❌ WRONG: Hardcoded ClusterIP
services.my-service = {
  settings.apiUrl = "http://10.0.0.192:8080";  # Breaks on service restart
};
```

**Kubernetes DNS Patterns:**
| Pattern | Resolves To | Example |
|---------|-------------|---------|
| `<service>` | Same namespace | `ai-inference-gateway` |
| `<service>.<namespace>` | Cross-namespace | `ai-inference-gateway.ai-inference` |
| `<service>.<namespace>.svc.cluster.local` | Fully qualified | `ai-inference-gateway.ai-inference.svc.cluster.local` |
| `<pod-ip>.<namespace>.pod.cluster.local` | Direct pod access | `10-244-98-6.ai-inference.pod.cluster.local` |

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

### Testing Checklist (NixOS-Specific)
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
- Bidders: Mining, Kubernetes, Gaming
- Prometheus metrics and Grafana dashboard
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

## SUPPLY CHAIN SECURITY

All software on this cluster has supply chain protections enforcing a 7-day cooling period on newly published packages and images.

### Package Manager Cooldowns (7-day age gate)

| Ecosystem | Config | Module |
|-----------|--------|--------|
| **npm** | `~/.npmrc` → `min-release-age=7` | `services.supply-chain-cooldowns` |
| **pnpm** | Same `~/.npmrc` (respects npm config) | `services.supply-chain-cooldowns` |
| **bun** | `~/.bunfig.toml` → `minimumReleaseAge = "7d"` | `services.supply-chain-cooldowns` |
| **uv (Python)** | `~/.config/uv/uv.toml` → `exclude-newer = "7 days"` | `services.supply-chain-cooldowns` |

**Module**: `modules/services/supply-chain-cooldowns.nix` — enable with `services.supply-chain-cooldowns.enable = true`

### Container Image Security

- **Image policy** (`/etc/containers/policy.json`): Rejects unsigned images by default; allows docker.io/library, ghcr.io, quay.io, localhost
- **No `:latest` tags**: All NixOS-managed container images pinned to specific versions (vaultwarden `1.35.4`, glitchtip `:6`, postgres `:16-alpine`, redis `:7-alpine`)
- **Trivy scanning**: Weekly vulnerability scan of all pulled images (`services.container-scanning.enable = true`)
- **K8s admission policy**: `kubernetes-manifests/security/deny-latest-tag.yaml` blocks `:latest` tags cluster-wide

### Flake Input Age Validation

`modules/services/auto-update.nix` validates that nixpkgs inputs are older than 7 days before auto-updating, preventing unreviewed changes from reaching the cluster.

### GitHub Actions Pinned to Commit SHAs

All CI workflows (`.github/workflows/`) pin actions to immutable commit SHAs instead of mutable version tags (prevents tag-hijacking attacks like the Trivy incident).

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
- **GPU Marketplace**: Dynamic GPU allocation (mining/K8s/gaming)
- **Gaming Detection**: GameMode + K8s integration with auto-mining pause
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
- **add-service** — systemd service creation
- **nix-rebuild** — Safe rebuild patterns

---

**Version**: 5.2 | **Updated**: 2026-04-01
**Changes**:
- Added supply chain security section (7-day cooldowns, image policy, Trivy, K8s admission policy, SHA pinning)
- Container image policy: reject unsigned, allow specific registries
- Pinned all container images to specific versions (no `:latest`)
- Added `supply-chain-cooldowns` module for npm/bun/uv age gating
- Activated Trivy container scanning with weekly timer
- Added K8s `deny-latest-tag` ValidatingAdmissionPolicy
- Pinned all GitHub Actions to immutable commit SHAs
