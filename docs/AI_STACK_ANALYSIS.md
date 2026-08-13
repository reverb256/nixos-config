# AI Stack Analysis

> **Status:** Active reference
> **Last Verified:** 2026-08-12
> **Owner:** j_kro
> **Authority:** Checked-in source only; verify runtime claims with `just health`, Kubernetes queries, and host service status.

## Executive summary

The cluster uses a hybrid AI stack. NixOS owns host drivers, local model services,
routing proxies, secrets wiring, and client configuration emitters. K3s owns the
OpenAI-compatible gateway, RAG support services, and selected inference workloads. The
external Home Manager repository owns user configuration. The user Nix profile owns
high-churn tools such as Hermes and Freebuff.

The former Z.AI/Zhipu cloud provider and its MCP integrations are not part of the target
architecture. NVIDIA NIM is a separate provider and remains available through the
NVIDIA API route. Do not confuse an NVIDIA catalog model ID such as `z-ai/glm-5.2` with
the removed Z.AI API provider.

The detailed, staged migration plan is
[`ai-stack-refactor-plan-2026-08-12.md`](ai-stack-refactor-plan-2026-08-12.md).

## Current checked-in architecture

```text
AI clients
  ├─ OpenCode / Pi / Crush / Droid / Claude
  ├─ Hermes Agent and Freebuff
  └─ Kubernetes coding-tool workloads
        │
        ▼
Switchyard and AI Gateway
  ├─ Switchyard: local routing and fallback policy
  └─ K3s gateway: OpenAI/Anthropic-compatible API, auth, RAG, metrics
        │
        ├─ Local llama.cpp / TurboQuant services
        ├─ vLLM workloads where configured
        └─ NVIDIA NIM API or deployment path
```

### NixOS and host services

- `hosts/zephyr/` contains the workstation's local model services, Switchyard, client
  routing, and host-specific NVIDIA settings.
- `hosts/nexus/` contains the primary builder/dispatcher and cluster AI service wiring.
- `hosts/forge/` contains mixed-vendor GPU compute and mining configuration.
- `hosts/sentry/` contains AMD/Vulkan inference and monitoring configuration.
- `modules/services/switchyard/` defines the local provider routes.
- `modules/services/ai-inference/` contains gateway source and compatibility modules. The
  production gateway is deployed through the K3s source under `kubernetes/`.

### Kubernetes

`kubernetes/modules/ai-inference.nix` defines the gateway, model discovery, Qdrant, Redis,
network policy, and the configured NVIDIA NIM fallback URL. The gateway's backend is
selected through checked-in ConfigMap values and secret references. It does not use the
removed Z.AI credentials.

`kubernetes/modules/llama-servers.nix` defines selected local model workloads. Check the
module and live pod state before claiming that a model is available on a node.

### Home Manager and user profile

The leaf Home Manager configuration is the separate
[`reverb256/home-manager-config`](https://github.com/reverb256/home-manager-config) input.
This repository provides the bridge and retained shared modules.

Hermes and Freebuff are user-profile tools. They must not be moved into Home Manager when
that creates package-priority collisions. Client configs must use environment-backed
credential references rather than embedding secret values.

## Measured local baseline

These values are benchmark observations from 2026-08-12. They are not capacity promises.

| Service | Host / accelerator | Generation speed |
|---|---|---:|
| Bonsai ternary + DSpark | Zephyr / RTX 3090 | 57.5 tok/s |
| Bonsai 1-bit | Zephyr / RTX 3060 Ti | 37.7 tok/s |
| Bonsai 1-bit | Nexus / RTX 3060 Ti | 31.2 tok/s |
| Bonsai 1-bit | Sentry / RX 5600 XT Vulkan | 10.8 tok/s |

Sentry's 35B-A3B experiment is a separate reversible benchmark. It uses AMD Vulkan and
therefore does not use the CUDA `GGML_CUDA_ENABLE_UNIFIED_MEMORY` setting. Zephyr's UMA
policy is host-specific and must not be generalized to the other nodes.

## Provider policy

| Provider class | Role | Status |
|---|---|---|
| Local llama.cpp / TurboQuant | Default local inference and low-egress development | Active |
| vLLM | Selected NVIDIA/Kubernetes workloads | Active where declared |
| NVIDIA NIM | Remote or opt-in NVIDIA serving path | Active route; deployment requires separate validation |
| OpenCode Go / Zen | Explicit external fallback routes | Active only where credentials and policy allow |
| Z.AI/Zhipu API and MCP | Former cloud provider | Removed from target configuration |

## Refactor priorities

1. Finish provider cleanup and add generated-config tests.
2. Create one canonical provider/model registry for all clients.
3. Keep local llama.cpp as the benchmarked baseline.
4. Add one pinned NVIDIA NIM experiment before considering TensorRT-LLM, Triton, or Dynamo.
5. Add NeMo Guardrails as policy middleware, not inside the inference engine.
6. Evaluate Hermes/NemoClaw as an isolated agent portfolio demonstration.
7. Publish reproducible benchmarks and deployment provenance as the portfolio evidence.

## Verification commands

```bash
just check
just health
kubectl get nodes -o wide
kubectl get pods -A
rg -n -i 'z\.ai|zai-api-key|zai-coding-plan|web-search-prime|web-reader' \
  --glob '!docs/**' --glob '!**/archive/**' . \
  | grep -v 'secretspec-creds-wiring.nix' || true
```

The filtered search should return no active provider or removed MCP configuration. The
SecretSpec wiring comment is an intentional removal marker. Historical mentions in dated
audits remain acceptable when they are clearly labeled as history.
