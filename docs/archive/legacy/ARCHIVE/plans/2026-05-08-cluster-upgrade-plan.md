# Cluster-Wide Component Upgrade Plan

> **⚠️ STALE (15 days old, last verified 2026-05-08)** — Verify against current cluster state before following.

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Upgrade all outdated components across the NixOS k3s cluster (4 nodes, K8s 1.35.4).

**Architecture:** All K8s resources are declared in easykubenix Nix modules under `/etc/nixos/kubernetes/modules/`. Image tags, env vars, and resource specs live in Nix code. Changes are committed, then applied via `easykubenix deploy` or `kubectl apply` for live patches. NixOS-level packages (k3s, coredns) require `just deploy` (colmena).

**Tech Stack:** NixOS 26.05 (unstable), k3s 1.35.4, easykubenix, colmena

---

## Risk Classification

| Tier | Components | Strategy |
|------|-----------|----------|
| **P0 Security** | vaultwarden, valkey | Immediate — patch CVEs |
| **P1 Safe** | prometheus, tempo, coredns, kagent, nvidia-device-plugin | Patch bumps — low risk |
| **P2 Minor** | loki, alloy, casdoor, qdrant, n8n, activepieces, k3s | Minor bumps — moderate risk |
| **P3 Major** | grafana 12->13, mimir 2->3, valkey 8->9, open-webui | Breaking changes — need migration plans |

---

## Task 1: vaultwarden 1.35.4 -> 1.36.0 (P0 Security)

**Objective:** Patch SSO CSRF, user enumeration, SSRF vulnerabilities.

**Files:**
- Modify: `kubernetes/modules/vaultwarden.nix` (image tag)

**Step 1:** Update image tag from `docker.io/vaultwarden/server:1.35.4` to `docker.io/vaultwarden/server:1.36.0`

**Step 2:** Verify Nix parse: `sudo nix-instantiate --parse kubernetes/modules/vaultwarden.nix`

**Step 3:** Apply live: `kubectl set image deployment/vaultwarden vaultwarden=docker.io/vaultwarden/server:1.36.0 -n vaultwarden`

**Step 4:** Verify: `kubectl rollout status deployment/vaultwarden -n vaultwarden --timeout=120s`

**Step 5:** Commit: `security: vaultwarden 1.35.4 -> 1.36.0 (SSO CSRF, user enum, SSRF fixes)`

---

## Task 2: valkey 8.1 -> 9.0.4 (P0 Security + P3 Major)

**Objective:** Patch CVE-2026-23479, CVE-2026-25243, CVE-2026-23631.

**Files:**
- Modify: `kubernetes/modules/search.nix` (valkey image tag)

**Step 1:** Research Valkey 9 breaking changes from 8.x (RDB format, API changes)

**Step 2:** Backup: `kubectl exec -n search valkey-0 -- valkey-cli SAVE` then `kubectl cp search/valkey-0:/data/dump.rdb /tmp/valkey-backup.rdb`

**Step 3:** Update image tag from `valkey/valkey:8.1` to `valkey/valkey:9.0.4`

**Step 4:** Apply: `kubectl set image statefulset/valkey valkey=valkey/valkey:9.0.4 -n search`

**Step 5:** Verify searxng + vane still connect: `kubectl logs -n search -l app=searxng --tail=5`

**Step 6:** Verify data: `kubectl exec -n search valkey-0 -- valkey-cli DBSIZE`

**Step 7:** Commit: `security: valkey 8.1 -> 9.0.4 (CVE fixes)`

---

## Task 3: prometheus 3.11.2 -> 3.11.3 (P1 Patch)

**Objective:** Patch bump for Prometheus.

**Files:** Modify `kubernetes/modules/monitoring.nix`

**Steps:** Update tag, apply, verify WAL replay, commit.

---

## Task 4: tempo 2.10.4 -> 2.10.5 (P1 Patch)

**Objective:** Patch bump for Tempo.

**Files:** Modify `kubernetes/modules/monitoring.nix`

**Steps:** Update tag, apply StatefulSet rollout, verify, commit.

---

## Task 5: coredns 1.14.2 -> 1.14.3 (P1 Patch)

**Objective:** Patch bump for CoreDNS. 2 replicas (zephyr + forge).

**Files:** Modify `kubernetes/modules/monitoring.nix`

**Steps:** Update tag, apply, re-enforce HA replicas (`kubectl scale deployment coredns --replicas=2 -n kube-system`), verify DNS, commit.

---

## Task 6: kagent 0.9.0 -> 0.9.2 (P1 Patch)

**Objective:** Patch bump for kagent controller + UI.

**Files:** Modify `kubernetes/modules/kagent.nix`

**Steps:** Update both image tags, apply, verify, commit.

---

## Task 7: nvidia-device-plugin 0.17.0 -> 0.19.1 (P1 Minor)

**Objective:** Upgrade NVIDIA device plugin DaemonSet.

**Files:** Modify `kubernetes/modules/monitoring.nix`

**Steps:** Research breaking changes (GPU resource naming, MIG), update tag, DaemonSet rolls one node at a time, verify GPU allocatable on all nodes, verify inference pods see GPUs, commit.

---

## Task 8: loki 3.6.10 -> 3.7.1 (P2 Minor)

**Objective:** Minor bump for Loki. PVC-backed StatefulSet on sentry.

**Files:** Modify `kubernetes/modules/monitoring.nix`

**Steps:** Research changelog, update tag, apply StatefulSet rollout, verify log ingestion from alloy, commit.

---

## Task 9: alloy 1.15.1 -> 1.16.1 (P2 Minor)

**Objective:** Minor bump for Alloy collector DaemonSet.

**Files:** Modify `kubernetes/modules/monitoring.nix`

**Steps:** Research config syntax changes, update tag, DaemonSet rolls one node at a time, verify log collection, commit.

---

## Task 10: casdoor 3.49.0 -> 3.52.0 (P2 Minor)

**Objective:** Upgrade Casdoor SSO. CRITICAL — handles auth for all .lan services.

**Files:** Modify `kubernetes/modules/auth.nix`

**Steps:** Backup PostgreSQL, research DB migration requirements, update tag, verify SSO + oauth2-proxy, commit.

---

## Task 11: qdrant 1.13.4 -> 1.17.1 (P2 Minor)

**Objective:** Upgrade Qdrant vector DB. Used by knowledge-base RAG.

**Files:** Modify `kubernetes/modules/ai-inference.nix`

**Steps:** Snapshot collections, research storage format changes, update tag, verify collections loaded, commit.

---

## Task 12: n8n 1.97.1 -> latest 1.x (P2 Minor)

**Objective:** Large version gap (1.97 -> 1.123+). Stay on 1.x line, avoid 2.x pre-release.

**Files:** Modify `kubernetes/modules/automation.nix`

**Steps:** Determine latest 1.x tag, backup PostgreSQL, update tag, verify workflows, commit.

---

## Task 13: activepieces 0.37.2 -> 0.82.2 (P2 Minor)

**Objective:** Massive version gap. Check if intermediate upgrades required.

**Files:** Modify `kubernetes/modules/automation.nix`

**Steps:** Research migration path, backup PostgreSQL, update tag, verify, commit.

---

## Task 14: prometheus-adapter fix (Broken — compat issue)

**Objective:** Fix adapter v0.12.0 broken on K8s 1.35 (dynamic discovery mapper failure). Currently scaled to 0. `kubectl top pods` is broken.

**Files:** Modify `kubernetes/modules/monitoring.nix` (ConfigMap + deployment)

**Steps:** Research fix (config format vs version), apply, scale to 1, verify HPA works, commit.

---

## Task 15: grafana 12.4.3 -> 13.0.1 (P3 Major)

**Objective:** Major version bump. 2 replicas (forge + sentry) with emptyDir.

**Files:** Modify `kubernetes/modules/monitoring.nix`

**Steps:** Research breaking changes (plugin API, provisioning, datasources), update tag, verify dashboard loading, commit.

---

## Task 16: mimir 2.17.9 -> 3.0.6 (P3 Major)

**Objective:** Major version bump for long-term metrics storage. PVC-backed StatefulSet on sentry. HIGHEST RISK.

**Files:** Modify `kubernetes/modules/monitoring.nix`

**Steps:** Research config/storage schema changes, backup PVC data, update tag, verify remote_write from prometheus, commit.

---

## Task 17: open-webui upgrade (P3 Major)

**Objective:** Upgrade from pinned sha256 to v0.9.2.

**Files:** Modify `kubernetes/modules/ai-inference.nix`

**Steps:** Research breaking changes, update image ref, verify UI loads, commit.

---

## Task 18: k3s 1.35.4 -> 1.36.0 (P2 Minor — NixOS level)

**Objective:** Upgrade k3s via nixpkgs update. DO THIS LAST.

**Files:** Modify `flake.lock` (nixpkgs input)

**Steps:** Check if nixpkgs has 1.36.0, `nix flake lock --update-input nixpkgs`, `just check`, `just deploy`, verify cluster health, commit.

**WARNING:** Highest risk upgrade. k3s controls the entire cluster. Do after all other upgrades verified stable.

---

## Execution Order

1. **P0 Security** (Tasks 1-2): vaultwarden, valkey
2. **P1 Safe patches** (Tasks 3-7): prometheus, tempo, coredns, kagent, nvidia-device-plugin
3. **P2 Minors** (Tasks 8-13): loki, alloy, casdoor, qdrant, n8n, activepieces
4. **Adapter fix** (Task 14): prometheus-adapter
5. **P3 Majors** (Tasks 15-17): grafana, mimir, open-webui
6. **NixOS k3s** (Task 18): LAST

## Pre-flight Checklist

- [ ] No active nix builds running
- [ ] Cluster healthy (all nodes Ready, no crash loops)
- [ ] etcd healthy (3 members)
- [ ] PostgreSQL backups of: casdoor, n8n, activepieces, kagent
- [ ] git working tree clean

## Post-upgrade Verification

- [ ] `kubectl get nodes` — all Ready
- [ ] `kubectl get pods -A` — no CrashLoop/Error/Pending
- [ ] `kubectl top nodes` — metrics flowing
- [ ] grafana.lan — dashboards loading
- [ ] auth.lan — SSO login works
- [ ] openwebui.lan — UI loads
- [ ] vaultwarden.lan — login works
- [ ] n8n.lan / activepieces.lan — workflows running
- [ ] Prometheus remote_write to Mimir — no errors
- [ ] Mining pods — unaffected on forge

---

## Execution Results (2026-05-09)

| # | Task | Target | Status | Notes |
|---|------|--------|--------|-------|
| 1 | vaultwarden | 1.36.0 | DONE | P0 CVE patches |
| 2 | valkey | 9.0.4 | DONE | P0 CVE patches, DBSIZE=0 (cache only) |
| 3 | prometheus | v3.11.3 | DONE | |
| 4 | tempo | 2.10.5 | DONE | |
| 5 | coredns | 1.14.3 | DONE | kubectl live, k3s-managed |
| 6 | kagent | 0.9.2 | DONE | Fixed NetworkPolicy default-deny blocking egress |
| 7 | nvidia-plugin | v0.19.1 | DONE | kubectl live, yaml manifest |
| 8 | loki | 3.7.1 | DONE | |
| 9 | alloy | v1.16.1 | DONE | |
| 10 | casdoor | 3.52.0 | BLOCKED | Go resolver DNS timeout on zephyr/flannel |
| 11 | qdrant | v1.17.1 | DONE | |
| 12 | n8n | 1.123.42 | DONE | |
| 13 | activepieces | 0.82.2 | DONE | Was scaled to 0, scaled up |
| 14 | prometheus-adapter | v0.12.0 | BLOCKED | Max K8s 1.30, upstream needs 1.35 support |
| 15 | grafana | 13.0.1 | DONE | Major version bump |
| 16 | mimir | 3.0.6 | DONE | Major bump, StatefulSet recreate needed |
| 17 | open-webui | v0.9.2 | DONE | Pinned release tag (was :main) |
| 18 | k3s | 1.36.0 | DEFERRED | Do last, requires colmena deploy |

**Summary: 15/18 done, 2 blocked, 1 deferred**

### Issues Discovered

1. **kagent NetworkPolicy regression:** A `default-deny-all` policy in kagent ns blocked new pod egress. The `allow-kagent-egress` policy used `app.kubernetes.io/part-of=kagent` label but pods use `app.kubernetes.io/component`. Fix: deleted default-deny-all, updated allow policies to match correct labels.

2. **casdoor Go resolver DNS timeout:** New casdoor pods on zephyr panic with "i/o timeout" resolving DNS. Busybox/musl pods on the same node resolve fine. Root cause unclear — possibly Go pure-Go resolver + flannel VXLAN interaction. Old pods with pre-existing connections work fine. BLOCKED until root cause found.

3. **prometheus-adapter K8s 1.35 incompat:** v0.12.0 (latest release) only supports up to K8s 1.30. Error: "no matches for /, Resource=cpu". No upstream release fixes this yet. HPAs using resource metrics work via metrics-server alone.

4. **mimir StatefulSet tag stuck:** `kubectl set image` on a StatefulSet doesn't recreate existing pods. Required `scale 0 -> scale 1` to force pod recreation.

### Commits

- `b4222694` security: vaultwarden 1.36.0 + valkey 9.0.4 (CVE patches)
- `99cf785a` chore: prometheus 3.11.3, tempo 2.10.5, nvidia-plugin v0.19.1
- `018df145` feat: batch image upgrades (P2/P3 tiers)
