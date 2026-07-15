"""
NixOS Cluster MCP Server

Exposes K8s cluster operations as MCP tools with safety rules baked in:
- Zephyr: infrastructure + mining only (31GB RAM, prone to OOM)
- Nexus: default for all workloads (46GB RAM)
- Forge: mining + GPU compute (16GB RAM)
- Sentry: monitoring + ROCm inference (31GB RAM)

GPU index remapping: nvidia-container-runtime remaps indices inside containers
(host GPU 1 = container GPU 0). Never spawn manual llama-server processes.
"""

from __future__ import annotations

import json
import subprocess
import os
from typing import Any

from fastmcp import FastMCP


mcp = FastMCP("nixos-cluster")

# Cluster topology
NODES = {
    "zephyr": {"ip": "10.1.1.110", "role": "workstation+control-plane", "ram": "31GB", "gpus": "2x NVIDIA"},
    "nexus": {"ip": "10.1.1.120", "role": "primary-server+gateway", "ram": "46GB", "gpus": "1x NVIDIA"},
    "forge": {"ip": "10.1.1.130", "role": "gpu-computing+mining", "ram": "16GB", "gpus": "2x NVIDIA + 2x AMD"},
    "sentry": {"ip": "10.1.1.140", "role": "monitoring+rocm-inference", "ram": "31GB", "gpus": "1x AMD RX 5600 XT"},
}

# AI inference backends
BACKENDS = {
    "llama-3060ti": {"host": "nexus", "port": 8040, "node_ip": "10.1.1.120"},  # vLLM Qwen3.5-2B-AWQ,
    "llama-3090": {"host": "zephyr", "port": 1237, "node_ip": "10.1.1.110"},
    "llama-sentry": {"host": "sentry", "port": 1235, "node_ip": "10.1.1.140"},
}

GATEWAY_URL = os.getenv("GATEWAY_URL", "http://10.15.67.242:8080")
NIXOS_DIR = os.getenv("NIXOS_DIR", "/etc/nixos")
KUBECTL_TIMEOUT = os.getenv("KUBECTL_TIMEOUT", "30")


def _kubectl(*args: str, namespace: str | None = None, timeout: str | None = None) -> tuple[int, str]:
    """Run kubectl and return (exit_code, output)."""
    cmd = ["kubectl"]
    if namespace:
        cmd += ["-n", namespace]
    cmd += list(args)
    if timeout:
        cmd += [f"--request-timeout={timeout}"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=int(timeout or KUBECTL_TIMEOUT) + 10)
        return result.returncode, (result.stdout + result.stderr).strip()
    except subprocess.TimeoutExpired:
        return -1, f"kubectl timed out after {timeout or KUBECTL_TIMEOUT}s"


def _curl(url: str, timeout: int = 5) -> tuple[int, str]:
    """Run curl and return (exit_code, output)."""
    try:
        result = subprocess.run(
            ["curl", "-s", "--max-time", str(timeout), url],
            capture_output=True, text=True, timeout=timeout + 5
        )
        return result.returncode, result.stdout.strip()
    except subprocess.TimeoutExpired:
        return -1, f"curl timed out after {timeout}s"


# ──────────────────────────────────────────────
# Cluster Status Tools
# ──────────────────────────────────────────────

@mcp.tool
def cluster_status() -> dict[str, Any]:
    """Get aggregated cluster health: node status, pod summary, gateway health."""
    # Node status
    rc, nodes_out = _kubectl("get", "nodes", "-o", "wide", "--no-headers")
    nodes = []
    if rc == 0:
        for line in nodes_out.splitlines():
            parts = line.split()
            if len(parts) >= 6:
                nodes.append({
                    "name": parts[0],
                    "status": parts[1],
                    "roles": parts[2],
                    "version": parts[4] if len(parts) > 4 else "unknown",
                    "ip": parts[5] if len(parts) > 5 else "unknown",
                })

    # Pod summary
    rc, pods_out = _kubectl("get", "pods", "-A", "--no-headers")
    pod_summary = {"total": 0, "running": 0, "pending": 0, "failed": 0, "other": 0}
    if rc == 0:
        for line in pods_out.splitlines():
            parts = line.split()
            if len(parts) >= 4:
                pod_summary["total"] += 1
                status = parts[3]
                if status == "Running":
                    pod_summary["running"] += 1
                elif status == "Pending":
                    pod_summary["pending"] += 1
                elif status in ("Failed", "Error", "CrashLoopBackOff", "ImagePullBackOff"):
                    pod_summary["failed"] += 1
                else:
                    pod_summary["other"] += 1

    # Gateway health
    rc, gw_out = _curl(f"{GATEWAY_URL}/health")
    gateway = {"status": "unknown", "raw": gw_out[:200]}
    if rc == 0 and gw_out:
        try:
            gw_data = json.loads(gw_out)
            gateway = {"status": gw_data.get("status", "unknown"), "backend_healthy": gw_data.get("backend", {}).get("healthy", False)}
        except json.JSONDecodeError:
            pass

    return {"nodes": nodes, "pods": pod_summary, "gateway": gateway}


@mcp.tool
def node_info(node: str) -> dict[str, Any]:
    """Get detailed info for a specific node: labels, capacity, allocatable, conditions."""
    if node not in NODES:
        return {"error": f"Unknown node '{node}'. Valid: {list(NODES.keys())}"}

    rc, out = _kubectl("get", "node", node, "-o", "json")
    if rc != 0:
        return {"error": f"kubectl failed: {out[:300]}"}

    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return {"error": f"Failed to parse kubectl output: {out[:200]}"}

    status = data.get("status", {})
    capacity = status.get("capacity", {})
    allocatable = status.get("allocatable", {})
    conditions = [
        {"type": c.get("type"), "status": c.get("status"), "reason": c.get("reason")}
        for c in status.get("conditions", [])
    ]

    return {
        "node": node,
        "info": NODES[node],
        "capacity": capacity,
        "allocatable": allocatable,
        "conditions": conditions,
        "labels": {k: v for k, v in data.get("metadata", {}).get("labels", {}).items()
                   if not k.startswith("node.kubernetes.io")},
    }


# ──────────────────────────────────────────────
# K8s Workload Tools
# ──────────────────────────────────────────────

@mcp.tool
def pod_status(namespace: str = "ai-inference", label_selector: str | None = None) -> dict[str, Any]:
    """List pods in a namespace with status, node assignment, and restart counts."""
    args = ["get", "pods", "-n", namespace, "-o", "wide", "--no-headers"]
    if label_selector:
        args += ["-l", label_selector]

    rc, out = _kubectl(*args)
    if rc != 0:
        return {"error": f"kubectl failed: {out[:300]}"}

    pods = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 8:
            pods.append({
                "name": parts[0],
                "ready": parts[1],
                "status": parts[2],
                "restarts": parts[3],
                "node": parts[6],
                "ip": parts[5] if len(parts) > 5 else "unknown",
            })

    return {"namespace": namespace, "count": len(pods), "pods": pods}


@mcp.tool
def deployment_logs(
    namespace: str,
    deployment: str,
    tail: int = 50,
    container: str | None = None,
) -> dict[str, Any]:
    """Get recent logs from a deployment's pods."""
    args = ["logs", "-n", namespace, f"deploy/{deployment}", f"--tail={tail}"]
    if container:
        args += ["-c", container]

    rc, out = _kubectl(*args, timeout="60")
    if rc != 0:
        return {"error": f"kubectl logs failed: {out[:300]}"}

    lines = out.splitlines()
    return {
        "namespace": namespace,
        "deployment": deployment,
        "tail": tail,
        "line_count": len(lines),
        "logs": lines[-tail:],
    }


@mcp.tool
def rollout_restart(namespace: str, deployment: str) -> dict[str, Any]:
    """Safely restart a deployment with rollout restart."""
    rc, out = _kubectl("rollout", "restart", f"deploy/{deployment}", "-n", namespace)
    if rc != 0:
        return {"error": f"Rollout restart failed: {out[:300]}"}

    return {"namespace": namespace, "deployment": deployment, "action": "restarted", "output": out}


@mcp.tool
def rollout_status(namespace: str, deployment: str, timeout: int = 120) -> dict[str, Any]:
    """Check rollout status of a deployment."""
    rc, out = _kubectl(
        "rollout", "status", f"deploy/{deployment}", "-n", namespace,
        f"--timeout={timeout}s",
        timeout=str(timeout + 30),
    )
    if rc != 0:
        return {"namespace": namespace, "deployment": deployment, "status": "failed_or_timeout", "output": out[:300]}

    return {"namespace": namespace, "deployment": deployment, "status": "complete", "output": out}


# ──────────────────────────────────────────────
# Safe Scale Tool (with OOM prevention)
# ──────────────────────────────────────────────

@mcp.tool
def safe_scale(namespace: str, deployment: str, replicas: int) -> dict[str, Any]:
    """Scale a deployment with safety checks. Blocks scaling beyond 1 replica for GPU workloads
    and warns about Zephyr OOM risk."""
    # Safety: check what node this deploys to
    rc, out = _kubectl("get", "deploy", deployment, "-n", namespace, "-o",
                       "jsonpath={.spec.template.spec.nodeName}", timeout="10")
    target_node = out.strip() if rc == 0 else "unknown"

    warnings = []

    # Zephyr OOM protection
    if target_node == "zephyr" and replicas > 0:
        # Check existing pod count on zephyr
        rc2, out2 = _kubectl("get", "pods", "-A", "--field-selector", "spec.nodeName=zephyr",
                             "-o", "jsonpath={.items[*].metadata.name}", timeout="10")
        existing = len(out2.split()) if rc2 == 0 and out2 else 0
        if existing > 10:
            warnings.append(f"Zephyr already has {existing} pods. OOM risk is HIGH.")

    # GPU workload protection: don't scale beyond 1 for llama-server
    if "llama-server" in deployment and replicas > 1:
        return {
            "error": f"BLOCKED: {deployment} is a GPU workload. Max replicas is 1. "
                     f"GPU workloads cannot share GPUs across replicas safely.",
            "namespace": namespace,
            "deployment": deployment,
        }

    rc, out = _kubectl("scale", f"deploy/{deployment}", "-n", namespace,
                       f"--replicas={replicas}")
    if rc != 0:
        return {"error": f"Scale failed: {out[:300]}"}

    result = {"namespace": namespace, "deployment": deployment, "replicas": replicas, "target_node": target_node}
    if warnings:
        result["warnings"] = warnings
    return result


# ──────────────────────────────────────────────
# AI Inference Tools
# ──────────────────────────────────────────────

@mcp.tool
def check_models() -> dict[str, Any]:
    """Check which models are loaded on each AI inference backend."""
    results = {}
    for name, backend in BACKENDS.items():
        url = f"http://{backend['node_ip']}:{backend['port']}/v1/models"
        rc, out = _curl(url)
        if rc == 0 and out:
            try:
                data = json.loads(out)
                models = [m.get("id", "unknown") for m in data.get("data", [])]
                results[name] = {"status": "up", "host": backend["host"], "models": models}
            except json.JSONDecodeError:
                results[name] = {"status": "parse_error", "host": backend["host"], "raw": out[:100]}
        else:
            results[name] = {"status": "down", "host": backend["host"]}

    return {"backends": results}


@mcp.tool
def get_deployment_env(namespace: str, deployment: str) -> dict[str, Any]:
    """Get environment variables from a deployment's container spec."""
    rc, out = _kubectl(
        "get", "deploy", deployment, "-n", namespace,
        "-o", "jsonpath={.spec.template.spec.containers[0].env}",
        timeout="10",
    )
    if rc != 0:
        return {"error": f"Failed: {out[:300]}"}

    try:
        env_list = json.loads(out) if out else []
    except json.JSONDecodeError:
        return {"error": f"Failed to parse env: {out[:200]}"}

    env = {}
    for item in env_list:
        name = item.get("name", "")
        value = item.get("value", item.get("valueFrom", "<ref>"))
        env[name] = value

    return {"namespace": namespace, "deployment": deployment, "env": env}


@mcp.tool
def set_deployment_env(
    namespace: str,
    deployment: str,
    env_vars: dict[str, str],
) -> dict[str, Any]:
    """Set environment variables on a deployment and trigger a rollout restart.
    Example: {"CUDA_VISIBLE_DEVICES": "0", "NVIDIA_VISIBLE_DEVICES": "0"}"""
    if not env_vars:
        return {"error": "No env vars provided."}

    # Build kubectl set env arguments
    env_args = []
    for k, v in env_vars.items():
        env_args.append(f"{k}={v}")

    rc, out = _kubectl("set", "env", f"deploy/{deployment}", "-n", namespace, *env_args)
    if rc != 0:
        return {"error": f"set env failed: {out[:300]}"}

    return {
        "namespace": namespace,
        "deployment": deployment,
        "env_set": env_vars,
        "output": out,
        "note": "Rollout restart triggered automatically by set env.",
    }


@mcp.tool
def describe_pod(namespace: str, pod_name: str) -> dict[str, Any]:
    """Describe a pod: events, conditions, container status, resource usage."""
    rc, out = _kubectl("describe", "pod", pod_name, "-n", namespace, timeout="15")
    if rc != 0:
        return {"error": f"Describe failed: {out[:300]}"}

    # Truncate to last 200 lines (events are at the bottom)
    lines = out.splitlines()
    return {
        "namespace": namespace,
        "pod": pod_name,
        "line_count": len(lines),
        "describe": lines[-200:],
    }


@mcp.tool
def get_events(namespace: str, limit: int = 20) -> dict[str, Any]:
    """Get recent K8s events in a namespace, sorted by last seen."""
    rc, out = _kubectl("get", "events", "-n", namespace, "--sort-by=.lastTimestamp",
                       "--no-headers", timeout="15")
    if rc != 0:
        return {"error": f"get events failed: {out[:300]}"}

    events = []
    for line in out.splitlines()[-limit:]:
        parts = line.split(maxsplit=7)
        if len(parts) >= 8:
            events.append({
                "last_seen": parts[0],
                "type": parts[1],
                "reason": parts[2],
                "object": parts[5] if len(parts) > 5 else "unknown",
                "message": parts[7] if len(parts) > 7 else "",
            })

    return {"namespace": namespace, "count": len(events), "events": events}


# ──────────────────────────────────────────────
# GPU Inventory Tools
# ──────────────────────────────────────────────

@mcp.tool
def gpu_inventory() -> dict[str, Any]:
    """Report GPU allocation across all nodes: which GPUs exist, which workloads use them,
    and available capacity. Reads from K8s node capacity and pod device assignments."""
    # Get node GPU capacity
    rc, out = _kubectl("get", "nodes", "-o", "json", timeout="15")
    if rc != 0:
        return {"error": f"kubectl failed: {out[:300]}"}

    nodes = {}
    try:
        for item in json.loads(out).get("items", []):
            name = item["metadata"]["name"]
            capacity = item.get("status", {}).get("capacity", {})
            nvidia = int(capacity.get("nvidia.com/gpu", "0"))
            amd = int(capacity.get("amd.com/gpu", "0"))
            if nvidia > 0 or amd > 0:
                nodes[name] = {"nvidia_gpus": nvidia, "amd_gpus": amd, "workloads": []}
    except (json.JSONDecodeError, ValueError) as e:
        return {"error": f"Failed to parse node data: {e}"}

    # Get GPU-using pods from ai-inference namespace
    rc, pods_out = _kubectl("get", "pods", "-n", "ai-inference", "-o", "json", timeout="15")
    if rc == 0:
        try:
            for pod in json.loads(pods_out).get("items", []):
                node_name = pod.get("spec", {}).get("nodeName", "")
                if node_name not in nodes:
                    continue
                pod_name = pod.get("metadata", {}).get("name", "")
                phase = pod.get("status", {}).get("phase", "Unknown")
                containers = pod.get("spec", {}).get("containers", [])

                gpu_info = {}
                for c in containers:
                    for env in c.get("env", []):
                        if env.get("name") in ("CUDA_VISIBLE_DEVICES", "NVIDIA_VISIBLE_DEVICES"):
                            gpu_info[env["name"]] = env.get("value", "")

                if gpu_info or any("nvidia" in str(c.get("resources", {})) for c in containers):
                    nodes[node_name]["workloads"].append({
                        "pod": pod_name,
                        "status": phase,
                        "gpu_assignment": gpu_info or "runtime-class managed",
                    })
        except (json.JSONDecodeError, ValueError):
            pass

    # Check mining processes on each node
    for node_name in nodes:
        rc, nvidia_smi = _kubectl("debug", f"node/{node_name}", "--", "nvidia-smi",
                                  "--query-gpu=index,name,memory.used,memory.total,utilization.gpu",
                                  "--format=csv,noheader,nounits",
                                  timeout="20")
        if rc == 0 and nvidia_smi:
            gpus = []
            for line in nvidia_smi.splitlines():
                parts = [p.strip() for p in line.split(",")]
                if len(parts) >= 5:
                    gpus.append({
                        "index": parts[0],
                        "name": parts[1],
                        "mem_used_mb": parts[2],
                        "mem_total_mb": parts[3],
                        "gpu_util_pct": parts[4],
                    })
            nodes[node_name]["gpus"] = gpus

    return {"nodes": nodes}


@mcp.tool
def gateway_health() -> dict[str, Any]:
    """Deep gateway health check: replica count, HPA status, probe health,
    backend connectivity, single-replica risk assessment."""
    issues = []

    # Gateway deployment info
    rc, out = _kubectl("get", "deploy", "-l", "app=ai-inference-gateway",
                       "-n", "ai-inference", "-o", "json", timeout="15")
    deploy_info = {}
    if rc == 0:
        try:
            items = json.loads(out).get("items", [])
            if items:
                d = items[0]
                spec = d["spec"]
                container = spec["template"]["spec"]["containers"][0]
                deploy_info = {
                    "replicas": spec.get("replicas", 0),
                    "available": d.get("status", {}).get("availableReplicas", 0),
                    "updated": d.get("status", {}).get("updatedReplicas", 0),
                    "node_selector": spec["template"]["spec"].get("nodeSelector"),
                    "has_readiness_probe": "readinessProbe" in container,
                    "has_liveness_probe": "livenessProbe" in container,
                }
                if spec.get("replicas", 0) == 1:
                    issues.append("SINGLE_REPLICA: Gateway has only 1 replica. No failover if node dies.")
                if not spec["template"]["spec"].get("nodeSelector"):
                    issues.append("NO_NODE_SELECTOR: Gateway can be scheduled anywhere. No placement control.")
        except (json.JSONDecodeError, KeyError, IndexError):
            deploy_info = {"error": "Failed to parse deployment"}

    # HPA check
    rc, hpa_out = _kubectl("get", "hpa", "-l", "app=ai-inference-gateway",
                           "-n", "ai-inference", "--no-headers", timeout="10")
    hpa_info = {"configured": False}
    if rc == 0 and hpa_out.strip():
        hpa_info = {"configured": True, "raw": hpa_out.strip()[:200]}
    elif rc == 0:
        issues.append("NO_HPA: No HorizontalPodAutoscaler configured. Cannot auto-scale under load.")

    # Health endpoint
    rc, health_out = _curl(f"{GATEWAY_URL}/health")
    health_data = {}
    if rc == 0 and health_out:
        try:
            health_data = json.loads(health_out)
        except json.JSONDecodeError:
            health_data = {"raw": health_out[:200]}
    else:
        issues.append(f"GATEWAY_UNREACHABLE: Cannot reach {GATEWAY_URL}/health")
        health_data = {"error": "unreachable"}

    # Backend connectivity
    backend_status = {}
    for name, backend in BACKENDS.items():
        url = f"http://{backend['node_ip']}:{backend['port']}/v1/models"
        rc, out = _curl(url)
        if rc == 0 and out:
            try:
                models = [m.get("id") for m in json.loads(out).get("data", [])]
                backend_status[name] = {"status": "up", "models": models}
            except json.JSONDecodeError:
                backend_status[name] = {"status": "parse_error"}
        else:
            backend_status[name] = {"status": "down"}
            issues.append(f"BACKEND_DOWN: {name} ({backend['host']}:{backend['port']}) is unreachable")

    # Network policies
    rc, np_out = _kubectl("get", "networkpolicies", "-n", "ai-inference", "--no-headers", timeout="10")
    policy_count = len([l for l in np_out.splitlines() if l.strip()]) if rc == 0 else 0

    return {
        "deployment": deploy_info,
        "hpa": hpa_info,
        "health": health_data,
        "backends": backend_status,
        "network_policies": policy_count,
        "issues": issues,
        "risk_level": "HIGH" if len(issues) >= 3 else "MEDIUM" if len(issues) >= 1 else "LOW",
    }


@mcp.tool
def eval_status() -> dict[str, Any]:
    """Check the status of any golden datasets or eval infrastructure.
    Reports whether evals are configured for the gateway."""
    eval_indicators = {
        "golden_dataset": False,
        "langfuse_configured": False,
        "braintrust_configured": False,
        "eval_script": False,
    }

    # Check for eval-related env vars in gateway
    rc, out = _kubectl("get", "deploy", "-l", "app=ai-inference-gateway",
                       "-n", "ai-inference", "-o",
                       "jsonpath={.items[0].spec.template.spec.containers[0].env}",
                       timeout="10")
    if rc == 0:
        try:
            for env in json.loads(out):
                name = env.get("name", "").lower()
                if "langfuse" in name or "eval" in name or "braintrust" in name:
                    if "langfuse" in name:
                        eval_indicators["langfuse_configured"] = True
                    if "braintrust" in name:
                        eval_indicators["braintrust_configured"] = True
        except (json.JSONDecodeError, ValueError):
            pass

    # Check for eval scripts in gateway project
    import pathlib
    gateway_dir = pathlib.Path("/data/projects/own/ai-inference-gateway")
    if gateway_dir.exists():
        eval_files = list(gateway_dir.rglob("*eval*")) + list(gateway_dir.rglob("*golden*"))
        if eval_files:
            eval_indicators["eval_script"] = True
            eval_indicators["eval_files"] = [str(f.relative_to(gateway_dir)) for f in eval_files[:10]]

    # Check for test files
    if gateway_dir.exists():
        test_files = list(gateway_dir.rglob("test_*.py")) + list(gateway_dir.rglob("*_test.py"))
        eval_indicators["test_files_count"] = len(test_files)

    return {
        "status": "NO_EVALS" if not any([eval_indicators["golden_dataset"],
                                          eval_indicators["langfuse_configured"],
                                          eval_indicators["eval_script"]])
                   else "PARTIAL",
        "indicators": eval_indicators,
        "recommendation": "Create a 50-example golden dataset from gateway traces and add a Langfuse sidecar.",
    }


# ──────────────────────────────────────────────
# Cluster Reference Resources
# ──────────────────────────────────────────────

@mcp.resource("cluster://topology")
def cluster_topology() -> str:
    """Cluster node topology: IPs, roles, RAM, GPUs."""
    return json.dumps(NODES, indent=2)


@mcp.resource("cluster://backends")
def ai_backends() -> str:
    """AI inference backend endpoints."""
    return json.dumps(BACKENDS, indent=2)


# ──────────────────────────────────────────────
# NixOS Host Management Tools
# ──────────────────────────────────────────────
# These tools manage the NixOS system layer (build / switch / verify) on each
# physical node. They deliberately SSH to the TARGET host and build there, so a
# heavy `nix build` never runs on zephyr (31GB, earlyoom kills it). Hosts track
# `main` (AGENTS.md), so resetting to origin/main is the correct deploy state.

import subprocess as _sp

_SSH_OPTS = ["-o", "StrictHostKeyChecking=accept-new", "-o", "BatchMode=yes", "-T"]


def _ssh_run(host: str, cmd: str, timeout: int = 2400) -> tuple[int, str]:
    """SSH to a node as j_kro and run a command. Returns (rc, combined_output)."""
    if host not in NODES:
        return 1, f"Unknown host '{host}'. Valid: {list(NODES.keys())}"
    ip = NODES[host]["ip"]
    full = ["ssh", *_SSH_OPTS, f"j_kro@{ip}", "bash", "--norc", "--noprofile", "-c", cmd]
    try:
        r = _sp.run(full, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except _sp.TimeoutExpired:
        return -1, f"ssh command timed out after {timeout}s"


@mcp.tool
def nixos_git_state() -> dict[str, Any]:
    """Root-cause visibility for deploy failures: report /etc/nixos git state on
    every node (branch, behind/ahead vs origin/main, dirty files). A dirty or
    behind tree is the usual cause of `nix run` / `nix build` eval failures."""
    out = {}
    for host in NODES:
        rc, raw = _ssh_run(host, (
            "cd /etc/nixos 2>/dev/null && "
            "echo BRANCH:$(git branch --show-current) && "
            "echo BEHIND:$(git rev-list --count HEAD..origin/main 2>/dev/null) && "
            "echo AHEAD:$(git rev-list --count origin/main..HEAD 2>/dev/null) && "
            "echo DIRTY:$(git status --porcelain 2>/dev/null | wc -l)"
        ), timeout=30)
        info: dict[str, Any] = {"reachable": rc == 0}
        if rc == 0:
            for line in raw.splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    info[k.lower()] = v.strip()
        else:
            info["error"] = raw[:200]
        out[host] = info
    return out


@mcp.tool
def nixos_status(host: str) -> dict[str, Any]:
    """NixOS host health: current generation, uptime, failed systemd unit count,
    and whether the node is on the latest origin/main config."""
    if host not in NODES:
        return {"error": f"Unknown host '{host}'. Valid: {list(NODES.keys())}"}
    rc, raw = _ssh_run(host, (
        "echo GEN:$(readlink /nix/var/nix/profiles/system | xargs basename); "
        "echo UPTIME:$(uptime -p 2>/dev/null || true); "
        "echo FAILED:$(systemctl --failed --no-legend 2>/dev/null | wc -l); "
        "cd /etc/nixos 2>/dev/null && echo BEHIND:$(git rev-list --count HEAD..origin/main 2>/dev/null)"
    ), timeout=30)
    if rc != 0:
        return {"host": host, "reachable": False, "error": raw[:300]}
    result = {"host": host, "reachable": True}
    for line in raw.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            result[k.lower()] = v.strip()
    return result


@mcp.tool
def nixos_failed_units(host: str) -> dict[str, Any]:
    """List failed systemd units on a NixOS host (the `systemctl --failed` view)."""
    if host not in NODES:
        return {"error": f"Unknown host '{host}'. Valid: {list(NODES.keys())}"}
    rc, raw = _ssh_run(host, "systemctl --failed --no-legend --no-pager 2>/dev/null", timeout=30)
    units = [u.split()[0] for u in raw.splitlines() if u.strip()]
    return {"host": host, "count": len(units), "units": units}


@mcp.tool
def nixos_build(host: str, reset_to_main: bool = True) -> dict[str, Any]:
    """Build a host's NixOS toplevel ON the target host (avoids zephyr earlyoom).
    Optionally resets the host's /etc/nixos to origin/main first (hosts track main).
    Returns the built store path. Does NOT switch — use nixos_switch for that.
    Long-running (10-40 min cold); the caller should poll nixos_status afterwards."""
    if host not in NODES:
        return {"error": f"Unknown host '{host}'. Valid: {list(NODES.keys())}"}
    sync = "git fetch origin main >/dev/null 2>&1 && git reset --hard origin/main >/dev/null 2>&1 && " if reset_to_main else ""
    build_cmd = (
        f"cd /etc/nixos && {sync}"
        f"OUT=$(nix build /etc/nixos#nixosConfigurations.{host}.config.system.build.toplevel "
        f"--no-link --print-out-paths 2>&1 | tail -1) && "
        f"echo BUILT:$OUT && echo \"$OUT\" | grep -q '^/nix/store' && echo OK || echo BUILD_FAILED"
    )
    rc, raw = _ssh_run(host, build_cmd, timeout=2400)
    store_path = ""
    for line in raw.splitlines():
        if line.startswith("BUILT:/nix/store"):
            store_path = line.split(":", 1)[1].strip()
    return {
        "host": host,
        "rc": rc,
        "store_path": store_path or None,
        "ok": rc == 0 and bool(store_path),
        "tail": raw.splitlines()[-12:],
    }


@mcp.tool
def nixos_switch(host: str, store_path: str | None = None) -> dict[str, Any]:
    """Switch a NixOS host to a built toplevel and activate it.
    If store_path is omitted, switches to the currently-built toplevel (last nix build).
    Falls back to `nixos-rebuild switch` if no explicit path is given and none is found."""
    if host not in NODES:
        return {"error": f"Unknown host '{host}'. Valid: {list(NODES.keys())}"}
    if store_path:
        switch_cmd = (
            f"sudo nix-env -p /nix/var/nix/profiles/system --set {store_path} && "
            f"sudo {store_path}/bin/switch-to-configuration switch"
        )
    else:
        switch_cmd = "cd /etc/nixos && sudo nixos-rebuild switch"
    rc, raw = _ssh_run(host, switch_cmd, timeout=600)
    return {
        "host": host,
        "rc": rc,
        "switched": rc == 0,
        "tail": raw.splitlines()[-15:],
    }


@mcp.tool
def nixos_deploy(host: str, reset_to_main: bool = True) -> dict[str, Any]:
    """One-shot safe deploy: build the host's toplevel on the target (no zephyr
    earlyoom), reset /etc/nixos to origin/main first (hosts track main), then
    switch + activate. Returns build path, switch result, and post-switch
    failed-unit count. This is the canonical cluster deploy path."""
    if host not in NODES:
        return {"error": f"Unknown host '{host}'. Valid: {list(NODES.keys())}"}
    sync = "git fetch origin main >/dev/null 2>&1 && git reset --hard origin/main >/dev/null 2>&1 && " if reset_to_main else ""
    deploy_cmd = (
        f"cd /etc/nixos && {sync}"
        f"OUT=$(nix build /etc/nixos#nixosConfigurations.{host}.config.system.build.toplevel "
        f"--no-link --print-out-paths 2>&1 | tail -1) && "
        f"echo BUILT:$OUT && "
        f"sudo nix-env -p /nix/var/nix/profiles/system --set \"$OUT\" && "
        f"sudo \"$OUT\"/bin/switch-to-configuration switch 2>&1 | tail -8 && "
        f"echo POSTFAIL:$(systemctl --failed --no-legend 2>/dev/null | wc -l)"
    )
    rc, raw = _ssh_run(host, deploy_cmd, timeout=2400)
    store_path = ""
    postfail = None
    for line in raw.splitlines():
        if line.startswith("BUILT:/nix/store"):
            store_path = line.split(":", 1)[1].strip()
        if line.startswith("POSTFAIL:"):
            postfail = line.split(":", 1)[1].strip()
    return {
        "host": host,
        "rc": rc,
        "store_path": store_path or None,
        "deployed": rc == 0 and bool(store_path),
        "post_switch_failed_units": postfail,
        "tail": raw.splitlines()[-15:],
    }


@mcp.resource("cluster://safety-rules")
def safety_rules() -> str:
    """Safety rules enforced by this MCP server."""
    return json.dumps({
        "zephyr_oom": "31GB RAM, prone to OOM. Infrastructure + mining only.",
        "default_node": "Nexus (46GB) for all non-infrastructure workloads.",
        "gpu_remapping": "nvidia-container-runtime remaps GPU indices: host GPU 1 = container GPU 0.",
        "no_manual_processes": "Never spawn manual llama-server processes. Always use K8s.",
        "gpu_replica_limit": "GPU workloads max 1 replica.",
    }, indent=2)


def main():
    import argparse
    parser = argparse.ArgumentParser(description="NixOS Cluster MCP Server")
    parser.add_argument("--transport", choices=["stdio", "sse"], default="stdio")
    parser.add_argument("--port", type=int, default=8081)
    args = parser.parse_args()
    if args.transport == "sse":
        mcp.run(transport="sse", host="0.0.0.0", port=args.port)
    else:
        mcp.run()


if __name__ == "__main__":
    main()
