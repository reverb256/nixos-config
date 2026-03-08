# NixOS Configuration - Agent Guidelines

## Purpose

This document provides guidelines for AI agents (OpenCode, Cursor, Copilot, etc.) working on this NixOS configuration. It focuses on workflows, testing strategies, and common patterns.

**For Claude Code-specific patterns**, see `CLAUDE.md`.

---

## Project Overview
This is a NixOS flake-based system configuration managing a 4-host Linux cluster. All system configurations are declarative and managed through Nix modules with a profile-based architecture for composable, reusable configurations.

---

## Build & Test Commands

### ⭐ Primary Workflow: Just Commands
```bash
# ALWAYS use justfile commands for CI/CD integration
just test              # Verify configuration (flake check + build all hosts)
just switch            # Apply to local host (auto-pauses mining)
just deploy            # Deploy to all cluster hosts
just ci-local          # Run full CI pipeline locally
```

### Legacy Commands (Avoid when possible)
```bash
# Fast syntax check (5 seconds) - still useful
nix flake check

# Build without applying (1-2 minutes) - for debugging
sudo nixos-rebuild build --flake .#zephyr

# Test configuration (rollback safe) - for testing
sudo nixos-rebuild test --flake .#zephyr

# ⚠️ Use "just switch" instead (auto-pauses mining)
sudo nixos-rebuild switch --flake .#zephyr

# Update all flake inputs
nix flake update
```

### Fish Aliases (auto-pause mining)
```bash
nswitch      # nixos-rebuild switch
nswitchu     # switch with --upgrade
ntest        # nixos-rebuild test
nbuild       # nixos-rebuild build
ndry         # nixos-rebuild dry-activate
```

### Justfile Recipes
```bash
just switch          # Local switch (auto-pauses mining)
just test            # Test configuration (flake check + colmena build)
just deploy          # Deploy to all hosts
just zephyr          # Deploy to zephyr only
just nexus           # Deploy to nexus only
just forge           # Deploy to forge only
just sentry          # Deploy to sentry only
just sync            # Sync all nodes to current branch
just status          # Show cluster status and git commits
```

### Cluster Storage Verification
```bash
# Verify all storage is mounted before deploying
/data/@projects/infra/nixos/verify-cluster-storage.sh

# Check specific node
ssh nexus "df -h | grep -E '(worn|home|shared|backups|media|containers)'"
```

**Critical Storage Mounts**:
- **Zephyr**: 1.85TB SSD (931GB + 922GB partitions)
- **Nexus**: 4.7TB total (915GB + 3.6TB bcache0 + 224GB)
  - `/data/worn`, `/data/home`, `/data/shared`, `/data/backups`, `/data/media`
  - `/var/lib/containers` (Podman storage)
- **Forge**: 446GB SSD
- **Sentry**: 1.23TB (230GB SSD + 1TB HDD)

### Safe Rebuild Script
```bash
# Auto-pauses mining, runs rebuild, restarts mining
sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake .#zephyr
```

### Testing Strategy
1. Always run `nix flake check` first for syntax validation
2. Use `nixos-rebuild build` to verify configuration compiles
3. Use `nixos-rebuild test` for temporary changes (rollback safe)
4. Only use `switch` for verified, production-ready changes

---

## Code Style Guidelines

### Nix Language Conventions
- **2 spaces** for indentation (no tabs)
- Blank lines between major sections
- Comments use `#` prefix, place above setting not inline
- Use trailing commas for multi-line attribute sets

### Attribute Sets & Lists
```nix
{ config, pkgs, inputs, ... }:  # Use ellipsis pattern
{
  description = "NixOS configuration";
  inputs = { inherit nixpkgs home-manager; };  # Use inherit
};
```

### Lists
```nix
environment.systemPackages = with pkgs; [
  tmux
  mosh
  tailscale
  inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
];
```

---

## Project Structure

### Flake Outputs
```
outputs:
├── nixosConfigurations  # For local nixos-rebuild
├── colmena              # Raw hive configuration
├── colmenaHive          # Wrapped hive for multi-host deployment
├── packages             # Custom packages (claude)
├── overlays             # Package overlays
└── apps                 # Colmena app
```

### Directory Structure
```
/etc/nixos/
├── flake.nix                    # Main flake definition
├── flake.lock                   # Auto-generated, DO NOT EDIT
├── justfile                     # Just commands
├── hosts/
│   ├── zephyr/
│   │   ├── configuration.nix    # Host-specific config (profiles)
│   │   └── hardware-configuration.nix
│   ├── nexus/
│   ├── forge/
│   └── sentry/
├── lib/
│   ├── attrs.nix                # Attribute utilities
│   └── modules.nix              # Module discovery helpers
├── modules/
│   ├── default.nix              # Module aggregator
│   ├── profiles/                # Profile system
│   │   ├── hardware/            # Hardware profiles (CPU/GPU)
│   │   ├── role/                # Role profiles (gaming, mining, AI)
│   │   └── network/             # Network profiles (tailscale)
│   ├── common-host.nix          # Shared host imports
│   ├── desktop/                 # Desktop modules
│   ├── gaming/                  # Gaming modules
│   ├── hardware/                # Hardware-specific configs
│   ├── mining/                  # Mining modules
│   ├── services/                # Service modules
│   └── shell/                   # Shell configuration
├── scripts/
│   └── nixos-rebuild-safe.sh    # Rebuild with mining pause
└── secrets/
    └── *.age                    # Agenix encrypted secrets
```

### Files
- **flake.nix**: Inputs and outputs (EDIT THIS)
- **configuration.nix**: Legacy main config (use host-specific configs)
- **hardware-configuration.nix**: Auto-generated per host (DO NOT EDIT)
- **flake.lock**: Reproducibility lockfile (AUTO-GENERATED, DO NOT EDIT)

---

## Profile System

Hosts use a declarative profile system for composable configuration:

### Hardware Profiles
| Profile | Description |
|---------|-------------|
| `amd.enable` | AMD CPU IOMMU |
| `amd.zen` | Zen CPU optimizations |
| `intel.enable` | Intel CPU optimizations |
| `nvidia.enable` | NVIDIA GPU support |
| `nvidia.multiGpu` | Multi-GPU CUDA settings |
| `amdgpu.enable` | AMD GPU support |
| `amdgpu.wayland` | ROC_ENABLE_PRE_VEGA |
| `monitoring.enable` | lm-sensors |

### Role Profiles
| Profile | Description |
|---------|-------------|
| `workstation` | Desktop + development |
| `gaming` | Steam, Lutris |
| `vr` | WiVRn, SteamVR |
| `mining` | GPU/CPU mining |
| `aiInference` | AI gateway + MCP |
| `desktop` | Plasma, Wayland |

### Network Profiles
| Profile | Description |
|---------|-------------|
| `tailscale.enable` | Enable Tailscale VPN |
| `tailscale.advertiseRoutes` | Routes to advertise |

### Host Definitions
```nix
# Example: hosts/zephyr/configuration.nix
{ lib, pkgs, ... }: {
  imports = [
    ../../modules/default.nix
    ../../modules/common-host.nix
  ];

  # Hardware profiles
  hardware.profiles = {
    amd.zen = true;
    nvidia.enable = true;
    nvidia.multiGpu = true;
    corsair.enable = true;
    monitoring.enable = true;
  };

  # Role profiles
  profiles.role = {
    workstation = true;
    gaming = true;
    vr = true;
    mining = true;
    aiInference = true;
  };

  # Network profiles
  profiles.network.tailscale.enable = true;
};
```

---

## Hosts

| Host | Hardware | Roles |
|------|----------|-------|
| **zephyr** | AMD 5950X (32 cores), 31GB RAM, NVIDIA (RTX 3090 + 3060 Ti), 1.85TB SSD | workstation, gaming, VR, mining, AI, Kubernetes control plane |
| **nexus** | AMD Zen (24 cores), 46GB RAM, NVIDIA (1x RTX 3060 Ti), 4.7TB storage (915GB + 3.6TB bcache0 + 224GB) | storage, mining, AI, Kubernetes worker |
| **forge** | Intel Skylake (6 cores), 15GB RAM, NVIDIA (2x RTX 4060) + AMD (2x RX 5700 XT), 446GB SSD | multi-GPU mining, AI, Kubernetes GPU worker |
| **sentry** | AMD Zen (16 cores), 31GB RAM, AMD RX 5600 XT, 1.23TB (230GB SSD + 1TB HDD) | mining, AI, monitoring, Kubernetes worker |

**See Also**: `/etc/nixos/ROADMAP.md` for complete Kubernetes migration plan

---

## Naming Conventions
- Hostnames: lowercase (e.g., `zephyr`)
- Usernames: underscores for spaces (e.g., `j_kro`)
- Flake inputs: lowercase with hyphens (e.g., `zen-browser`)
- Service names: match systemd services (e.g., `tailscale`, `networkmanager`)
- Profiles: camelCase for nested (e.g., `amd.zen`, `profiles.role`)

---

## Formatting
```bash
# Format all .nix files
nix-shell -p nixpkgs-fmt --run "nixpkgs-fmt **/*.nix"

# Format specific files
nixpkgs-fmt flake.nix configuration.nix
```

---

## Common Patterns
```nix
# Enable services
services.xserver.enable = true;
services.desktopManager.plasma6.enable = true;

# System packages
environment.systemPackages = with pkgs; [ package1 package2 ];

# User config
users.users.j_kro = {
  isNormalUser = true;
  description = "Jeremy Kroeker";
  shell = pkgs.fish;
  extraGroups = [ "networkmanager" "wheel" ];
};

# Home Manager
home-manager.users.j_kro = { pkgs, lib, ... }: {
  home.stateVersion = "26.05";
};
```

---

## Important Notes
- Keep `system.stateVersion` and `home.stateVersion` current
- Never edit `hardware-configuration.nix` - regenerate with `nixos-generate-config`
- Never edit `flake.lock` - regenerate with `nix flake update`
- Run `nix flake update` before making changes
- Check `nix flake show` for available configurations
- Build/test/switch require root/sudo
- All new Python files MUST be added to git before rebuilding (Nix only packages git-tracked files)
- **Always use `just` commands instead of direct `nixos-rebuild`** for CI/CD integration
- **Always run `just test` before `just deploy`** to catch configuration errors early
- **Always run `just sync` before `just deploy`** to ensure all nodes have the same configuration
- **Never suppress build errors** (no `2>&1 >/dev/null` or `|| true`) - errors must be investigated
- **Check storage mounts after deployment** - all cluster storage must be available
- **Hookify rules will warn about dangerous patterns** - see `.claude/hookify-*.md` files

### Cluster Storage Module
The `modules/system/cluster-storage.nix` module ensures all configured storage mounts are active on boot across all cluster nodes. This prevents issues like the Nexus 3.8TB bcache0 not being mounted.

**What it does**:
- Runs on boot after filesystems are mounted
- Checks node-specific critical mounts (e.g., `/data/*` on Nexus)
- Attempts to mount any missing filesystems
- Logs status of all cluster storage mounts

**Verify after deployment**:
```bash
# Check systemd service status
systemctl status ensure-cluster-storage

# View service logs
journalctl -u ensure-cluster-storage -n 50

# Manual verification script
/data/@projects/infra/nixos/verify-cluster-storage.sh
```

---

## Multi-Host Deployment (Colmena)

### Colmena Commands
```bash
# Build all hosts (dry run)
nix run .#apps.x86_64-linux.colmena -- build

# Apply to specific host
nix run .#apps.x86_64-linux.colmena -- apply --on zephyr

# Apply to remote hosts (use 'boot' goal to avoid inhibitors)
nix run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry boot

# Deploy to all hosts
just deploy
```

### Remote Deployment Notes
- Remote hosts use `boot` goal to avoid switch inhibitors (e.g., dbus changes)
- Local host (zephyr) uses `switch` goal
- Mining auto-pauses on all hosts during deployment

---

## Kubernetes Migration

### Overview
The cluster is migrating from NixOS systemd services to Kubernetes using `services.kubernetes` (full upstream Kubernetes, not K3s). See `/etc/nixos/ROADMAP.md` for the complete 9-week migration plan.

### Migration Strategy
- **Phase 1 (Week 1-2)**: Bootstrap single-node cluster on Zephyr
- **Phase 2 (Week 2-3)**: Add worker nodes (Nexus, Forge, Sentry)
- **Phase 3-4 (Week 3-4)**: Migrate stateful services (PostgreSQL, Redis)
- **Phase 5-6 (Week 4-6)**: Migrate stateless services
- **Phase 6-7 (Week 6-7)**: GPU workloads with device plugins
- **Phase 7-8 (Week 7-8)**: Monitoring and observability
- **Phase 8-9 (Week 8-9)**: Cleanup and optimization

### Kubernetes Architecture

**Control Plane (Zephyr)**:
- API server, scheduler, controller manager
- etcd (single-node initially, consider HA later)
- Flannel CNI (VXLAN backend)
- CoreDNS for cluster DNS

**Worker Nodes**:
- **Nexus**: Storage workloads, large local storage
- **Forge**: GPU workloads (NVIDIA + AMD mixed vendor)
- **Sentry**: Monitoring, logging, observability

**Storage**:
- Longhorn for distributed block storage
- NFS for shared filesystem (nexus:/data/shared)
- Local storage for databases

**Networking**:
- Tailscale VPN for cluster interconnect
- Flannel VXLAN for pod networking
- Caddy-based ingress for external access

### GPU Passthrough Strategy

**NVIDIA Nodes (Zephyr, Nexus)**:
```nix
# NVIDIA device plugin DaemonSet
services.kubernetes.podNets = [ "10.244.0.0/16" ];
virtualisation.docker.enable = true;
hardware.graphics.nvidia.enable = true;
```

**AMD Nodes (Forge, Sentry)**:
```nix
# AMD GPU device plugin (different plugin!)
services.kubernetes.kubelet.extraOpts = "--feature-gates=KubeletPodResources=false";
hardware.graphics.amdgpu.enable = true;
```

**Mixed Vendor Challenge (Forge)**:
- Deploy both NVIDIA and AMD device plugins
- Use node selector: `accelerator: nvidia` or `accelerator: amd`
- Separate resource requests: `nvidia.com/gpu` vs `amd.com/gpu`

### Kubernetes Commands

**Cluster Management**:
```bash
# Check cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# View service endpoints
kubectl get endpoints
kubectl describe service <service-name>

# Debug pod issues
kubectl logs <pod-name> -n <namespace>
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Check resource usage
kubectl top nodes
kubectl top pods -n <namespace>
```

**Deployment**:
```bash
# Apply manifests
kubectl apply -f manifests/

# Rollout restart
kubectl rollout restart deployment/<name> -n <namespace>

# Check rollout status
kubectl rollout status deployment/<name> -n <namespace>
```

**Storage**:
```bash
# List PVs/PVCs
kubectl get pv,pvc -n <namespace>

# Check storage classes
kubectl get storageclass

# Describe volume
kubectl describe pvc <pvc-name> -n <namespace>
```

### Migration Workflow for Services

**1. Create Kubernetes Manifest**:
```yaml
# manifests/<service-name>.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-service
  template:
    metadata:
      labels:
        app: my-service
    spec:
      containers:
      - name: my-service
        image: registry.example.com/my-service:latest
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

**2. Test in Development Namespace**:
```bash
kubectl apply -f manifests/my-service.yaml -n development
kubectl port-forward -n development svc/my-service 8080:80
```

**3. Migrate Data (if stateful)**:
```bash
# Export data from systemd service
systemctl stop my-service
pg_dump mydb > backup.sql

# Import into Kubernetes pod
kubectl cp backup.sql my-pod:/tmp/backup.sql -n production
kubectl exec my-pod -n production -- psql mydb < /tmp/backup.sql
```

**4. Switch Traffic**:
```bash
# Update ingress to point to Kubernetes service
kubectl apply -f manifests/ingress.yaml

# Verify traffic flowing
kubectl logs -f deployment/my-service -n production

# Disable systemd service
systemctl disable --now my-service
```

**5. Monitor and Rollback**:
```bash
# If issues occur, rollback immediately
kubectl rollout undo deployment/my-service -n production
systemctl enable --now my-service
```

### NixOS Kubernetes Configuration

**Enable Kubernetes**:
```nix
# hosts/zephyr/configuration.nix
services.kubernetes = {
  enable = true;
  roles = ["master" "node"];
  masterAddress = "zephyr";
  apiserverAddress = "https://10.0.0.10:6443";
  easyCerts = true;
  dnsDomain = "cluster.local";
  podNets = ["10.244.0.0/16"];
  serviceNets = ["10.96.0.0/12"];
};
```

**Enable Docker (required for Kubernetes)**:
```nix
virtualisation.docker = {
  enable = true;
  autoPrune = {
    enable = true;
    dates = "weekly";
  };
};
```

**Firewall Rules**:
```nix
networking.firewall.allowedTCPPorts = [
  6443  # Kubernetes API server
  2379  # etcd client
  2380  # etcd peer
  10250 # Kubelet API
  10251 # Kube-scheduler
  10252 # Kube-controller-manager
];

networking.firewall.allowedUDPPorts = [
  8472  # Flannel VXLAN
];
```

### Common Patterns

**Node Selector for GPU Workloads**:
```yaml
spec:
  nodeSelector:
    gpu: "nvidia"  # or "amd"
  containers:
  - resources:
      requests:
        nvidia.com/gpu: 1  # or amd.com/gpu: 1
```

**Tolerations for System Pods**:
```yaml
spec:
  tolerations:
  - key: "node-role.kubernetes.io/master"
    operator: "Exists"
    effect: "NoSchedule"
```

**ConfigMaps and Secrets**:
```bash
# Create ConfigMap from file
kubectl create configmap my-config --from-file=config.yaml -n production

# Create Secret from literal
kubectl create secret generic my-secret --from-literal=password=secret123 -n production
```

### Troubleshooting

**Pod Not Starting**:
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
```

**Service Not Reachable**:
```bash
kubectl get endpoints <service-name> -n <namespace>
kubectl describe svc <service-name> -n <namespace>
```

**Storage Issues**:
```bash
kubectl describe pvc <pvc-name> -n <namespace>
kubectl get pv
```

**Network Policies Blocking Traffic**:
```bash
kubectl get networkpolicies -n <namespace>
kubectl describe networkpolicy <policy-name> -n <namespace>
```

### Documentation Links
- **Full Migration Plan**: `/etc/nixos/ROADMAP.md`
- **Kubernetes Docs**: https://kubernetes.io/docs/
- **NixOS Kubernetes Module**: https://search.nixos.org/options?query=services.kubernetes

---

## MCP (Model Context Protocol) Integration

### Overview
The AI inference gateway includes an MCP broker that aggregates tools from multiple MCP servers, enabling AI agents to call external tools through the gateway.

### MCP Server Configuration
MCP servers are configured in `.mcp.json`:

```json
{
  "mcpServers": {
    "web-search-prime": {
      "url": "https://api.z.ai/api/mcp/web_search_prime/mcp",
      "headers": {
        "Authorization": "Bearer /run/agenix/zai-api-key"
      }
    }
  }
}
```

### Key Implementation Insights

**1. MCP Protocol Structure**
- Uses JSON-RPC 2.0 format over HTTP/SSE
- Methods: `initialize`, `tools/list`, `tools/call`
- Responses come in Server-Sent Events (SSE) format
- Requires specific `Accept` header: `application/json, text/event-stream`

**2. Authentication Pattern**
```python
# Headers with file paths need special handling
"Authorization": "Bearer /run/agenix/zai-api-key"

# Python code to load actual key:
if header_value.startswith("Bearer "):
    file_path = header_value.split(" ", 1)[1].strip()
    with open(file_path, "r") as f:
        api_key = f.read().strip()
        headers[header_name] = f"Bearer {api_key}"
```

**3. SSE Response Parsing**
```python
# ZAI MCP servers return SSE format:
# id:1
# event:message
# data:{"jsonrpc":"2.0","id":1,"result":{...}}

# Parse SSE:
async for line in response.aiter_lines():
    if line.startswith("data:"):
        data = json.loads(line[5:].strip())
        # Handle data["result"] or data["error"]
```

**4. Tool Name Discovery**
- Tool names are **case-sensitive** (e.g., `webSearchPrime` not `web_search`)
- Always fetch tool names via `tools/list` before calling
- Different servers may have different tool names for similar functionality

**5. Accept Header Requirements**
```python
headers = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream"  # Required by ZAI MCP servers
}
```

### MCP Endpoints
```
GET  /mcp/servers              # List configured MCP servers with health status
GET  /mcp/tools               # List available tools from all servers
POST /mcp/call                # Call an MCP tool
GET  /mcp/health/{server_name}  # Check MCP server health
```

### Testing MCP Integration

**Direct Server Test:**
```bash
curl -X POST "https://api.z.ai/api/mcp/web_search_prime/mcp" \
  -H "Authorization: Bearer YOUR_KEY" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list"
  }'
```

**Through Gateway:**
```bash
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "web-search-prime",
    "tool": "webSearchPrime",
    "arguments": {"search_query": "test"}
  }'
```

### Common Pitfalls

**❌ Wrong Tool Name**
```json
{"tool": "web_search"}  // 404 Not Found
```

**✅ Correct Tool Name**
```json
{"tool": "webSearchPrime"}  // Works!
```

**❌ Missing Accept Header**
```bash
# Returns: "Accept header must include both application/json and text/event-stream"
curl -H "Accept: application/json" ...
```

**✅ Correct Accept Header**
```bash
curl -H "Accept: application/json, text/event-stream" ...
```

**❌ Not Reading API Key File**
```python
headers = {"Authorization": "Bearer /run/agenix/zai-api-key"}  # Literal string
```

**✅ Reading API Key from File**
```python
# Extract file path and read contents
if "/run/" in header_value:
    with open(file_path, "r") as f:
        api_key = f.read().strip()
    headers = {"Authorization": f"Bearer {api_key}"}
```

### ZAI MCP Servers

| Server | URL | Tool Names | Purpose |
|--------|-----|------------|---------|
| web-search-prime | `/api/mcp/web_search_prime/mcp` | `webSearchPrime` | Web search |
| web-reader | `/api/mcp/web_reader/mcp` | `webReader` | URL content fetching |
| zread | `/api/mcp/zread/mcp` | `get_repo_structure`, `read_file` | GitHub analysis |
| 4-5v-mcp-server | `/api/mcp/4_5v/mcp` | `analyze_image` | Image analysis |

### Debugging Tips

**CRITICAL: Zero Tolerance Policy for Errors**

This project has a **zero tolerance policy for errors and bugs**. ANY error encountered during builds, deployments, or operation MUST be investigated and resolved, never ignored.

#### Core Debugging Workflow

1. **Never Ignore Errors**: When ANY error occurs (build warnings, service failures, journal errors):
   - Stop and investigate immediately
   - Use async subagents to debug while continuing primary work
   - Document root cause and resolution

2. **Async Subagent Debugging Pattern**:
   ```bash
   # Launch async agent for debugging
   Agent(tool="Agent", subagent_type="general-purpose", prompt="Investigate X error, find root cause, recommend fix", run_in_background=true)

   # Continue with other tasks while debugging happens
   # Agent notifies you when complete with findings
   ```

3. **During Builds/Deployments**:
   - Monitor build output for warnings/errors
   - Launch async agents to investigate ANY non-success result
   - Verify fixes before considering build "complete"

4. **Service Failures**:
   - Check `journalctl -xe` immediately
   - Review service status: `systemctl status <service>`
   - Use async agent to trace dependency chains
   - Verify fix didn't introduce new issues

5. **Boot Errors**:
   - Check `journalctl -b 0 --priority=err`
   - Look for dependency cycles, missing modules, filesystem errors
   - Use async agent to investigate boot process
   - Test on all nodes after fixes

#### MCP-Specific Debugging

1. **Test Directly First**: Always test MCP servers directly before testing through gateway
2. **Check Response Format**: Use `curl -v` to see actual response headers and format
3. **Enable Debug Logging**: Set `LOG_LEVEL=DEBUG` in environment for verbose logs
4. **Verify File Permissions**: Ensure service user can read agenix secret files
5. **Test JSON-RPC Methods**: Try `initialize` → `tools/list` → `tools/call` in order

---

## Service Management

```bash
# Check service status
systemctl status ai-inference-gateway

# View service logs
journalctl -u ai-inference-gateway -f

# Restart service
systemctl restart ai-inference-gateway

# Check if service is running
systemctl is-active ai-inference-gateway
```

---

## Gateway Testing

```bash
# Health check
curl http://127.0.0.1:8080/health | jq .

# List models
curl http://127.0.0.1:8080/v1/models | jq .

# Simple completion test
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen/qwen3.5-9b","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' | jq .

# MCP tools list
curl http://127.0.0.1:8080/mcp/tools | jq .
```
