# AI Stack Refactor Plan

> **Status:** Proposed
> **Last Verified:** 2026-08-12
> **Owner:** j_kro
> **Scope:** `nixos-config`, the external Home Manager input, and the user Nix profile

## Decision summary

Keep the current local inference path as the reliable baseline. Add NVIDIA's serving
components as an opt-in NVIDIA path. Do not replace working llama.cpp services until a
measured comparison passes.

The target architecture has four clear layers:

```text
agent clients → switchyard / gateway → selected serving backend → GPU or CPU
                         │
                         ├─ local llama.cpp / TurboQuant
                         ├─ vLLM where it already fits
                         └─ NVIDIA NIM or TensorRT-LLM on NVIDIA nodes
```

Use NeMo Guardrails as an optional policy proxy. Use Hermes Agent and NemoClaw as agent
execution and isolation concerns, not as model-serving runtimes.

## Verified current boundaries

### Layer 1: NixOS configuration

The source of truth is this repository.

- Host-specific inference and routing live in `hosts/*/configuration.nix` and
  `hosts/*/services.nix`.
- `modules/services/ai-inference/` contains the legacy gateway module and gateway source.
  The production gateway is now built and deployed through Kubernetes; the NixOS module
  still provides compatibility options and status tooling.
- `modules/services/switchyard/` provides the local OpenAI-compatible routing proxy.
  Its routes distinguish local Bonsai, NVIDIA NIM, OpenCode Go, and OpenCode Zen.
- `kubernetes/modules/ai-inference.nix` owns the K3s gateway deployment, Qdrant, Redis,
  model discovery, and the NVIDIA NIM fallback URL.
- `kubernetes/modules/llama-servers.nix` and the host service modules own local model
  servers.

The Z.AI/Zhipu provider and its MCP names are being removed. NVIDIA NIM remains a separate
provider. A NIM model ID containing `z-ai/` is an NVIDIA catalog model identifier, not a
Z.AI API or MCP integration.

### Layer 2: Home Manager

The leaf configuration is in the separate `home-manager-config` flake input at
`/home/j_kro/Projects/home-manager-config`. This repository only contains the NixOS
bridge and retained shared modules under `modules/home-manager/`.

AI client settings are emitted by the NixOS modules under
`modules/development/ai-coding-tools/` and by the external Home Manager leaves. These
outputs must consume one provider registry rather than each defining a separate provider
list.

### Layer 3: User Nix profile

High-churn tools such as Hermes and Freebuff are owned by the user profile. Do not move
these binaries into Home Manager when that creates priority collisions. Use the existing
profile activation workflow and keep credentials outside generated model files where the
client supports environment references.

### Runtime evidence

The current measured local baselines from this session are:

| Service | Host and accelerator | Measured generation |
|---|---|---:|
| Bonsai ternary + DSpark | Zephyr, RTX 3090 | 57.5 tok/s |
| Bonsai 1-bit | Zephyr, RTX 3060 Ti | 37.7 tok/s |
| Bonsai 1-bit | Nexus, RTX 3060 Ti | 31.2 tok/s |
| Bonsai 1-bit | Sentry, RX 5600 XT Vulkan | 10.8 tok/s |

These are benchmark observations, not permanent capacity guarantees. The Sentry A3B
experiment must remain reversible and must not change mining policy or NVIDIA UMA policy.
UMA is a Zephyr NVIDIA concern. It does not apply to Sentry's AMD Vulkan path.

## NVIDIA component roles

| Component | Layer | Use in this cluster |
|---|---|---|
| GPU Operator | Kubernetes infrastructure | Evaluate only for NVIDIA worker nodes; do not mix it blindly with NixOS-managed drivers and toolkit |
| NIM | Packaged serving endpoint | First NVIDIA production experiment; requires NGC/NVIDIA credentials and model-specific terms |
| TensorRT-LLM | Optimized execution and engine build layer | Use when NIM is insufficient and an engine build is justified |
| Triton | General model server | Use when serving several model backends or ensembles; not required in front of NIM |
| Dynamo | Distributed inference orchestration | Later portfolio experiment after one stable serving backend is measured |
| NeMo Framework | Training, fine-tuning, and customization | Separate research/training track; not a replacement for the gateway |
| NeMo Guardrails | Policy and conversation control | Optional gateway middleware, kept outside low-level inference engines |
| Hermes Agent | Agent runtime and tool use | User-profile / portfolio layer; route it through switchyard |
| NemoClaw | Sandboxed agent deployment pattern | Evaluate for an isolated portfolio demo; do not make it the cluster control plane |

## Staged implementation plan

### Stage 0 — Finish the provider cleanup

1. Remove Z.AI options, routing branches, generated config entries, MCP names, and unused
   encrypted secrets.
2. Preserve local, gateway, and NVIDIA NIM providers in every generated client config.
3. Add tests that parse generated JSON and assert that no Z.AI provider or credential name
   is present.
4. Run gateway syntax tests and `just check` in the issue worktree. If the existing model-store path triggers the repository's pure-evaluation guard, record that failure and run `nix flake check --impure` as the validation command until that separate path is fixed.

Exit criteria: no active source/config reference to the Z.AI provider; local and NIM
providers remain discoverable.

### Stage 1 — Establish a canonical provider contract

Create one checked-in provider registry with these fields:

- provider ID and display name;
- OpenAI-compatible base URL;
- credential reference name, never the credential value;
- supported model IDs and capabilities;
- host or cluster placement;
- health endpoint and timeout;
- fallback eligibility;
- privacy and egress classification.

Generate OpenCode, Pi, Crush, Droid, Claude, Hermes, and gateway discovery data from that
registry. Keep the generator idempotent and preserve user-managed fields.

Exit criteria: one model/provider inventory produces equivalent client outputs and a diff
shows no provider loss.

### Stage 2 — Stabilize local serving

1. Keep llama.cpp/TurboQuant as the default local backend.
2. Measure prompt processing, generation speed, first-token latency, VRAM, host RAM, and
   error rate for each model and host.
3. Finish the reversible Sentry A3B experiment with `--n-cpu-moe` only after verifying the
   exact binary supports the flag and the model architecture.
4. Keep Zephyr's UMA setting host-specific. Do not generalize it to Nexus, Forge, or Sentry.

Exit criteria: benchmark artifacts are stored with model, binary, flags, context, and
hardware metadata; failed experiments roll back without changing the default route.

### Stage 3 — Add one NVIDIA production-grade backend

Start with one NIM deployment on one NVIDIA node. Do not deploy NIM, raw TensorRT-LLM,
vLLM, and Triton for the same model at the same time.

1. Confirm NGC access, image license, model license, and secret routing.
2. Deploy one pinned NIM image with explicit GPU and memory limits.
3. Add a switchyard target and health probe. Set an explicit `NIM_FALLBACK_MODEL`; never send a local model ID to NIM by guesswork.
4. Benchmark against the existing llama.cpp/vLLM route using the same prompts and context.
5. Keep NIM opt-in until latency, throughput, restart behavior, and memory use are better
   or provide a clear capability that local serving lacks.

Exit criteria: a reproducible NIM deployment and a measured comparison, not only a healthy
pod.

### Stage 4 — Add policy and agent isolation

1. Place NeMo Guardrails or the existing gateway policy middleware before selected remote
   and agentic routes.
2. Keep Hermes Agent in the user profile and expose tools through the existing MCP bridge.
3. Evaluate NemoClaw for a portfolio demonstration of sandboxed agent execution. Keep
   credentials in its supported secret helper and restrict network egress.
4. Record a threat model for tool execution, repository writes, and external provider use.

Exit criteria: tool calls have explicit approval boundaries, logs identify the provider,
and a failed guardrail does not take down the serving layer.

### Stage 5 — Portfolio packaging

Use `reverb256.ca` and the GitHub portfolio as the public narrative:

- **Flagship:** a reproducible multi-backend inference gateway with measured routing.
- **Demonstration:** local llama.cpp/TurboQuant versus NIM on the same OpenAI-compatible
  contract.
- **Systems case study:** NixOS + K3s + GPU scheduling + rollback and provenance.
- **Agent case study:** Hermes/NemoClaw sandbox with NeMo Guardrails and auditable tools.
- **Research note:** Sentry 6GB MoE offload experiment, including negative results.

Publish architecture diagrams, benchmark methodology, limitations, and deployment scripts.
Do not publish API keys, private model weights, internal host addresses, or claims based
only on stale status documents.

## Guardrails for the refactor

- Keep changes in an issue worktree and merge through review.
- Do not deploy from a feature worktree.
- Do not mix imperative Kubernetes changes with declarative source changes.
- Pin container images and model revisions.
- Treat NIM credentials and model licenses as separate from code.
- Keep provider IDs stable during migration so client configs do not silently change.
- Make each serving backend independently removable.
- Record benchmark and live deployment evidence with dates.

## Official sources

- [NVIDIA NIM documentation](https://docs.nvidia.com/nim/index.html)
- [NVIDIA Dynamo documentation](https://docs.nvidia.com/dynamo/latest/)
- [Triton TensorRT-LLM user guide](https://docs.nvidia.com/deeplearning/triton-inference-server/user-guide/docs/getting_started/trtllm_user_guide.html)
- [NVIDIA NeMo documentation](https://docs.nvidia.com/nemo/index.html)
- [NeMo Guardrails documentation](https://docs.nvidia.com/nemo/guardrails/latest/getting_started/README.html)
- [NVIDIA GPU Operator documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html)
- [NVIDIA NemoClaw repository](https://github.com/NVIDIA/NemoClaw)
- [NemoClaw Hermes quickstart](https://docs.nvidia.com/nemoclaw/user-guide/hermes/get-started/quickstart)
- [NousResearch Hermes Agent](https://github.com/NousResearch/hermes-agent)
