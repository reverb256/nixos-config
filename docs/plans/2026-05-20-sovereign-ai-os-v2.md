# Sovereign AI OS v2: The Reflow Proposal
**Date:** 2026-05-20
**Status:** Draft / Proposal
**Author:** Sisyphus (Orchestrator)
**Reference:** Friction Audit 2026-05-18

## 1. Executive Summary
The current "Sovereign AI OS" is a powerful collection of silos. While it achieves high performance, it does so through "privileged" bypasses, fragmented configurations, and overlapping agent roles. 

**Sovereign AI OS v2** transitions the system from a *collection of tools* to a *unified operating environment*. The goal is to move from "it works because I bypassed the driver" to "it works because the architecture is natively designed for AI workloads."

---

## 2. The "Current State" Friction Analysis
The "v1" implementation suffers from four critical systemic frictions:

### 2.1 GPU Layer: The "Privilege" Trap
- **Symptom**: Pods require `privileged: true` and `hostPath` mounts for NVIDIA drivers/libraries.
- **Risk**: High security vulnerability; fragile host-guest coupling.
- **Inefficiency**: Coarse-grained GPU assignment (1 Pod = 1 GPU) leads to massive under-utilization of VRAM on multi-GPU nodes.

### 2.2 Config Layer: Fragmented Truth
- **Symptom**: Model providers and endpoint mappings are scattered across `ai-models.toml`, `flake.nix`, and agent-specific `.env` or `config.yaml` files.
- **Risk**: Configuration drift. Updating a model version requires editing 4+ files across different layers.
- **Anti-Pattern**: Heavy reliance on `system.activationScripts` to imperatively write config files.

### 2.3 Orchestration Layer: Agent Soup
- **Symptom**: Overlapping responsibilities between Hermes, Kelos, and Kagent. No clear state tracking across complex tasks.
- **Inefficiency**: Linear "A $\rightarrow$ B $\rightarrow$ C" pipelines. Lack of an "Executive" layer that can plan, delegate, and critique.

### 2.4 Infra Layer: The Deployment Gap
- **Symptom**: The loop `Nix $\rightarrow$ Colmena $\rightarrow$ K8s` is too slow for rapid agentic iteration.
- **Friction**: To change a single environment variable in a pod, the entire system config often needs to be evaluated and deployed.

---

## 3. v2 Architectural Pillars

### 3.1 GPU Virtualization & Isolation
**The Reflow: From Privileged to Virtual**
- **HAMi Integration**: Implement **Heterogeneous AI Memory Isolation (HAMi)**. This allows fractional GPU slicing (e.g., assigning 4GB VRAM instead of a whole chip), enabling higher density of inference workers.
- **NVIDIA DRA**: Transition to **Dynamic Resource Allocation (DRA)**. Drivers and libraries are injected via the K8s resource model rather than `hostPath` mounts, eliminating the need for `privileged: true`.
- **RWX Model Cache**: Replace `hostPath` HuggingFace caches with an **RWX PVC** (powered by the existing NFS/Garage setup). Model weights become a shared system resource rather than a node-local artifact.

### 3.2 Unified Configuration Registry
**The Reflow: From Files to API**
- **Absolute SSOT**: `ai-models.toml` becomes the single source of truth for the entire cluster.
- **Dynamic Registry API**: The **AI Inference Gateway** will implement a `/v1/registry` endpoint. 
- **Runtime Injection**: Agents (Hermes, OpenCode, etc.) no longer read local config files. They fetch their model mappings and provider endpoints from the Gateway API at runtime.
- **Secret Proxying**: Central K8s secrets (managed via Agenix) are held by the Gateway and proxied to workers via secure headers, removing the need for distributed `.env` files.

### 3.3 Hierarchical Agent Orchestration
**The Reflow: The Executive-Worker Pattern**
- **The Executive (Hermes)**: High-reasoning "Brain." Responsible for:
    - Multi-step planning and decomposition using **Interactive HTML Blueprints** (moving beyond static Markdown to visual, dynamic specs).
    - Delegation to specialists via "Context Capsules."
    - Final synthesis and quality control.
    - *Constraint*: Never executes bash or writes code directly.
- **The Workers (Specialists)**:
    - **Kelos**: Dedicated to the "Issue $\rightarrow$ Branch $\rightarrow$ PR" coding loop.
    - **Kagent**: Dedicated to NixOS/K8s infrastructure operations.
    - **Explorer/Librarian**: Pure research and discovery.
- **Stateful Graph**: Implementation of a **LangGraph-style state machine**. The Executive tracks the global state of a task, allowing for iterative loops (Plan $\rightarrow$ Execute $\rightarrow$ Critique $\rightarrow$ Refine).
- **Visual Planning Loop**: Shift the token budget toward planning. Use HTML artifacts to create "throwaway UIs" for spec editing and system visualization, ensuring human alignment before implementation.

### 3.4 Pure Declarative Infra Loop
**The Reflow: Rendered Manifests & Fast-Paths**
- **Rendered Manifests Pattern**: 
    - Nix evaluates the high-level config $\rightarrow$ Generates plain YAML manifests $\rightarrow$ Committed to Git $\rightarrow$ Applied by **ArgoCD**.
    - This separates the *generation* of the desired state (Nix) from the *reconciliation* (ArgoCD), providing instant visibility and auditability.
- **The "Fast-Path"**: Introduce a restricted MCP toolset that allows agents to make "Ephemeral Changes" (e.g., updating a ConfigMap or scaling a deployment) for rapid tuning, which are later formalized into Nix config.

---

## 4. Implementation Roadmap

### Phase 1: GPU & Cache Foundation (The "Stabilize" Phase)
- [ ] Deploy HAMi on Nexus and Sentry.
- [ ] Migrate model caches from `hostPath` to NFS-backed RWX PVCs.
- [ ] Remove `privileged: true` from all inference pods.

### Phase 2: Config Unification (The "Harmonize" Phase)
- [ ] Extend AI Gateway to serve `/v1/registry`.
- [ ] Refactor agents to fetch config via API instead of local files.
- [ ] Centralize secrets into the Gateway proxy.

### Phase 3: Orchestration Reflow (The "Intelligence" Phase)
- [ ] Formalize "Executive" role for Hermes (update `AGENTS.md`).
- [ ] Implement the stateful graph for multi-agent task tracking.
- [ ] Move from linear pipelines to "Plan $\rightarrow$ Critique" loops.

### Phase 4: Infra Modernization (The "Scale" Phase)
- [ ] Set up ArgoCD for manifest reconciliation.
- [ ] Implement the "Rendered Manifests" pipeline in `flake.nix`.
- [ ] Deploy "Fast-Path" MCP tools for resource iteration.

---

## 5. Success Metrics
- **Security**: Zero `privileged: true` pods in the production namespace.
- **Efficiency**: GPU utilization increased by $>50\%$ via fractional slicing.
- **Velocity**: Time from "Requirement" to "PR" reduced by eliminating redundant config edits.
- **Reliability**: 100% alignment between `ai-models.toml` and active agent behavior.
