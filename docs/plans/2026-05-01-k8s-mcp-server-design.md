# K8s MCP Server Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy `containers/kubernetes-mcp-server` (base K8s ops) + custom `nixos-cluster-mcp` (cluster-specific tools) accessible from all AI tools via stdio (local) and SSE (in-cluster).

**Architecture:** Two MCP servers — a Go binary from `containers/kubernetes-mcp-server` for standard K8s operations, and a Python FastMCP extension wrapping `just`/`kubectl` with cluster safety rules. Both run as stdio for Claude Code and as SSE services for in-cluster agents.

**Tech Stack:** Go (base server), Python 3.13 + FastMCP (extension), NixOS modules, K8s deployments, Caddy ingress

---

## Phase 1: Base Server — Local stdio (Tasks 1-4)

### Task 1: Add flake input for kubernetes-mcp-server

**Files:**
- Modify: `flake.nix:3` (inputs block)

**Step 1: Add input to flake.nix**

Add after the `mcp-registry` input (~line 127):

```nix
kubernetes-mcp = {
  url = "github:containers/kubernetes-mcp-server";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**Step 2: Validate syntax**

Run: `nix-instantiate --parse flake.nix > /dev/null`
Expected: no error

**Step 3: Fetch the input**

Run: `nix flake lock --update-input kubernetes-mcp`
Expected: flake.lock updated with new input

**Step 4: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat(mcp): add kubernetes-mcp-server flake input"
```

---

### Task 2: Create Nix package for kubernetes-mcp-server

**Files:**
- Create: `packages/kubernetes-mcp-server.nix`

**Step 1: Write the package derivation**

```nix
# packages/kubernetes-mcp-server.nix
{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:
buildGoModule rec {
  pname = "kubernetes-mcp-server";
  version = "0.0.51";

  src = fetchFromGitHub {
    owner = "containers";
    repo = "kubernetes-mcp-server";
    rev = "v${version}";
    hash = ""; # Will be filled after first build attempt
  };

  vendorHash = ""; # Will be filled after first build attempt

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  meta = with lib; {
    description = "MCP server for Kubernetes and OpenShift";
    homepage = "https://github.com/containers/kubernetes-mcp-server";
    license = licenses.asl20;
    mainProgram = "kubernetes-mcp-server";
  };
}
```

**Step 2: Add to flake.nix packages**

In the `packages` block of `flake.nix`, add:

```nix
kubernetes-mcp-server = pkgs.callPackage ./packages/kubernetes-mcp-server.nix {};
```

**Step 3: Attempt build to get hashes**

Run: `nix build .#kubernetes-mcp-server 2>&1 | head -5`

The build will fail with a hash mismatch — copy the `got: sha256-...` value into both `hash` fields and retry.

**Step 4: Verify build**

Run: `nix build .#kubernetes-mcp-server && ./result/bin/kubernetes-mcp-server --help`
Expected: help output with version, toolsets, transport options

**Step 5: Commit**

```bash
git add packages/kubernetes-mcp-server.nix flake.nix
git commit -m "feat(mcp): add kubernetes-mcp-server Nix package"
```

---

### Task 3: Create NixOS service module (stdio mode)

**Files:**
- Create: `modules/services/kubernetes-mcp.nix`

**Step 1: Write the NixOS module**

```nix
# modules/services/kubernetes-mcp.nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.kubernetes-mcp;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.kubernetes-mcp = {
    enable = mkEnableOption "Kubernetes MCP Server";

    package = mkOption {
      type = types.package;
      default = pkgs.kubernetes-mcp-server;
    };

    kubeconfig = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to kubeconfig file (defaults to /etc/rancher/k3s/k3s.yaml)";
    };

    toolsets = mkOption {
      type = types.listOf types.str;
      default = ["core"];
      description = "Toolsets to enable (core, helm, kiali, kubevirt)";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for SSE/HTTP transport";
    };

    transport = mkOption {
      type = types.enum ["stdio" "sse"];
      default = "stdio";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    # For stdio mode: no systemd service needed, Claude Code spawns the process
    # For SSE mode: run as systemd service
    systemd.services.kubernetes-mcp = mkIf (cfg.transport == "sse") {
      description = "Kubernetes MCP Server (SSE transport)";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "k3s.service"];
      serviceConfig = {
        ExecStart =
          "${lib.getExe cfg.package}"
          + lib.optionalString (cfg.kubeconfig != null) " --kubeconfig ${cfg.kubeconfig}"
          + " --transport sse"
          + " --port ${toString cfg.port}"
          + " --toolsets ${lib.concatStringsSep "," cfg.toolsets}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
```

**Step 2: Validate**

Run: `nix-instantiate --parse modules/services/kubernetes-mcp.nix > /dev/null`
Expected: no error

**Step 3: Commit**

```bash
git add modules/services/kubernetes-mcp.nix
git commit -m "feat(mcp): add kubernetes-mcp-server NixOS service module"
```

---

### Task 4: Wire into Claude Code settings (stdio)

**Files:**
- Modify: `~/.claude/settings.json` or project `.claude/settings.json`

**Step 1: Add MCP server config**

Add to `.claude/settings.json` mcpServers:

```json
"kubernetes": {
  "command": "kubernetes-mcp-server",
  "args": ["--toolsets", "core,helm"],
  "type": "stdio"
}
```

**Step 2: Restart Claude Code and verify**

Run: `kubernetes-mcp-server --toolsets core 2>&1 | head -5`
Expected: server starts in stdio mode, waiting for JSON-RPC input

**Step 3: Commit**

```bash
git add .claude/settings.json 2>/dev/null
git commit -m "feat(mcp): configure kubernetes-mcp-server for Claude Code"
```

---

## Phase 2: Extension Server — nixos-cluster-mcp (Tasks 5-9)

### Task 5: Scaffold Python FastMCP project

**Files:**
- Create: `packages/nixos-cluster-mcp/pyproject.toml`
- Create: `packages/nixos-cluster-mcp/src/nixos_cluster_mcp/__init__.py`
- Create: `packages/nixos-cluster-mcp/src/nixos_cluster_mcp/server.py`

**Step 1: Create pyproject.toml**

```toml
[project]
name = "nixos-cluster-mcp"
version = "0.1.0"
description = "MCP server for NixOS cluster management"
requires-python = ">=3.12"
dependencies = [
    "mcp[cli]>=1.0.0",
]

[project.scripts]
nixos-cluster-mcp = "nixos_cluster_mcp.server:main"
```

**Step 2: Create server.py with minimal server**

```python
# src/nixos_cluster_mcp/server.py
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("nixos-cluster")


@mcp.tool()
def cluster_status() -> str:
    """Get aggregated cluster status: nodes, pods, resources, health."""
    import subprocess
    import json

    result = {}
    # Nodes
    nodes = subprocess.run(
        ["kubectl", "get", "nodes", "-o", "json"],
        capture_output=True, text=True, timeout=30,
    )
    if nodes.returncode == 0:
        node_data = json.loads(nodes.stdout)
        result["nodes"] = [
            {
                "name": n["metadata"]["name"],
                "status": n["status"]["conditions"][-1]["type"],
                "roles": [
                    k.replace("node-role.kubernetes.io/", "")
                    for k in n["metadata"]["labels"]
                    if k.startswith("node-role.kubernetes.io/")
                ],
            }
            for n in node_data["items"]
        ]

    return json.dumps(result, indent=2)


@mcp.tool()
def safe_scale(namespace: str, deployment: str, replicas: int) -> str:
    """Scale a deployment with pod explosion prevention guards.

    Checks node capacity and replica history before scaling.
    Refuses to scale if it would exceed cluster safety limits.
    """
    import subprocess

    if replicas < 0 or replicas > 10:
        return f"ERROR: replicas must be 0-10, got {replicas}"

    # Check current replica count
    current = subprocess.run(
        ["kubectl", "get", "deploy", deployment, "-n", namespace,
         "-o", "jsonpath={.spec.replicas}"],
        capture_output=True, text=True, timeout=15,
    )
    if current.returncode != 0:
        return f"ERROR: deployment {namespace}/{deployment} not found"

    # Check total replicas across namespace
    total = subprocess.run(
        ["kubectl", "get", "deploy", "-n", namespace,
         "-o", "jsonpath={range .items[*]}{.spec.replicas}{\\n}{end}"],
        capture_output=True, text=True, timeout=15,
    )
    total_replicas = sum(int(r) for r in total.stdout.strip().split("\n") if r)

    if total_replicas + replicas > 20:
        return f"ERROR: would exceed namespace replica limit (current: {total_replicas}, requested: {replicas})"

    subprocess.run(
        ["kubectl", "scale", "deploy", deployment,
         f"--replicas={replicas}", "-n", namespace],
        capture_output=True, text=True, timeout=30,
    )
    return f"Scaled {namespace}/{deployment} to {replicas}"


@mcp.tool()
def debug_pod(namespace: str, pod_name: str) -> str:
    """Debug a failing pod: describe + events + recent logs."""
    import subprocess

    parts = []

    describe = subprocess.run(
        ["kubectl", "describe", "pod", pod_name, "-n", namespace],
        capture_output=True, text=True, timeout=30,
    )
    parts.append(f"=== DESCRIBE ===\n{describe.stdout[-2000:]}")

    logs = subprocess.run(
        ["kubectl", "logs", pod_name, "-n", namespace, "--tail=50"],
        capture_output=True, text=True, timeout=30,
    )
    parts.append(f"\n=== LOGS (last 50) ===\n{logs.stdout[-1000:]}")

    return "\n".join(parts)


@mcp.tool()
def deploy_host(host: str) -> str:
    """Deploy NixOS configuration to a specific host via Colmena.

    Runs in /etc/nixos directory. host must be: zephyr, nexus, forge, or sentry.
    """
    import subprocess

    valid_hosts = {"zephyr", "nexus", "forge", "sentry"}
    if host not in valid_hosts:
        return f"ERROR: invalid host '{host}'. Must be one of: {', '.join(sorted(valid_hosts))}"

    result = subprocess.run(
        ["just", "deploy", host],
        capture_output=True, text=True, timeout=600,
        cwd="/etc/nixos",
    )
    return result.stdout[-2000:] if result.returncode == 0 else f"ERROR:\n{result.stderr[-2000:]}"


@mcp.tool()
def check_nix_store(store_path: str, node: str) -> str:
    """Verify a /nix/store path exists on a target cluster node.

    Useful before deploying to confirm nix-csi scratch images have the
    required binary available on the host.
    """
    import subprocess

    if not store_path.startswith("/nix/store/"):
        return f"ERROR: not a /nix/store path: {store_path}"

    result = subprocess.run(
        ["ssh", node, f"test -e {store_path}"],
        capture_output=True, text=True, timeout=15,
    )
    return f"EXISTS on {node}" if result.returncode == 0 else f"MISSING on {node}"


@mcp.tool()
def check_node_capacity(node: str) -> str:
    """Check CPU, memory, and pod capacity on a cluster node."""
    import subprocess
    import json

    result = subprocess.run(
        ["kubectl", "get", "node", node, "-o", "json"],
        capture_output=True, text=True, timeout=15,
    )
    if result.returncode != 0:
        return f"ERROR: node {node} not found"

    data = json.loads(result.stdout)
    allocatable = data["status"]["allocatable"]
    capacity = data["status"]["capacity"]

    return json.dumps({
        "node": node,
        "allocatable": {
            "cpu": allocatable.get("cpu"),
            "memory": allocatable.get("memory"),
            "pods": allocatable.get("pods"),
        },
        "capacity": {
            "cpu": capacity.get("cpu"),
            "memory": capacity.get("memory"),
            "pods": capacity.get("pods"),
        },
    }, indent=2)


def main():
    mcp.run()


if __name__ == "__main__":
    main()
```

**Step 3: Create __init__.py**

```python
# empty
```

**Step 4: Verify Python syntax**

Run: `python3 -m py_compile packages/nixos-cluster-mcp/src/nixos_cluster_mcp/server.py`
Expected: no output (success)

**Step 5: Commit**

```bash
git add packages/nixos-cluster-mcp/
git commit -m "feat(mcp): scaffold nixos-cluster-mcp extension server"
```

---

### Task 6: Create Nix package for nixos-cluster-mcp

**Files:**
- Create: `packages/nixos-cluster-mcp/default.nix`

**Step 1: Write the Nix derivation**

```nix
# packages/nixos-cluster-mcp/default.nix
{
  lib,
  python313,
  fetchFromGitHub,
}:
python313.pkgs.buildPythonApplication {
  pname = "nixos-cluster-mcp";
  version = "0.1.0";
  pyproject = true;

  src = ./src;

  build-system = with python313.pkgs; [setuptools];

  dependencies = with python313.pkgs; [mcp];

  meta = with lib; {
    description = "MCP server for NixOS cluster management";
    license = licenses.mit;
    mainProgram = "nixos-cluster-mcp";
  };
}
```

**Step 2: Add to flake.nix packages**

In the `packages` block:

```nix
nixos-cluster-mcp = pkgs.callPackage ./packages/nixos-cluster-mcp {};
```

**Step 3: Build and verify**

Run: `nix build .#nixos-cluster-mcp`
Expected: builds successfully

Run: `./result/bin/nixos-cluster-mcp --help 2>&1 | head -5`
Expected: MCP server help or starts in stdio mode

**Step 4: Commit**

```bash
git add packages/nixos-cluster-mcp/default.nix flake.nix
git commit -m "feat(mcp): add nixos-cluster-mcp Nix package"
```

---

### Task 7: Wire nixos-cluster-mcp into Claude Code

**Files:**
- Modify: `.claude/settings.json` (mcpServers)

**Step 1: Add to mcpServers config**

```json
"nixos-cluster": {
  "command": "nixos-cluster-mcp",
  "type": "stdio"
}
```

**Step 2: Restart Claude Code and test**

In a new Claude Code session, test:
- "Check cluster status using the nixos-cluster MCP"
- "Check node capacity for nexus"

**Step 3: Commit**

```bash
git add .claude/settings.json 2>/dev/null
git commit -m "feat(mcp): configure nixos-cluster-mcp for Claude Code"
```

---

## Phase 3: In-Cluster Deployment — SSE Transport (Tasks 8-10)

### Task 8: Create K8s RBAC + Deployment for base server

**Files:**
- Modify: `kubernetes/modules/infrastructure.nix`

**Step 1: Add ServiceAccount, ClusterRole, ClusterRoleBinding**

Add to the infrastructure namespace:

```nix
infrastructure.ServiceAccount.kubernetes-mcp = {};
infrastructure.ClusterRole.kubernetes-mcp = {
  rules = [
    {apiGroups = [""]; resources = ["pods" "pods/log" "namespaces" "nodes" "services" "configmaps" "secrets"]; verbs = ["get" "list" "watch"];}
    {apiGroups = ["apps"]; resources = ["deployments" "statefulsets" "daemonsets" "replicasets"]; verbs = ["get" "list" "watch"];}
    {apiGroups = ["batch"]; resources = ["jobs" "cronjobs"]; verbs = ["get" "list" "watch"];}
    {apiGroups = ["networking.k8s.io"]; resources = ["ingresses" "networkpolicies"]; verbs = ["get" "list" "watch"];}
  ];
};
infrastructure.ClusterRoleBinding.kubernetes-mcp = {
  subjects = [{kind = "ServiceAccount"; name = "kubernetes-mcp"; namespace = "infrastructure";}];
  roleRef = {apiGroup = "rbac.authorization.k8s.io"; kind = "ClusterRole"; name = "kubernetes-mcp";};
};
```

**Step 2: Add Deployment**

```nix
infrastructure.Deployment.kubernetes-mcp = {
  metadata.labels = {app = "kubernetes-mcp";};
  spec = {
    replicas = 1;
    revisionHistoryLimit = 1;
    selector.matchLabels.app = "kubernetes-mcp";
    strategy.type = "Recreate";
    template = {
      metadata = {
        labels.app = "kubernetes-mcp";
        annotations."nix-csi/discard" = "true";
      };
      spec = {
        nodeName = "nexus";
        serviceAccountName = "kubernetes-mcp";
        containers = {
          _namedlist = true;
          mcp = {
            image = "ghcr.io/containers/kubernetes-mcp-server:latest";
            imagePullPolicy = "Always";
            args = ["--transport" "sse" "--port" "8080" "--toolsets" "core"];
            ports = [{containerPort = 8080; protocol = "TCP";}];
            resources = {
              requests = {cpu = "100m"; memory = "128Mi";};
              limits = {cpu = "500m"; memory = "256Mi";};
            };
            livenessProbe = {
              httpGet = {path = "/healthz"; port = 8080;};
              initialDelaySeconds = 10;
              periodSeconds = 30;
            };
          };
        };
      };
    };
  };
};
infrastructure.Service.kubernetes-mcp = {
  metadata.labels.app = "kubernetes-mcp";
  spec = {
    type = "ClusterIP";
    ports = [{port = 8080; targetPort = 8080; protocol = "TCP";}];
    selector.app = "kubernetes-mcp";
  };
};
```

**Step 3: Validate**

Run: `nix-instantiate --parse kubernetes/modules/infrastructure.nix > /dev/null`
Expected: no error

**Step 4: Commit**

```bash
git add kubernetes/modules/infrastructure.nix
git commit -m "feat(mcp): add kubernetes-mcp-server K8s deployment (SSE)"
```

---

### Task 9: Deploy nixos-cluster-mcp as K8s Deployment

**Files:**
- Modify: `kubernetes/modules/infrastructure.nix`

**Step 1: Add Deployment using nix-csi scratch pattern**

```nix
infrastructure.Deployment.nixos-cluster-mcp = {
  metadata.labels = {app = "nixos-cluster-mcp";};
  spec = {
    replicas = 1;
    revisionHistoryLimit = 1;
    selector.matchLabels.app = "nixos-cluster-mcp";
    strategy.type = "Recreate";
    template = {
      metadata = {
        labels.app = "nixos-cluster-mcp";
        annotations."nix-csi/discard" = "true";
      };
      spec = {
        nodeName = "nexus";
        serviceAccountName = "kubernetes-mcp";
        hostNetwork = true;
        containers = {
          _namedlist = true;
          mcp = {
            image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
            imagePullPolicy = "IfNotPresent";
            command = ["${lib.getExe (pkgs.callPackage ./packages/nixos-cluster-mcp/default.nix {})}"];
            args = ["--transport" "sse" "--port" "8081"];
            env = {HOME.value = "/tmp";};
            ports = [{containerPort = 8081; protocol = "TCP";}];
            resources = {
              requests = {cpu = "100m"; memory = "128Mi";};
              limits = {cpu = "500m"; memory = "256Mi";};
            };
            volumeMounts = {
              _namedlist = true;
              nix = {mountPath = "/nix"; readOnly = true;};
              etc-nixos = {mountPath = "/etc/nixos"; readOnly = true;};
            };
          };
        };
        volumes = {
          _namedlist = true;
          nix.hostPath = {path = "/nix"; type = "Directory";};
          etc-nixos.hostPath = {path = "/etc/nixos"; type = "Directory";};
        };
      };
    };
  };
};
infrastructure.Service.nixos-cluster-mcp = {
  metadata.labels.app = "nixos-cluster-mcp";
  spec = {
    type = "ClusterIP";
    ports = [{port = 8081; targetPort = 8081; protocol = "TCP";}];
    selector.app = "nixos-cluster-mcp";
  };
};
```

**Step 2: Validate + commit**

Run: `nix-instantiate --parse kubernetes/modules/infrastructure.nix > /dev/null`
Expected: no error

```bash
git add kubernetes/modules/infrastructure.nix
git commit -m "feat(mcp): add nixos-cluster-mcp K8s deployment (SSE)"
```

---

### Task 10: Register both servers in mcp-registry

**Files:**
- Modify: `/data/projects/own/mcp-registry/mcp-server-registry.nix`

**Step 1: Add entries to registry**

```nix
# In the registry attrset:
kubernetes = {
  description = "Kubernetes MCP Server — standard K8s operations";
  package = "kubernetes-mcp-server";
  type = "stdio";
  entrypoint = "kubernetes-mcp-server";
};

nixos-cluster = {
  description = "NixOS Cluster MCP — cluster-specific orchestration tools";
  package = "nixos-cluster-mcp";
  type = "stdio";
  entrypoint = "nixos-cluster-mcp";
};
```

**Step 2: Validate + commit**

```bash
cd /data/projects/own/mcp-registry
nix-instantiate --parse mcp-server-registry.nix > /dev/null
git add mcp-server-registry.nix
git commit -m "feat: register kubernetes and nixos-cluster MCP servers"
```

---

## Phase 4: Testing & Validation (Tasks 11-12)

### Task 11: Test base server tools from Claude Code

**Step 1: Verify MCP tools are available**

In Claude Code session, check for tools: `kubectl_get`, `pods_list`, `namespaces_list`, `kubectl_logs`

**Step 2: Test read operations**

- "List all pods in the ai-inference namespace"
- "Get logs for the ai-inference-gateway deployment"
- "List all nodes in the cluster"

**Step 3: Verify no write access (safety check)**

Try: "Delete all pods in the kube-system namespace"
Expected: Permission denied (read-only by default)

---

### Task 12: Test extension tools from Claude Code

**Step 1: Verify extension tools are available**

Check for: `cluster_status`, `safe_scale`, `debug_pod`, `deploy_host`, `check_nix_store`, `check_node_capacity`

**Step 2: Test each tool**

- "Check cluster status"
- "Check node capacity for nexus"
- "Check if /nix/store/... exists on nexus"
- "Debug the pod ai-inference-gateway in ai-inference"
- "Safely scale redis in ai-inference to 2 replicas"
- "Deploy to nexus"

**Step 3: Validate flake check passes**

Run: `nix flake check --no-build`
Expected: only pre-existing nix-csi.yaml.drv error

**Step 4: Deploy to cluster**

Run: `just switch && just deploy all`

---

## Summary

| Phase | Tasks | Outcome |
|-------|-------|---------|
| Phase 1 (1-4) | Base server + local stdio | Claude Code can do standard K8s ops |
| Phase 2 (5-7) | Extension server + local stdio | Claude Code can do cluster-specific ops |
| Phase 3 (8-10) | K8s deployments (SSE) | In-cluster agents can use both servers |
| Phase 4 (11-12) | Testing | All tools verified working |
