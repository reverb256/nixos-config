# Session optimization and scope report

> **Last Verified:** 2026-07-30
> **Repository:** `reverb256/nixos-config`
> **Branch observed:** `main`
> **Scope:** This session's Nix architecture review, Nexus dispatcher work,
> easykubenix audit, repository optimization, and GitHub issue reconciliation.
> **Method:** read-only source inspection, static searches, prior-report review,
> direct GitHub issue queries with `gh`, and independent architecture review.
> **No deployment, build, host switch, SSH mutation, or GitHub mutation was
> performed while producing this report.**

## Executive decision

Do not run another broad modernization sprint. The repository has accumulated
several partially overlapping epics and multiple deployment/configuration paths.
The best optimization is **scope reduction plus stronger gates**, not more
frameworks.

Use this operating rule:

> **Stabilize one path, prove it, then migrate one ownership boundary. Do not
> start a second architecture while the first is still ambiguous.**

The recommended order is:

1. **Protect the current system:** validate and land the Nexus dispatcher work;
   make CI and deployment fail closed; resolve current security/build blockers.
2. **Choose architecture decisions:** collapse duplicate K3s HA issues, DNS
   issues, secretspec migration issues, and easykubenix migration scope.
3. **Migrate by boundary:** move one active Kubernetes service family at a time,
   with generated-object validation and rollback evidence.
4. **Only then optimize throughput and platform features:** builder registry,
   cache hardening, resilience, agent orchestration, and broad refactors.

## What this session accomplished

### 1. Build architecture was clarified

- The Nix system target remains generic `x86_64-linux`; there is no global
  x86-64-v3 build.
- Selected packages may use `-march=x86-64-v3`; this is package-specific.
- `big-parallel` is a builder feature label, not an architecture, CPU tuning
  flag, or thread count.
- Zephyr is intentionally a light authoring/dispatch host with `max-jobs = 0`.
- Nexus is the intended primary builder and deployment dispatcher.
- Sentry is a secondary builder; Forge is intentionally excluded because it is
  the GPU/mining host.

Relevant sources:

- `modules/system/distributed-builds.nix`
- `modules/system/nix-distributed-builders.nix`
- `machines`
- `flake.nix`
- `AGENTS.md`
- `knowledge.md`

### 2. Nexus dispatcher architecture was implemented in the worktree

The session added or changed the dispatcher path so that:

- `just deploy` routes through `scripts/deploy/nexus-dispatch.sh`.
- synchronous and disconnect-safe asynchronous modes share one executor;
- Nexus refreshes `/etc/nixos` to `origin/main` before building;
- Nexus activates itself locally and reaches remote targets explicitly;
- Zephyr is the public dispatch/source-of-truth host;
- duplicate deploy sessions are refused;
- async attach/log/stop helpers operate on Nexus;
- normal `colmena-deploy` recipes route through the dispatcher;
- direct deployment remains an explicitly named emergency path.

Important worktree condition:

- `scripts/deploy/nexus-dispatch.sh` is still untracked in the observed
  worktree.
- The dispatcher must be committed and pushed to `origin/main` before any real
  deployment. Nexus resets to `origin/main`; an untracked local script will not
  exist there.
- The dispatcher changes were syntax/diff reviewed, but a full flake/Colmena
  build and live dry-run were intentionally not performed.

### 3. The Nix/easykubenix audit produced a prior technical report

`docs/NIX-EASYKUBENIX-DEEP-AUDIT-2026-07-30.md` contains the detailed evidence
and primary references. Its central findings were:

- duplicate builder definitions;
- permissive Nix trust settings;
- cache endpoint/signing-key ownership requiring verification;
- CI paths that downgrade failures to warnings;
- direct GitHub deployment bypassing the Nexus dispatcher;
- source-text Kubernetes tests instead of evaluated-object tests;
- ambiguous raw YAML versus easykubenix ownership;
- mutable image identity and incomplete workload policy coverage;
- underuse of easykubenix transformers, generators, and API-server validation.

This report is the **scope and sequencing companion** to that technical audit;
it does not duplicate every code-level finding.

## Current worktree state

At the end of the session, the worktree contained the prior dispatcher/docs
changes plus three untracked artifacts:

- modified: `AGENTS.md`
- modified: `README.md`
- modified: `colmena.nix`
- modified: `docs/LIVE/ARCHITECTURE.md`
- modified: `flake.nix`
- modified: `hosts/metadata.nix`
- modified: `hosts/metadata/*.json`
- modified: `justfile`
- modified: `knowledge.md`
- modified: `machines`
- modified: `scripts/preflight-check.sh`
- untracked: `scripts/deploy/nexus-dispatch.sh`
- untracked: `docs/NIX-EASYKUBENIX-DEEP-AUDIT-2026-07-30.md`
- untracked: this report

The snapshot therefore contains **three untracked artifacts**; the dispatcher
and prior audit predate this report, while this report is the newly created
session artifact.

This report does not claim those changes are ready to deploy. The correct next
step is review/staging/commit/push followed by full non-destructive validation,
not a live switch from the current uncommitted tree.

## GitHub issue reconciliation

### Tracker state

The direct GitHub queries established that issues **#325–#330 are closed**.
The fresh decision-relevant issue refresh was run at
**2026-07-30T17:22:56-05:00**; statuses below are a point-in-time snapshot and
should be rechecked before any GitHub mutation or deployment decision.
They should be treated as historical evidence of recurring failure classes, not
as current open work:

- #325 Forge PAM helper failure — closed 2026-07-27
- #326 Forge AMD GPU fatal initialization — closed 2026-07-27
- #327 Forge CUPS permissions — closed 2026-07-27
- #328 Zephyr systemd-oomd/sysctl keys — closed 2026-07-27
- #329 Zephyr/Forge utility service failures — closed 2026-07-27
- #330 runner zombie + secretspec PATH/drift — closed 2026-07-27

The current open backlog is much broader than the issues visible in the earlier
summary. The most relevant current open issues observed were:

| Issues | Current theme | Scope implication |
|---|---|---|
| #332 | Standalone Home Manager activation / starship warning | Small, isolated UX/HM slice; do not mix into infra stabilization |
| #324, #306 | Secretspec end-to-end migration and host credentials | One security migration epic; verify current implementation before adding features |
| #323, #320 | Multi-node K3s / HA control planes | Likely overlapping or nested epics; compare full bodies and choose one canonical issue or explicit phase relationship |
| #322, #319 | Unbound/`searxng.lan` stale DNS | Duplicate symptom/fix area; merge into one DNS closure issue |
| #321 | SearXNG tolerations and HPA | Narrow workload policy slice; can proceed independently after DNS ownership is clear |
| #317 | Declarative nim-proxy/Hermes configuration | Separate service-declaration epic; not a prerequisite for dispatcher landing |
| #316, #315, #314, #313 | nim-proxy streaming, metrics, per-model control, concurrency | One ordered nim-proxy feature stack, not four parallel projects |
| #312 | Forge Colmena bad machine specification | Directly overlaps builder/dispatcher validation; highest deployment relevance |
| #311 | Replace raw Kubernetes YAML with easykubenix | Direct overlap with this session; based on the available issue summary, narrow it to active ownership boundaries after a fresh full-body review |
| #310 | Pre-commit eval gate | Foundational CI slice; should precede broad migration work |
| #309, #308 | Pure evaluation and local tarball/flake-input cleanup | Foundational reproducibility work; sequence before new generated outputs |
| #307 | Aspect-based module reorganization | Broad refactor; defer until correctness work is closed |
| #280 | Nexus age-key mismatch and wait-online activation issue | Operational prerequisite for reliable deployment; verify before dispatcher rollout |
| #266 | Hermes deployment consolidation | Existing service migration; coordinate with #317, avoid duplicate configuration work |
| #248 | Local K3s registry | Supports local-image reproducibility and easykubenix migration |
| #246 | Chrony/static NTP | Cluster prerequisite for HA/K3s reliability |
| #243 | Nexus rescue closure transfer and activation | Break-glass deployment/recovery prerequisite |
| #242 | Preservation/BTRFS recovery standardization | Storage/recovery epic; do not combine with K8s migration |
| #220 | External HA etcd | Alternative/next-level datastore architecture; do not pursue simultaneously with embedded K3s HA decision |
| #213 | nix-csi/K3s proxy/BTRFS exhaustion | Infrastructure blocker for stateful workloads and resilience |
| #211 | Single-node failover | Umbrella resilience goal; should consume outcomes from K3s, storage, registry, and database work |
| #144 | Cluster security hardening | Security gate/umbrella; map concrete controls rather than duplicating #10/#11/#12 |
| #12, #11, #10 | Resource limits, PSA labels, image pinning | Older narrow security issues; reconcile status and ownership with #144 and #311 |

Issue URLs:

- <https://github.com/reverb256/nixos-config/issues/332>
- <https://github.com/reverb256/nixos-config/issues/324>
- <https://github.com/reverb256/nixos-config/issues/323>
- <https://github.com/reverb256/nixos-config/issues/322>
- <https://github.com/reverb256/nixos-config/issues/321>
- <https://github.com/reverb256/nixos-config/issues/320>
- <https://github.com/reverb256/nixos-config/issues/319>
- <https://github.com/reverb256/nixos-config/issues/317>
- <https://github.com/reverb256/nixos-config/issues/316>
- <https://github.com/reverb256/nixos-config/issues/315>
- <https://github.com/reverb256/nixos-config/issues/314>
- <https://github.com/reverb256/nixos-config/issues/313>
- <https://github.com/reverb256/nixos-config/issues/312>
- <https://github.com/reverb256/nixos-config/issues/311>
- <https://github.com/reverb256/nixos-config/issues/310>
- <https://github.com/reverb256/nixos-config/issues/309>
- <https://github.com/reverb256/nixos-config/issues/308>
- <https://github.com/reverb256/nixos-config/issues/307>
- <https://github.com/reverb256/nixos-config/issues/306>
- <https://github.com/reverb256/nixos-config/issues/280>
- <https://github.com/reverb256/nixos-config/issues/266>
- <https://github.com/reverb256/nixos-config/issues/248>
- <https://github.com/reverb256/nixos-config/issues/246>
- <https://github.com/reverb256/nixos-config/issues/243>
- <https://github.com/reverb256/nixos-config/issues/242>
- <https://github.com/reverb256/nixos-config/issues/220>
- <https://github.com/reverb256/nixos-config/issues/213>
- <https://github.com/reverb256/nixos-config/issues/211>
- <https://github.com/reverb256/nixos-config/issues/144>
- <https://github.com/reverb256/nixos-config/issues/12>
- <https://github.com/reverb256/nixos-config/issues/11>
- <https://github.com/reverb256/nixos-config/issues/10>

### Issue management observations

- No GitHub milestones currently exist. This makes priority and sequencing
  harder to see than necessary.
- Useful labels exist (`p0`, `p1`, `priority:*`, `epic`, `agent-ready`, `infra`,
  `security`, `cleanup`), but the open backlog has no visible milestone-based
  delivery boundary.
- Issue #311 explicitly references #306, #307, and #309, confirming that the
  easykubenix migration is coupled to secretspec/pure-evaluation/module-shape
  work.
- #323 and #320 both describe multi-node K3s control-plane/HA outcomes. They
  are **candidate overlaps**, not confirmed duplicates; compare their full
  bodies and decide whether one is cluster formation and the other HA
  hardening, or whether they should be consolidated.
- #319 and #322 describe the same Unbound stale-DNS symptom family. Compare
  their full bodies, then make one the canonical fix and close the other as a
  duplicate or convert it into a verification subtask.
- #313–#316 are one nim-proxy implementation sequence. Splitting them is useful
  for review, but not for independent roadmap prioritization.
- #10/#11/#12 overlap the newer security umbrella #144 and the easykubenix work
  in #311. They need a status/reopen/close reconciliation rather than another
  independent remediation sprint.

## Scope model: four lanes, not one mega-project

### Lane A — Safety and deployability

**Goal:** make the current NixOS fleet safe to evaluate and deploy.

Includes:

- land and validate the Nexus dispatcher;
- resolve #312 machine specification behavior;
- verify #280 key/wait-online activation blockers;
- complete the required CI/pre-commit gate (#310);
- make deployment workflow and `just deploy` use one path;
- verify cache endpoint/signing ownership before changing `require-sigs`;
- keep recovery path #243 usable.

Exit criteria:

- `scripts/deploy/nexus-dispatch.sh` is tracked only after the pending worktree
  change is reviewed, committed, and merged into `main`;
- `nix flake check` passes from a clean checkout;
- all four host evaluations succeed on the intended builder;
- Colmena dry/build validation succeeds for Nexus, Forge, and Sentry;
- dispatcher sync/async/target guards pass offline;
- one controlled deployment to one non-critical target succeeds;
- rollback and rescue instructions are tested/read-only validated;
- no normal CI/workflow path directly bypasses Nexus.

**Do not include:** K3s HA redesign, broad YAML migration, nim-proxy features,
agent orchestration, or cosmetic Home Manager changes.

### Lane B — Secrets and trust

**Goal:** one auditable runtime-secret path and a defensible Nix trust boundary.

Includes:

- reconcile #306 and #324 into one secretspec migration issue;
- verify all provider/fork/age-key prerequisites;
- eliminate silent dotenv fallback for required sops-backed values;
- verify the cache endpoint/key ownership;
- restore signature verification and narrow trusted users only after the cache
  gate passes;
- close obsolete agenix/sops-nix references deliberately, not by search/replace.

Exit criteria:

- production secretspec check proves the intended provider path, not fallback;
- all required `/run/secrets/*` files are generated by the declarative service;
- no required secret has an accidental plaintext or dotenv masking path;
- cache artifacts verify with trusted signatures;
- `trusted-users` has no wildcard and `require-sigs` is true in production;
- migration docs identify the one remaining secret mechanism and a removal date
  for compatibility code.

**Do not include:** a new secrets provider, new external secret service, or
large application-level provider rewrites.

### Lane C — Kubernetes ownership and policy

**Goal:** make generated Kubernetes state authoritative and safe without
attempting a one-shot 311-file migration.

Includes:

- narrow #311 to one active service family or namespace;
- use the vendored easykubenix evaluator and API-server validation;
- replace source-text heuristics with evaluated-object checks;
- reconcile #10/#11/#12 into #144 or a current policy epic;
- define standard versus privileged/GPU/hostPath/local-image exceptions;
- pin image identities and fix endpoint/DNS drift;
- use #248 local registry work only where it supports reproducible local images.

Recommended first migration boundary:

1. choose a small, non-control-plane service family with clear ownership;
2. generate its Namespace/Deployment/Service/NetworkPolicy from easykubenix;
3. remove its duplicate raw YAML deployment path;
4. validate against ephemeral API server and kubeconform;
5. deploy only after object identity and rollback are proven.

Exit criteria:

- every migrated object has one source of truth;
- generated objects pass API-server validation;
- standard workloads carry resources, probes, security context, labels, and
  deliberate scheduling;
- exceptions are machine-readable with owner/reason;
- raw YAML inventory has an owner and lifecycle state;
- no `latest` image remains without an explicit local-development exception;
- service DNS/ports resolve against the generated registry.

**Do not include:** all raw YAML, CRDs, GPU device plugins, K3s control-plane
changes, or NetworkPolicy redesign in the first migration.

### Lane D — Features and resilience

**Goal:** improve capability only after foundation lanes are stable.

Includes later:

- #313–#316 as one ordered nim-proxy feature epic;
- #317 and #266 as one declarative Hermes/nim-proxy service configuration epic;
- #242 storage/preservation hardening;
- #213 nix-csi/BTRFS recovery;
- #246 time synchronization;
- #323/#320 selected K3s HA plan;
- #220 external etcd only if embedded K3s HA is insufficient;
- #211 single-node resilience after registry/storage/database topology is known;
- #332 standalone Home Manager activation as an isolated quality-of-life task.

**Do not include:** all of these in one milestone. Each has a different failure
surface and validation method.

## Recommended issue consolidation

### Consolidate into canonical epics

1. **Deploy safety epic:** #312, #280, #243, the Nexus dispatcher work, and
   the relevant parts of #310.
2. **Secrets/trust epic:** #306 + #324, with cache verification and Nix trust
   hardening as explicit subtasks.
3. **K3s topology decision:** compare #323 and #320 fully, then either
   consolidate them or record an explicit cluster-formation → HA phase
   relationship. Keep #220 as a separate option analysis until the
   embedded-etcd/control-plane decision is made.
4. **DNS closure:** compare #319 and #322 fully, then designate one canonical
   fix and make the other a duplicate or verification subtask.
5. **Kubernetes policy/migration:** perform a fresh complete review of #311
   before consolidating it with #10/#11/#12/#144; use #248 as an enabling
   subtask for local-image reproducibility.
6. **Nim-proxy feature epic:** #313 + #314 + #315 + #316, ordered by runtime
   safety first.
7. **Hermes declarative services:** #266 + #317.
8. **Resilience/storage:** #211 + #213 + #242 + #246, but preserve separate
   implementation PRs and gates.

### Keep separate

- #332 standalone Home Manager activation: small and low-risk.
- #307 aspect-based module reorganization: broad refactor; defer until active
  breakages and ownership ambiguity are reduced.
- #308 local tarball pipeline cleanup and #309 pure-evaluation cleanup: these
  are foundation tasks, but should remain independently reviewable.
- #220 external etcd: architectural decision, not an automatic implementation
  dependency of K3s HA.

## Optimization principles for the codebase

### 1. Optimize for fewer authoritative paths

Current duplication is more expensive than raw line count:

- two distributed-builder modules;
- direct Colmena deployment alongside Nexus dispatch;
- raw YAML alongside easykubenix modules;
- multiple secret compatibility paths;
- duplicate issue epics for the same outcome;
- generated metadata mirrored manually in JSON/docs.

A useful optimization metric is:

> **Number of independently mutable paths that can change production behavior.**

Reduce that number before attempting module abstraction or performance tuning.

### 2. Optimize for failure detection before execution speed

The repository already has substantial build capacity. The more costly failures
have been wrong-target deploys, stale evaluation, syntax/configuration breaks,
missing secrets, and policy drift—not insufficient CPU.

Prioritize:

- clean-checkout evaluation;
- target/hostname assertions;
- generated artifact validation;
- signed cache verification;
- failure-injection tests;
- one deployment executor.

Only optimize evaluation/build throughput after recording a baseline for:

- host evaluation duration;
- easykubenix bundle evaluation duration;
- closure size;
- cache hit rate;
- deployment time by target.

### 3. Optimize for reversible slices

Every infrastructure PR should have:

- one ownership boundary;
- one explicit rollback path;
- one non-destructive validation command;
- one live health gate if deployment is later approved;
- no unrelated formatting/refactor churn.

Avoid combining a builder rewrite, K3s topology change, secrets migration, and
Kubernetes manifest migration in one PR.

### 4. Optimize issue tracking as an engineering system

Create milestones or equivalent project views for:

- `M0 Safety / deployability`
- `M1 Secrets / trust`
- `M2 Kubernetes ownership`
- `M3 K3s topology decision`
- `M4 Resilience / storage`
- `M5 Product features`

Use labels consistently:

- `epic` for outcome/decision issues;
- `agent-ready` only when acceptance criteria and files are known;
- `p0`/`p1` for operational severity, not broad importance;
- `cleanup` for deletion/deprecation work;
- `security` for threat-boundary changes;
- `blocked` or `needs-decision` for unresolved architecture choices.

Every epic should state:

- in-scope files and systems;
- explicit non-goals;
- dependencies;
- validation gate;
- rollback plan;
- exit condition;
- issues that it supersedes or absorbs.

## Concrete 30-day plan

### Days 0–3: freeze scope and protect the tree

- Do not deploy from the current untracked dispatcher tree.
- Review the dispatcher diff as one change set.
- Stage only the intended dispatcher/docs changes.
- Run syntax, parse, diff, and offline guard checks.
- Confirm current GitHub issue states before opening duplicates.
- Mark #312, #280, #243, #310 as deploy-safety dependencies.

### Days 3–7: deployability gate

- Run full `nix flake check` from the intended clean checkout.
- Run Colmena build/dry validation on Nexus for Nexus, Forge, and Sentry.
- Verify machine-file output and target hostname guards.
- Reconcile GitHub workflow direct deployment with the dispatcher.
- Validate one controlled target deployment only after the above pass.

### Week 2: secrets and trust

- Reconcile #306/#324 implementation status.
- Prove secretspec uses the intended sops provider rather than dotenv fallback.
- Verify cache endpoint, owner, port, key name, and signature behavior.
- Then narrow `trusted-users` and restore `require-sigs` in a staged PR.
- Remove or document obsolete agenix/sops compatibility paths.

### Week 3: one Kubernetes migration slice

- Reconcile #311 with #10/#11/#12/#144.
- Pick one low-risk active service family.
- Add evaluated-object contract tests and easykubenix API-server validation.
- Migrate, validate, and document only that family.
- Inventory all other raw YAML without migrating it yet.

### Week 4: architecture decisions, not implementation sprawl

- Decide whether #323 or #320 is canonical.
- Decide whether external etcd #220 is required or deferred.
- Define storage/resilience dependencies among #211/#213/#242/#246.
- Combine #313–#316 and #266/#317 into explicit feature sequences.
- Create milestones and close/merge duplicate issues.

## Definition of done for this session's optimization work

The repository is better scoped when all of the following are true:

- one normal deployment path exists;
- one builder registry is authoritative;
- one secrets migration path is explicit;
- one K3s topology decision is recorded;
- one DNS issue owns the SearXNG symptom;
- one Kubernetes migration epic owns policy/image/resource work;
- each migrated service has one manifest source of truth;
- required CI gates fail closed;
- every broad epic has explicit non-goals;
- current work is represented by milestones rather than an undifferentiated
  open-issue list;
- no live deployment is performed from untracked worktree state.

## Explicitly defer or cut

To prevent scope explosion, defer these until the foundation lanes close:

- broad aspect-based module reorganization (#307);
- all-at-once raw YAML migration (#311 as currently summarized; confirm the
  full issue body before final scope is set);
- external etcd (#220) before the K3s topology decision;
- single-node resilience claims (#211) before storage/registry/database reality
  is measured;
- full agent fleet-control automation (#297 and related historical issues);
- broad AI routing/memory/orchestration epics;
- cosmetic Home Manager improvements when a deployability blocker is open;
- builder micro-optimizations before cache/signature correctness is proven.

## Final recommendation

Treat the next engineering milestone as:

> **M0: Safe, reproducible, single-path deployment from a clean checkout.**

Its only deliverables should be dispatcher correctness, Colmena machine-spec
correctness, CI/pre-commit failure behavior, cache/trust verification, recovery
readiness, and the minimum secretspec gate needed to evaluate/deploy safely.

After M0, select exactly one of:

- **M1 Secrets/trust**, or
- **M2 one-service easykubenix migration**.

Do not begin K3s HA, external etcd, broad raw-YAML migration, and agent
orchestration concurrently. The fastest route to a more reliable codebase is to
remove competing paths and make each remaining path prove its invariants.
