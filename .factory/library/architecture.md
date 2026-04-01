# AI Inference Stack Architecture

## Components

### AI Inference Gateway
- FastAPI app (ai_inference_gateway) running as Kubernetes Deployment
- Image built via NixOS dockerTools, deployed with imagePullPolicy: Never
- Runs with hostNetwork on Zephyr, port 8081 internally, exposed via ClusterIP service on 8080
- Routes AI inference requests to backends (vLLM, llama-cpp, etc.)
- Features: MCP broker, RAG with Qdrant, SearXNG integration, system prompts

### vLLM (LLM Inference)
- Serves Qwen3.5-0.8B.Q8_0.gguf model (~800MB GGUF format)
- Image: vllm/vllm-openai:v0.6.3.post1 (includes Python + CUDA runtime)
- REQUIRES runtimeClassName: nvidia for GPU passthrough
- REQUIRES --device=cuda flag in container args
- Target: Nexus (primary), Forge (secondary with GPU takeover)
- Priority: ai-inference-high (900) can preempt mining-low (100)

### Supporting Services
- **Qdrant**: Vector DB for RAG, StatefulSet on Nexus with PVC
- **kb-mcp**: Knowledge base MCP server on Nexus
- **SearXNG**: Search integration, 3 replicas in search namespace
- **SearXNG MCP**: MCP wrapper for SearXNG on Nexus

### Infrastructure
- **Caddy Ingress**: DaemonSet in ingress-system namespace, routes external traffic
- **Metrics Server**: In kube-system, provides resource metrics for HPA
- **NVIDIA Device Plugin**: DaemonSet with nodeSelector nixos-nvidia-cdi=enabled

## GPU Passthrough Chain
```
NixOS nvidia-common.nix (hardware.nvidia-container-toolkit)
  → kubernetes.nix (nvidia-containerd-setup service)
    → containerd configured with nvidia runtime at /etc/containerd/conf.d/99-nvidia.toml
      → Pod spec: runtimeClassName: nvidia + nvidia.com/gpu: "1" resource request
        → Container gets GPU device nodes + CUDA libraries
```

## Node Roles
| Node | GPUs | RAM | Role |
|------|------|-----|------|
| Zephyr | 2x NVIDIA (RTX 3090 + 3060 Ti) | 31GB | Control plane, gateway |
| Nexus | 1x NVIDIA (RTX 3060 Ti) | 46GB | DEFAULT workload target |
| Forge | 2x NVIDIA RTX 4060 + 2x AMD | 15GB | GPU mining, optional vLLM |
| Sentry | 1x AMD | 31GB | Monitoring, logging |

## Data Flow
```
External → Caddy (443) → Gateway (8080) → vLLM (8000) → GPU inference
                       → Qdrant (6333) → RAG retrieval
                       → SearXNG (8080) → Web search
```
