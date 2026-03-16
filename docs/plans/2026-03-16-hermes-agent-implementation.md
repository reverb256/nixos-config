# Hermes Agent Multi-Node Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy Hermes Agent across all 4 NixOS cluster nodes with shared skills/memory via NFS, integrated with local AI Gateway for inference

**Architecture:** Full NixOS package using buildPythonApplication with Python 3.11, NFS-mounted shared storage for skills/memory, OpenAI-compatible API integration with existing AI Inference Gateway

**Tech Stack:** NixOS flakes, Python 3.11, buildPythonApplication, NFS (Garage), Hermes Agent (NousResearch)

---

## Pre-Implementation Tasks

### Task 1: Create Hermes module directory structure

**Files:**
- Create: `modules/services/hermes-agent/default.nix`
- Create: `modules/services/hermes-agent/package.nix`
- Create: `modules/services/hermes-agent/skills/.gitkeep`

**Step 1: Create module directory**

Run: `mkdir -p modules/services/hermes-agent/skills`
Expected: Directory created

**Step 2: Create placeholder files**

Run: `touch modules/services/hermes-agent/skills/.gitkeep`
Expected: File created

**Step 3: Commit**

```bash
git add modules/services/hermes-agent/
git commit -m "feat(hermes-agent): add module structure"
```

---

## Phase 1: Package Definition

### Task 2: Add Hermes agent to flake inputs

**Files:**
- Modify: `flake.nix`

**Step 1: Add Hermes repository to flake inputs**

Find the `inputs` section in `flake.nix` and add:

```nix
hermes-agent = {
  url = "github:NousResearch/hermes-agent/main";
  flake = false;
};
```

**Step 2: Pass Hermes input to modules**

Find the `hermesModules` call and add `hermes-agent`:

```nix
heritableInputs = inputs // {
  inherit (inputs) hermes-agent;
};
```

**Step 3: Verify flake is still valid**

Run: `nix flake check`
Expected: No errors

**Step 4: Commit**

```bash
git add flake.nix
git commit -m "feat(hermes-agent): add hermes-agent to flake inputs"
```

---

### Task 3: Create Python package definition

**Files:**
- Create: `modules/services/hermes-agent/package.nix`

**Step 1: Create package.nix with Hermes dependencies**

Write the following content to `modules/services/hermes-agent/package.nix`:

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.services.hermes-agent;
  python = pkgs.python311;
in
python.pkgs.buildPythonApplication rec {
  pname = "hermes-agent";
  version = "0.1.0-unstable";

  src = config.services.hermes-agent.packageSrc;

  # Enable submodules (mini-swe-agent, tinker-atropos)
  postUnpack = ''
    chmod -R u+w source
    cd source
    git submodule update --init --recursive || true
  '';

  propagatedBuildInputs = with python.pkgs; [
    openai
    python-dotenv
    fire
    httpx
    rich
    tenacity
    pyyaml
    requests
    jinja2
    pydantic
    prompt_toolkit
    firecrawl-py
    fal-client
    edge-tts
    litellm
    typer
    platformdirs
    PyJWT
  ];

  nativeBuildInputs = with pkgs; [
    git
    installShellFiles
  ];

  # Skip tests for now
  doCheck = false;

  meta = with lib; {
    description = "Self-improving AI agent by Nous Research";
    homepage = "https://hermes-agent.nousresearch.com/";
    license = licenses.mit;
  };
}
```

**Step 2: Commit**

```bash
git add modules/services/hermes-agent/package.nix
git commit -m "feat(hermes-agent): add Python package definition"
```

---

## Phase 2: Module Configuration

### Task 4: Create main module options

**Files:**
- Create: `modules/services/hermes-agent/default.nix`

**Step 1: Create default.nix with all options**

Write the following to `modules/services/hermes-agent/default.nix`:

```nix
{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.services.hermes-agent;
  hermesPackage = import ./package.nix { inherit pkgs lib config; };
in
{
  options.services.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent - self-improving AI agent";

    packageSrc = lib.mkOption {
      type = lib.types.path;
      default = inputs.hermes-agent;
      defaultText = "inputs.hermes-agent";
      description = "Hermes agent source";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = "User account for Hermes Agent";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = "Group for Hermes Agent";
    };

    sharedStorage = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable NFS shared storage for skills/memory";
      };

      mountPoint = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/hermes";
        description = "Mount point for shared Hermes data";
      };

      nfsServer = lib.mkOption {
        type = lib.types.str;
        example = "10.1.1.120";
        description = "NFS server address";
      };

      nfsPath = lib.mkOption {
        type = lib.types.str;
        example = "/mnt/garage/hermes";
        description = "NFS export path";
      };
    };

    aiGateway = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Connect to local AI Inference Gateway";
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:8080/v1";
        description = "AI Gateway URL (OpenAI-compatible)";
      };
    };

    terminal = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable terminal tool access";
      };

      requireApproval = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Require user approval for terminal commands";
      };

      allowedCommands = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = "Allow-list of commands (null = allow all)";
      };
    };

    customSkills = lib.mkOption {
      type = lib.types.path;
      default = ./skills;
      defaultText = "./skills";
      description = "Path to custom NixOS-specific skills";
    };
  };
}
```

**Step 2: Commit**

```bash
git add modules/services/hermes-agent/default.nix
git commit -m "feat(hermes-agent): add module options"
```

---

### Task 5: Implement module configuration

**Files:**
- Modify: `modules/services/hermes-agent/default.nix` (add config section)

**Step 1: Add config section to default.nix**

After the options section, add the config implementation:

```nix
  config = lib.mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = lib.mkIf (cfg.user == "hermes") {
      isNormalUser = true;
      createHome = true;
      home = cfg.sharedStorage.mountPoint;
      group = cfg.group;
      extraGroups = [ "wheel" "video" "render" ];
      shell = pkgs.fish;
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "hermes") {};

    # System packages
    environment.systemPackages = with pkgs; [
      hermesPackage
      ripgrep  # For file search
      ffmpeg   # For TTS
    ];

    # NFS mount for shared storage
    systemd.mounts = lib.mkIf cfg.sharedStorage.enable [{
      where = cfg.sharedStorage.mountPoint;
      what = "${cfg.sharedStorage.nfsServer}:${cfg.sharedStorage.nfsPath}";
      type = "nfs";
      options = "nofail,_netdev,hard,intr,timeo=600";
      wantedBy = [ "multi-user.target" ];
    }];

    # Environment variables
    environment.sessionVariables = lib.mkIf cfg.aiGateway.enable {
      HERMES_AI_GATEWAY_URL = cfg.aiGateway.url;
      OPENAI_API_KEY = "not-needed";
      OPENAI_BASE_URL = cfg.aiGateway.url;
    };
  };
}
```

**Step 2: Verify module builds**

Run: `nix eval .#modules.hermes-agent`
Expected: No errors

**Step 3: Commit**

```bash
git add modules/services/hermes-agent/default.nix
git commit -m "feat(hermes-agent): add module config implementation"
```

---

### Task 6: Add Hermes to modules/default.nix

**Files:**
- Modify: `modules/default.nix`

**Step 1: Import hermes-agent module**

Find the services section and add hermes-agent to the list:

```nix
services.ai-inference = import ./services/ai-inference;
services.hermes-agent = import ./services/hermes-agent;
```

**Step 2: Commit**

```bash
git add modules/default.nix
git commit -m "feat(hermes-agent): add to modules list"
```

---

## Phase 3: Host Configuration

### Task 7: Enable Hermes on Zephyr

**Files:**
- Modify: `hosts/zephyr/configuration.nix`

**Step 1: Add hermes-agent to Zephyr config**

Add to the imports or enable section:

```nix
services.hermes-agent = {
  enable = true;
  user = "j_kro";  # Use existing user
  sharedStorage = {
    enable = true;
    mountPoint = "/home/j_kro/.hermes";
    nfsServer = "10.1.1.120";  # Nexus
    nfsPath = "/mnt/garage/hermes";
  };
  aiGateway = {
    enable = true;
    url = "http://127.0.0.1:8080/v1";
  };
  terminal = {
    enable = true;
    requireApproval = false;
  };
};
```

**Step 2: Test build**

Run: `nix build .#nixosConfigurations.zephyr.config.system.build.toplevel`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "feat(hermes-agent): enable on zephyr"
```

---

### Task 8: Enable Hermes on other nodes

**Files:**
- Modify: `hosts/nexus/configuration.nix`
- Modify: `hosts/forge/configuration.nix`
- Modify: `hosts/sentry/configuration.nix`

**Step 1: Add to Nexus**

```nix
services.hermes-agent = {
  enable = true;
  user = "j_kro";
  sharedStorage = {
    enable = true;
    mountPoint = "/home/j_kro/.hermes";
    nfsServer = "10.1.1.120";  # Nexus itself
    nfsPath = "/mnt/garage/hermes";
  };
  aiGateway = {
    enable = true;
    url = "http://10.1.1.110:8080/v1";  # Zephyr AI Gateway
  };
  terminal = {
    enable = true;
    requireApproval = false;
  };
};
```

**Step 2: Add to Forge**

```nix
services.hermes-agent = {
  enable = true;
  user = "j_kro";
  sharedStorage = {
    enable = true;
    mountPoint = "/home/j_kro/.hermes";
    nfsServer = "10.1.1.120";
    nfsPath = "/mnt/garage/hermes";
  };
  aiGateway = {
    enable = true;
    url = "http://10.1.1.110:8080/v1";  # Zephyr AI Gateway
  };
  terminal = {
    enable = true;
    requireApproval = false;
  };
};
```

**Step 3: Add to Sentry**

```nix
services.hermes-agent = {
  enable = true;
  user = "j_kro";
  sharedStorage = {
    enable = true;
    mountPoint = "/home/j_kro/.hermes";
    nfsServer = "10.1.1.120";
    nfsPath = "/mnt/garage/hermes";
  };
  aiGateway = {
    enable = true;
    url = "http://10.1.1.110:8080/v1";  # Zephyr AI Gateway
  };
  terminal = {
    enable = true;
    requireApproval = false;
  };
};
```

**Step 4: Test build for all hosts**

Run: `nix build .#nixosConfigurations`
Expected: All configurations build successfully

**Step 5: Commit**

```bash
git add hosts/nexus/configuration.nix hosts/forge/configuration.nix hosts/sentry/configuration.nix
git commit -m "feat(hermes-agent): enable on nexus, forge, sentry"
```

---

## Phase 4: Custom Skills

### Task 9: Create nixos-deployment skill

**Files:**
- Create: `modules/services/hermes-agent/skills/nixos-deployment/SKILL.md`

**Step 1: Create skill directory**

Run: `mkdir -p modules/services/hermes-agent/skills/nixos-deployment`
Expected: Directory created

**Step 2: Write nixos-deployment skill**

```markdown
---
name: nixos-deployment
description: Deploy NixOS configurations across the 4-host cluster using just commands
version: 1.0.0
author: j_kro
license: MIT
metadata:
  hermes:
    tags: [NixOS, Colmena, Deployment, Cluster]
---

# NixOS Cluster Deployment

Deploy NixOS flake configurations across zephyr, nexus, forge, sentry.

## Quick Commands

### Test Configuration
```bash
just test
```

### Deploy to All Hosts
```bash
just deploy
```

### Apply to Local Host Only
```bash
just switch
```

## Safety Rules

CRITICAL: Always follow these rules:
1. **ALWAYS** run `just test` before `just deploy`
2. If SSH breaks on any node, STOP immediately
3. Check `modules/networking/*` changes affect zephyr AND nexus
4. Read commit messages before deploying

## Troubleshooting

### Build Failures
```bash
# Check error details
nix log .#nixosConfigurations.zephyr

# Fix and rebuild
just test
```

### SSH Issues
```bash
# Test SSH to each node
ssh zephyr "echo OK"
ssh nexus "echo OK"
ssh forge "echo OK"
ssh sentry "echo OK"
```

## Related Skills
- k8s-migration: For Kubernetes deployment steps
- cluster-management: For multi-host operations
```

**Step 3: Commit**

```bash
git add modules/services/hermes-agent/skills/
git commit -m "feat(hermes-agent): add nixos-deployment skill"
```

---

### Task 10: Create k8s-migration skill

**Files:**
- Create: `modules/services/hermes-agent/skills/k8s-migration/SKILL.md`

**Step 1: Create skill directory**

Run: `mkdir -p modules/services/hermes-agent/skills/k8s-migration`
Expected: Directory created

**Step 2: Write k8s-migration skill**

```markdown
---
name: k8s-migration
description: Guide the Kubernetes migration following the 9-week roadmap
version: 1.0.0
author: j_kro
license: MIT
metadata:
  hermes:
    tags: [Kubernetes, K8s, Migration, Roadmap]
---

# Kubernetes Migration Guide

Follow the 9-week migration plan from ROADMAP.md.

## Current Status

Phase 1 Complete: K8s v1.35.0 running on Zephyr

## Migration Phases

### Phase 2: Core Services (Weeks 2-4)
- Storage: Longhorn distributed storage
- Ingress: NGINX or Traefik
- Cert-Manager: TLS automation
- Monitoring: Prometheus + Grafana

### Phase 3: Application Migration (Weeks 5-7)
- AI Inference Gateway → StatefulSet
- Qdrant → Helm Chart
- Services → Deployments

### Phase 4: Optimization (Weeks 8-9)
- HPA: Horizontal Pod Autoscaling
- VPA: Vertical Pod Autoscaling
- GitOps: ArgoCD integration

## Validation Checklist

After each phase:
- [ ] Pods are running
- [ ] Services are accessible
- [ ] Data persistence works
- [ ] Backups are functional

## Rollback Plan

If migration fails:
```bash
# Revert to NixOS configs
just deploy

# Disable affected services
kubectl delete -f <manifest>
```

## References
- Full roadmap: ROADMAP.md
- K8s docs: docs/kubernetes/
```

**Step 3: Commit**

```bash
git add modules/services/hermes-agent/skills/
git commit -m "feat(hermes-agent): add k8s-migration skill"
```

---

### Task 11: Create ai-gateway-config skill

**Files:**
- Create: `modules/services/hermes-agent/skills/ai-gateway-config/SKILL.md`

**Step 1: Create skill directory**

Run: `mkdir -p modules/services/hermes-agent/skills/ai-gateway-config`
Expected: Directory created

**Step 2: Write ai-gateway-config skill**

```markdown
---
name: ai-gateway-config
description: Configure and manage the AI Inference Gateway with routing and backends
version: 1.0.0
author: j_kro
license: MIT
metadata:
  hermes:
    tags: [AI, Gateway, LM-Studio, Configuration]
---

# AI Inference Gateway Configuration

The AI Gateway provides OpenAI-compatible API with intelligent routing.

## Architecture

```
Request → Gateway → Backend Selection → LM Studio | ZAI | Pollinations
                  ↓
              Knowledge Fabric
              (RAG + Semantic Search)
```

## Configuration Location

```nix
modules/services/ai-inference/default.nix
```

## Backend Priority

1. **LM Studio** (local, port 1234) - Primary
2. **ZAI** (cloud, coding plan) - Fallback
3. **Pollinations** (free tier) - Fallback

## Model Routing

By token count:
- 0-128K tokens: `qwen3.5-35b-a3b`
- 128K+ tokens: `qwen3.5-27b`

## Adding New Models

Edit the `models` section in `default.nix`:

```nix
models."my-model" = {
  name = "My Custom Model";
};
```

## Testing

```bash
# Check gateway health
curl http://localhost:8080/health

# List available models
curl http://localhost:8080/v1/models

# Test inference
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.5-35b-a3b","messages":[{"role":"user","content":"Hello"}]}'
```

## RAG Integration

Knowledge Fabric with:
- Qdrant vector database (port 6333)
- Semantic search with sentence-transformers
- Hybrid search (vector + BM25)
- MCP broker for tool integration

## Related Skills
- cluster-management: Multi-host operations
- k8s-migration: Future container deployment
```

**Step 3: Commit**

```bash
git add modules/services/hermes-agent/skills/
git commit -m "feat(hermes-agent): add ai-gateway-config skill"
```

---

### Task 12: Create cluster-management skill

**Files:**
- Create: `modules/services/hermes-agent/skills/cluster-management/SKILL.md`

**Step 1: Create skill directory**

Run: `mkdir -p modules/services/hermes-agent/skills/cluster-management`
Expected: Directory created

**Step 2: Write cluster-management skill**

```markdown
---
name: cluster-management
description: Manage the 4-host NixOS cluster (zephyr, nexus, forge, sentry)
version: 1.0.0
author: j_kro
license: MIT
metadata:
  hermes:
    tags: [Cluster, NixOS, Colmena, Multi-host]
---

# NixOS Cluster Management

## Cluster Overview

| Host | IP | Role | Hardware |
|------|-------|-------------|------------------|
| Zephyr | 10.1.1.110 | Control plane, AI Gateway, Gaming | RTX 3090 |
| Nexus | 10.1.1.120 | Storage, GPU | RTX 3090, 8TB storage |
| Forge | 10.1.1.130 | GPU compute, mining | RTX 3090, RX 7900 |
| Sentry | 10.1.1.140 | Monitoring, logging | - |

## Multi-Host Commands

### Check all hosts
```bash
for host in zephyr nexus forge sentry; do
  ssh $host "hostname && uname -r"
done
```

### Run command on all hosts
```bash
for host in zephyr nexus forge sentry; do
  ssh $host "nixos-version"
done
```

### Colmena Deployment
```bash
# Build all hosts
nix run .#apps.x86_64-linux.colmena -- build

# Deploy to specific host
nix run .#apps.x86_64-linux.colmena -- apply --on zephyr

# Deploy to all hosts
just deploy
```

## Service Health Checks

```bash
# AI Gateway
curl http://10.1.1.110:8080/health

# Qdrant
curl http://10.1.1.110:6333/

# Prometheus
curl http://10.1.1.140:9090/-/healthy
```

## Storage Access

```bash
# Garage S3 (Nexus)
s3cmd ls s3://hermes-storage

# NFS mounts
df -h | grep nfs
```

## Monitoring

- Grafana: http://10.1.1.140:3000
- Prometheus: http://10.1.1.140:9090
- Loki: http://10.1.1.140:3100

## Safety

Before cluster-wide changes:
1. Test on one node first
2. Have rollback plan ready
3. Monitor logs during deployment
```

**Step 3: Commit**

```bash
git add modules/services/hermes-agent/skills/
git commit -m "feat(hermes-agent): add cluster-management skill"
```

---

## Phase 5: Storage Setup

### Task 13: Create NFS export on Garage

**Files:**
- Modify: `modules/services/garage.nix`

**Step 1: Add Hermes NFS export to Garage configuration**

Find the Garage configuration and add hermes export:

```nix
# In garage.nix configuration.services.garage.settings
garage.defaultNamespaces.v0y0 = "hermes";

# Export configuration
environment.etc."garage/hermes-bucket.txt".text = ''
  hermes-files
'';
```

**Step 2: Commit**

```bash
git add modules/services/garage.nix
git commit -m "feat(garage): add NFS export for hermes storage"
```

---

## Phase 6: Testing

### Task 14: Test build on all hosts

**Step 1: Build Zephyr configuration**

Run: `nix build .#nixosConfigurations.zephyr.config.system.build.toplevel`
Expected: Build succeeds

**Step 2: Build Nexus configuration**

Run: `nix build .#nixosConfigurations.nexus.config.system.build.toplevel`
Expected: Build succeeds

**Step 3: Build Forge configuration**

Run: `nix build .#nixosConfigurations.forge.config.system.build.toplevel`
Expected: Build succeeds

**Step 4: Build Sentry configuration**

Run: `nix build .#nixosConfigurations.sentry.config.system.build.toplevel`
Expected: Build succeeds

**Step 5: Commit completion marker**

```bash
echo "Build test completed successfully" | git commit --allow-empty -m "test(hermes-agent): all host configurations build successfully"
```

---

### Task 15: Deploy to Zephyr (first node)

**Step 1: Deploy to Zephyr**

Run: `sudo nixos-rebuild switch --install-bootloader`
Expected: Build and switch succeeds

**Step 2: Verify Hermes is available**

Run: `hermes --version`
Expected: Hermes version displayed

**Step 3: Verify AI Gateway integration**

Run: `hermes "Say hello"`
Expected: Response from local AI Gateway

**Step 4: Verify NFS mount**

Run: `df -h | grep hermes`
Expected: NFS mount visible

**Step 5: Verify skills loaded**

Run: `hermes skills list | grep nixos`
Expected: nixos-deployment skill listed

**Step 6: Commit success marker**

```bash
echo "Zephyr deployment successful" | git commit --allow-empty -m "deploy(hermes-agent): zephyr deployment successful"
```

---

### Task 16: Deploy to remaining nodes

**Step 1: Deploy to Nexus**

Run: `ssh nexus "sudo nixos-rebuild switch --install-bootloader"`
Expected: Build and switch succeeds

**Step 2: Deploy to Forge**

Run: `ssh forge "sudo nixos-rebuild switch --install-bootloader"`
Expected: Build and switch succeeds

**Step 3: Deploy to Sentry**

Run: `ssh sentry "sudo nixos-rebuild switch --install-bootloader"`
Expected: Build and switch succeeds

**Step 4: Verify on each node**

Run: `for node in nexus forge sentry; do ssh $node "hermes --version"; done`
Expected: Hermes version displayed on each

**Step 5: Test shared skills**

On Zephyr: `hermes "Create a test file in /tmp/hermes-test.txt"`
On Nexus: `hermes "List files in /tmp/hermes-test.txt"`
Expected: Skills and memory are shared

**Step 6: Commit success marker**

```bash
echo "Multi-node deployment successful" | git commit --allow-empty -m "deploy(hermes-agent): all nodes deployed successfully"
```

---

## Phase 7: Validation

### Task 17: Full integration test

**Step 1: Test AI Gateway connectivity**

Run: `hermes "What models are available?"`
Expected: Lists available models from AI Gateway

**Step 2: Test terminal access**

Run: `hermes "Run 'nixos-version' on all cluster nodes"`
Expected: Executes on all nodes and returns results

**Step 3: Test skill usage**

Run: `hermes "Deploy configuration using nixos-deployment skill"`
Expected: Executes deployment workflow

**Step 4: Test shared memory**

On Zephyr: `hermes "Remember: the cluster has 4 nodes"`
On Nexus: `hermes "What do you remember about the cluster?"
Expected: Memory is shared across nodes

**Step 5: Commit success marker**

```bash
echo "Integration tests passed" | git commit --allow-empty -m "test(hermes-agent): all integration tests passed"
```

---

## Rollback Plan

If any critical issue occurs:

### Rollback to previous state

```bash
# Revert Hermes commits
git revert HEAD~4..HEAD

# Rebuild
just switch

# Verify services are back to normal
systemctl status ai-inference-gateway
```

---

## Success Criteria

- [ ] Hermes CLI available on all 4 nodes
- [ ] Can invoke local models via AI Gateway
- [ ] Skills and memory shared across nodes
- [ ] Terminal access works on all nodes
- [ ] Custom NixOS skills loaded and functional
- [ ] Multi-node cluster operations work

---

## Next Steps After Deployment

1. Create additional custom skills based on usage patterns
2. Add messaging gateway (Telegram/Discord) for mobile access
3. Explore MCP integration with existing MCP broker
4. Consider containerization for K8s migration
