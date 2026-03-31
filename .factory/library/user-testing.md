# User Testing

Testing surface discovery, resource cost classification, and tool requirements for validation.

## Validation Surface

This mission has **two testing surfaces**:

### Surface 1: CLI / Filesystem (primary)
- **Tool**: bash (nix eval, nix flake check, nixos-rebuild build, git, test, kubectl get)
- **What**: Verify config equivalence, file existence, git state, K8s resource inventory
- **No browser needed** — all verification is CLI-based

### Surface 2: K8s Cluster State (secondary)
- **Tool**: kubectl
- **What**: Verify no active resources were affected by manifest cleanup
- **Commands**: kubectl get nodes, deployments, daemonsets, services, configmaps, namespaces

## Validation Concurrency

- **Max concurrent validators**: 3 (memory constrained — Zephyr has 31GB RAM at 84% usage)
- **Memory per validator**: ~200MB (nix eval + kubectl queries)
- **Available headroom**: ~5GB * 0.7 = 3.5GB for validators
- **CPU impact**: nix builds are CPU-heavy; limit concurrent builds to 1

## Required Skills

- No agent-browser or tuistory needed
- Standard bash/nix/kubectl for all validation
- nixos-config-worker and k8s-manifest-worker are the worker types

## Pre-Validation Requirements

Before user testing validation can run:
1. `nix flake check` must pass
2. `nixos-rebuild build` must succeed for all 4 hosts
3. kubectl must be accessible from Zephyr
4. Baseline snapshots of key settings must be captured
