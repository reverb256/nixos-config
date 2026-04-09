# Environment

## Cluster Access
- kubectl context configured on Zephyr (current host)
- All nodes accessible via SSH (zephyr, nexus, forge, sentry)
- NFS shared storage at /run/nixos-shared (Zephyr exports)

## Key Paths
- Manifests: /etc/nixos/kubernetes-manifests/
- AI inference manifests: /etc/nixos/kubernetes-manifests/ai-inference/
- vLLM manifests: /etc/nixos/kubernetes-manifests/ai-inference/vllm/
- Gateway source: /etc/nixos/modules/services/ai-inference/ai_inference_gateway/
- NixOS modules: /etc/nixos/modules/
- Secrets: /etc/nixos/secrets/ (agenix encrypted)

## Model Files
- Nexus: /home/j_kro/.lmstudio/models/Jackrong/Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF/Qwen3.5-0.8B.Q8_0.gguf
- Zephyr: Same path (exists)
- Forge: NOT present (needs copy)

## Container Images
- vLLM: vllm/vllm-openai:v0.6.3.post1 (available on Nexus and Zephyr)
- Gateway: docker.io/library/ai-inference-gateway:local (Nix-built, on Zephyr)
- kb-mcp: localhost/kb-mcp:latest (on Nexus)

## Environment Variables
- None required for manifest changes
- NixOS manages all system-level configuration

## What belongs here
Env vars, external dependencies, model file locations, container image details.
## What does NOT belong here
Service ports/commands (use .factory/services.yaml), architecture (use architecture.md).
