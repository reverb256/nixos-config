"""NixOS Cluster MCP Server — cluster-specific orchestration tools."""

import argparse
import json
import subprocess

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("nixos-cluster")

VALID_HOSTS = {"zephyr", "nexus", "forge", "sentry"}


def _run(cmd: list[str], timeout: int = 30, cwd: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd)


@mcp.tool()
def cluster_status() -> str:
    """Get aggregated cluster status: nodes, pods summary, resource usage."""
    result = {}

    nodes = _run(["kubectl", "get", "nodes", "-o", "json"])
    if nodes.returncode == 0:
        node_data = json.loads(nodes.stdout)
        result["nodes"] = [
            {
                "name": n["metadata"]["name"],
                "status": next(
                    (c["status"] for c in n["status"]["conditions"] if c["type"] == "Ready"),
                    "Unknown",
                ),
                "roles": sorted(
                    k.replace("node-role.kubernetes.io/", "")
                    for k in n["metadata"]["labels"]
                    if k.startswith("node-role.kubernetes.io/")
                ),
            }
            for n in node_data["items"]
        ]

    pods = _run(["kubectl", "get", "pods", "-A", "--no-headers"])
    if pods.returncode == 0:
        lines = [l for l in pods.stdout.strip().split("\n") if l]
        result["pods"] = {
            "total": len(lines),
            "running": sum(1 for l in lines if "Running" in l),
            "pending": sum(1 for l in lines if "Pending" in l),
            "failed": sum(1 for l in lines if "Error" in l or "Failed" in l),
            "image_pull_backoff": sum(1 for l in lines if "ImagePullBackOff" in l or "ErrImagePull" in l),
        }

    return json.dumps(result, indent=2)


@mcp.tool()
def check_node_capacity(node: str) -> str:
    """Check CPU, memory, and pod capacity on a cluster node."""
    if node not in VALID_HOSTS:
        return f"ERROR: invalid node '{node}'. Must be one of: {', '.join(sorted(VALID_HOSTS))}"

    result = _run(["kubectl", "get", "node", node, "-o", "json"])
    if result.returncode != 0:
        return f"ERROR: node {node} not found"

    data = json.loads(result.stdout)
    allocatable = data["status"]["allocatable"]
    capacity = data["status"]["capacity"]

    return json.dumps(
        {
            "node": node,
            "allocatable": {
                "cpu": allocatable.get("cpu"),
                "memory": allocatable.get("memory"),
                "pods": allocatable.get("pods"),
                "nvidia.com/gpu": allocatable.get("nvidia.com/gpu", "0"),
            },
            "capacity": {
                "cpu": capacity.get("cpu"),
                "memory": capacity.get("memory"),
                "pods": capacity.get("pods"),
            },
        },
        indent=2,
    )


@mcp.tool()
def safe_scale(namespace: str, deployment: str, replicas: int) -> str:
    """Scale a deployment with pod explosion prevention guards.

    Enforces: replicas 0-10, namespace total <= 20, checks current state first.
    """
    if replicas < 0 or replicas > 10:
        return f"ERROR: replicas must be 0-10, got {replicas}"

    current = _run(
        ["kubectl", "get", "deploy", deployment, "-n", namespace, "-o", "jsonpath={.spec.replicas}"]
    )
    if current.returncode != 0:
        return f"ERROR: deployment {namespace}/{deployment} not found"

    total = _run(
        ["kubectl", "get", "deploy", "-n", namespace, "-o", "jsonpath={range .items[*]}{.spec.replicas}\\n{end}"]
    )
    total_replicas = sum(int(r) for r in total.stdout.strip().split("\n") if r.strip().isdigit())
    diff = replicas - int(current.stdout)

    if total_replicas + diff > 20:
        return f"BLOCKED: would exceed namespace limit (current total: {total_replicas}, delta: +{diff})"

    scale = _run(["kubectl", "scale", "deploy", deployment, f"--replicas={replicas}", "-n", namespace])
    if scale.returncode != 0:
        return f"ERROR: {scale.stderr.strip()}"

    return f"Scaled {namespace}/{deployment} {current.stdout} → {replicas}"


@mcp.tool()
def debug_pod(namespace: str, pod_name: str) -> str:
    """Debug a failing pod: describe + events + recent logs."""
    parts = []

    describe = _run(["kubectl", "describe", "pod", pod_name, "-n", namespace], timeout=30)
    events_start = describe.stdout.find("Events:")
    events_section = describe.stdout[events_start:] if events_start >= 0 else "No events found"
    parts.append(f"=== EVENTS ===\n{events_section[-1500:]}")

    logs = _run(["kubectl", "logs", pod_name, "-n", namespace, "--tail=50"], timeout=30)
    parts.append(f"\n=== LOGS (last 50) ===\n{logs.stdout[-1000:]}")

    if logs.returncode != 0:
        parts.append(f"\n=== LOG ERRORS ===\n{logs.stderr[-500:]}")

    return "\n".join(parts)


@mcp.tool()
def deploy_host(host: str) -> str:
    """Deploy NixOS configuration to a specific host via just deploy.

    Runs in /etc/nixos. host must be: zephyr, nexus, forge, or sentry.
    """
    if host not in VALID_HOSTS:
        return f"ERROR: invalid host '{host}'. Must be one of: {', '.join(sorted(VALID_HOSTS))}"

    result = _run(["just", "deploy", host], timeout=600, cwd="/etc/nixos")
    if result.returncode == 0:
        return result.stdout[-2000:]
    return f"ERROR:\n{result.stderr[-2000:]}"


@mcp.tool()
def check_nix_store(store_path: str, node: str) -> str:
    """Verify a /nix/store path exists on a target cluster node.

    Useful before deploying to confirm binaries are available on the host.
    """
    if not store_path.startswith("/nix/store/"):
        return f"ERROR: not a /nix/store path: {store_path}"

    result = _run(["ssh", node, f"test -e {store_path}"], timeout=15)
    return f"EXISTS on {node}" if result.returncode == 0 else f"MISSING on {node}"


def main():
    parser = argparse.ArgumentParser(description="NixOS Cluster MCP Server")
    parser.add_argument("--transport", choices=["stdio", "sse"], default="stdio")
    parser.add_argument("--port", type=int, default=8081, help="Port for SSE transport")
    args = parser.parse_args()

    if args.transport == "sse":
        mcp.settings.host = "0.0.0.0"
        mcp.settings.port = args.port
        mcp.settings.transport_security = False
        mcp.run(transport="sse")
    else:
        mcp.run()


if __name__ == "__main__":
    main()
