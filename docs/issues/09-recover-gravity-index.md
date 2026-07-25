# Issue #9: Recover gravity_index orphaned Phase-1 work

**Priority:** LOW  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** Original user ask: *"find opportunities to make management and orchestration of this codebase easier. first, look at opportunities in the codebase, and then look for ai tools."*  
  The codebase half was completed (drift cycle). The "ai tools" half was orphaned because `gravity_index` could not be spawned as a subagent (`spawn_agents` only takes agent-types).  
**Depends on:** Operator's understanding of current tooling.  
**Blocks:** completion of original ask.

## Context

`gravity_index` is a service-discovery tool (see https://docs.codebuff.com/tools/gravity-index). It recommends third-party services (DB, auth, payments, etc.) for a given stack + constraints. It needs to be called as a TOOL (top-level), not via spawn_agents.

For this cluster (4-node SOHO, single-operator trust, ~123GB RAM, NixOS-first, K8s + Vaultwarden + Garage S3 + Casdoor + SearXNG + Gitea already in place), reasonable service recommendations would cover: secrets manager (already secretspec + sops-nix), CI runner (already self-hosted), observability (already Prometheus + Grafana), artifact registry (Garage S3 covers), and so on. Cluster is mostly internally-built; gravity_index would highlight gaps we haven't noticed.

## Acceptance Criteria

- A `gravity_index search` query delivers 3-5 concrete service recommendations tailored to this cluster.
- Recommendations recorded alongside codebase improvements (existing knowledge.md or new TODOs).

## Approach

1. Run `gravity_index` as a tool (NOT spawn_agents) with query: *"secrets manager compatible with sops-nix for k8s workloads running on a small NixOS cluster"*.
2. Run a second query: *"AI agent infrastructure for a SOHO NixOS cluster with single-operator trust model"*.
3. Capture recommendations in this issue (or in knowledge.md).
4. Triage: which recommendations are worth implementing? (Most likely a defense-in-depth monitoring recommendation.)

## Risk

- If gravity_index isn't available in this environment, fall back to manual research on alternatives.

## Related

- Original user message (start-of-session)
- `.factory/init.sh` (might be relevant)
