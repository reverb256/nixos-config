# Master Plan: Hermes Agent & K8s Gateway Integration

**Status:** Phase 0 Complete | Phase 1 In Progress
**Created:** 2026-04-22 | **Updated:** 2026-04-23
**Owner:** j_kro

## Overview

This plan integrates Hermes Agent and the AI Inference Gateway into the Kubernetes cluster using proven Nix/K8s patterns (nix-csi, easykubenix). Phase 0 establishes security baselines before CI/CD implementation.

## Three-Plane Isolation Model

```
┌─────────────────────────────────────────────────────────────┐
│                    THREE-PLANE ARCHITECTURE                  │
├─────────────────────────────────────────────────────────────┤
│  PLANE          PURPOSE         RUNTIME           EXAMPLES   │
├─────────────────────────────────────────────────────────────┤
│  systemd       Desktop/Gaming   host PID 1       Steam,     │
│                (interactive)                     mining,     │
│                                                   X11/Wayland│
├─────────────────────────────────────────────────────────────┤
│  K8s           AI workloads     containerized     llama-     │
│                (scalable)       (easykubenix)    server,     │
│                                                   gateway,    │
│                                                   searxng     │
├─────────────────────────────────────────────────────────────┤
│  microvm       CI/isolation     microvm.nix       test       │
│                (disposable)     (lightweight)     runners,    │
│                                                   canary      │
└─────────────────────────────────────────────────────────────┘
```

**Key Principle:** Each workload runs in the appropriate plane for its use case.

## Execution Order

**Phase 0: Security Baseline** ✅ COMPLETE
- Fix all pre-existing configuration errors
- Enable nix-mineral on all hosts
- Document hardening choices

**Phase 1: CI/CD Safety** ⏳ NEXT
- Garnix on 8 repos (hermes-agent, etc.)
- Selective flake updates (avoid nuclear `nix flake update`)
- Canary deploy pattern

**Track A: K8s Gateway Migration** (4-5 hours)
- Use nix-csi scratch pattern (proven with llama-servers)
- No image building needed
- easykubenix for manifest generation

**Track B: microvm.nix Integration** (2-3 hours)
- CI test microVMs for disposable validation
- GitHub Actions self-hosted runner
- Canary-in-microVM deploy pattern

**Track C: Three-Plane Documentation** (1-2 hours)
- Architecture diagrams
- Decision log
- Migration runbooks

## Phase 0: Security Baseline ✅

**Status:** COMPLETE

**Completed:**
- ✅ Fixed 14 pre-existing configuration errors blocking all hosts
- ✅ Enabled nix-mineral on zephyr (compatibility preset)
- ✅ Resolved gitconfig conflict with lib.mkForce
- ✅ All 4 hosts build successfully

**Remaining:**
- ⏳ Deploy nix-mineral to nexus, forge, sentry
- ⏳ Test gaming compatibility on zephyr
- ⏳ Verify AI workload compatibility

**Documentation:** PHASE-0-SECURITY-BASELINE.md

## Phase 1: CI/CD Safety Foundation

**Status:** NOT STARTED

**Objective:** Prevent broken deployments through gated CI/CD

**Tasks:**
1. **Garnix Setup** (8 repos)
   - hermes-agent (already has garnix.nix)
   - ai-inference-gateway
   - knowledge-fabric
   - compute-market
   - llama-cpp-turboquant
   - mcp-registry
   - caddy-ingress
   - searxng-cluster

2. **Selective Flake Updates**
   - Avoid `nix flake update` (updates all inputs)
   - Pin critical inputs: hermes-agent, nixpkgs
   - Update strategy: `nix flake lock update <input>`

3. **Branch Protection** (GitHub)
   - Require PR review before merge
   - Require status checks to pass
   - Block force pushes

**Documentation:** PHASE-1-CICD-SAFETY.md

## Track A: K8s Gateway Migration

**Status:** NOT STARTED

**Objective:** Migrate AI Inference Gateway from systemd to Kubernetes

**Approach:**
- Use **nix-csi scratch pattern** (proven with llama-servers)
- NO image building (uses proven llama-server approach)
- easykubenix for manifest generation

**Estimated Time:** 4-5 hours (down from 8-12 hours with nix-oci)

**Steps:**
1. Create easykubenix module for gateway
2. Add nix-csi scratch config (like llama-servers)
3. Generate manifests with easykubenix
4. Apply to cluster
5. Verify gateway works in K8s

**Documentation:** k8s-gateway-migration-plan-v2.md

## Track B: microvm.nix Integration

**Status:** NOT STARTED

**Objective:** Use microVMs for CI testing and canary deployments

**Use Cases:**
- CI test microVMs (disposable validation)
- GitHub Actions self-hosted runner
- Canary-in-microVM deploy pattern

**Estimated Time:** 2-3 hours

**Steps:**
1. Add microvm.nix input to flake.nix
2. Create test microVM config
3. Add microVM to CI workflow
4. Test canary deploy pattern

**Documentation:** microvm-integration-plan.md

## Track C: Three-Plane Documentation

**Status:** NOT STARTED

**Objective:** Document architecture decisions and runbooks

**Deliverables:**
- Architecture diagrams (three-plane model)
- Decision log (why microVM vs Docker, etc.)
- Migration runbooks (how to move workloads)
- Troubleshooting guides

**Estimated Time:** 1-2 hours

## Dependencies

| Phase | Prerequisites | Blocks |
|-------|---------------|--------|
| Phase 0 | None | Phase 1 |
| Phase 1 | Phase 0 | Track A, B, C |
| Track A | Phase 1 | Production gateway |
| Track B | Phase 1 | CI microVM testing |
| Track C | Phase 1 | Complete documentation |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| nix-mineral breaks gaming | HIGH | Use compatibility preset, test before deploy |
| Gateway migration breaks AI | HIGH | Test in dev namespace first |
| microVM nested virt issues | MEDIUM | Check hardware support first |
| Garnix CI failures | MEDIUM | Start with hermes-agent only |

## Success Criteria

- ✅ All hosts build without errors
- ✅ nix-mineral enabled on zephyr
- ⏳ Garnix CI running on all repos
- ⏳ Gateway migrated to K8s
- ⏳ microVM CI tests passing
- ⏳ Complete three-plane documentation

## References

- **Phase 0:** PHASE-0-SECURITY-BASELINE.md
- **Phase 1:** PHASE-1-CICD-SAFETY.md
- **Track A:** k8s-gateway-migration-plan-v2.md
- **Track B:** microvm-integration-plan.md
- **nix-mineral:** nix-mineral-research.md
- **Cluster context:** CLAUDE.md, AGENTS.md

---

**Last Updated:** 2026-04-23
**Current Phase:** 0 Complete → 1 Next
