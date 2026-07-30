# Nix-first + easykubenix deep audit

> **Last Verified:** 2026-07-30
> **Scope:** NixOS/flakes, distributed builds, Colmena deployment, easykubenix
> generation/validation, Kubernetes policy, CI/CD, and repository architecture.
> **Method:** source inspection, targeted static searches, vendored easykubenix
> inspection, and primary-source documentation research. No deployment, build,
> SSH mutation, or cluster switch was performed.
>
> This report supplements `docs/audit-2026-07-27.md`; it does not replace the
> incident and secrets findings recorded there.

## Executive summary

The repository has a strong declarative direction and already contains valuable
controls: a locked flake, a vendored easykubenix copy, generated Kubernetes
objects, explicit workload placement, admission policies, multiple validation
scripts, and the Nexus dispatcher design. The largest remaining risk is not a
lack of controls; it is that several controls are duplicated, heuristic, or
non-blocking.

The highest-leverage improvement is to make the existing architecture fail
closed:

1. **One builder configuration** — remove or quarantine the duplicate
   distributed-builder module and fix the active builder security posture.
2. **One deployment path** — make the Nexus dispatcher the only normal path,
   including GitHub Actions; retain direct Colmena only as an explicit,
   documented break-glass path.
3. **One Kubernetes source of truth** — distinguish generated easykubenix
   resources from legacy/raw YAML and stop normal deployment from applying
   both independently.
4. **Structural validation** — validate evaluated manifests, not source text;
   run easykubenix's API-server validation and kubeconform in CI; make failures
   fail the job.
5. **Policy as reusable Nix** — use easykubenix transformers/generators or
   shared constructors to inject labels, resources, security context, probes,
   scheduling, and rollout defaults consistently.
6. **Explicit exceptions** — GPU/device-plugin/hostPath/privileged workloads
   should carry machine-checkable exception metadata and narrowly scoped policy
   exemptions.

## Priority table

| Priority | Workstream | Why it matters | First slice |
|---|---|---|---|
| P0 | Builder security and duplicate config | Builds/substitutes are trust boundaries; current settings are overly permissive and duplicated | Remove the dormant module or make it assert-disabled; verify cache signing first, then restore signature verification; replace wildcard trusted users |
| P0 | CI fail-closed behavior | The workflow configuration can currently allow failed builds, failed docs checks, failed security scans, or failed tests to finish as warnings | Delete non-blocking wrappers from correctness/security gates and add explicit allowlisted experimental jobs |
| P0 | Deployment-path convergence | GitHub Actions still performs direct Colmena deployment and imperative mining control outside the Nexus dispatcher | Route workflow deployment through the checked-in dispatcher or retire the workflow path |
| P1 | Evaluated-manifest policy tests | Text heuristics miss generated objects and produce false positives/negatives | Build each easykubenix output, parse YAML/JSON, and assert object-level invariants |
| P1 | easykubenix validation gate | The vendored implementation already provides ephemeral API-server validation, but CI mostly uses kubeconform/source checks | Expose `validationScript` as a flake check/app and run it for every active manifest bundle |
| P1 | Kubernetes source-of-truth boundary | 32 easykubenix modules coexist with 311 non-archived raw YAML files and imperative `kubectl apply` recipes; the count does not prove all files are deployed | Classify raw YAML as generated, bootstrap, vendor, or legacy; block unclassified deployment |
| P1 | Image identity policy | Several active easykubenix modules still use mutable tags, including `latest` | Require digest or centrally declared immutable version; permit local `imagePullPolicy=Never` only with an exception |
| P2 | Shared workload constructors | Similar security/resource/probe/rollout blocks are repeated and drift | Introduce small `mkDeployment`/`mkContainer` helpers and a policy transformer |
| P2 | API/port/endpoint registry | Ports and service DNS are partly centralized but raw manifests still hardcode node IPs | Generate service references from cluster constants and validate endpoint existence |
| P2 | Test architecture | Many tests inspect source strings and several are not wired into required CI | Replace with evaluated assertions and a single machine-readable test runner |
| P3 | Documentation and lifecycle | Existing docs are useful but stale warnings and duplicate registries create maintenance cost | Generate architecture/host/port/build-farm docs from Nix data |

## Confirmed repository findings

### A. Nix-first and build architecture

#### A1. Duplicate distributed-builder implementations

Two modules describe distributed builds:

- `modules/system/distributed-builds.nix` is imported by both
  `modules/default.nix` and `modules/common-host.nix` and generates
  `/etc/nix/machines`.
- `modules/system/nix-distributed-builders.nix` defines a separate
  `nix.distributedBuilds-config` option and a separate `nix.builders` list.

The second module appears dormant, but it is dangerous dormant code: its SSH
configuration at `modules/system/nix-distributed-builders.nix:23-37` maps
`Host nexus` to `10.1.1.130` and `Host sentry` to `10.1.1.120`, which conflicts
with the repository's host registry (Nexus 10.1.1.120, Forge 10.1.1.130, Sentry
10.1.1.140). This is exactly the class of latent drift that becomes an incident
when someone re-enables the module.

**Recommendation:** choose one implementation. Prefer the generated
`/etc/nix/machines` path because it is already integrated with per-host
capacity and current-host exclusion. Delete the dormant module if its option
is unused, or make it a thin compatibility wrapper around one shared builder
attribute set. Add an evaluation assertion that every builder hostname maps to
the canonical cluster registry.

#### A2. Active Nix trust settings are too permissive

`modules/system/distributed-builds.nix:15-20` currently sets:

```nix
require-sigs = lib.mkForce false;
trusted-users = lib.mkForce [ "root" "*" "@wheel" ];
```

This weakens the default Nix trust boundary for every host using the module.
The configured cache and upstream keys exist, but the cache endpoint/ownership
needs verification first (see A2b below); there is no architectural reason to
leave signature verification globally disabled after that compatibility work.
The wildcard trusted-user entry also grants every local user administrative
Nix-daemon trust.

**Recommendation:** restore `require-sigs = true` after a staged compatibility
gate proves every configured substituter serves artifacts signed by a trusted
key; replace `"*"` with the minimum required service accounts/groups; keep
cache keys in one registry; and add a test that rejects wildcard trusted users
and disabled signature verification in production hosts. Validate the result
with a non-deploying builder/cache test before activation.

#### A2b. Cache endpoint and signing-key ownership require verification ⚠️ P1

`modules/system/distributed-builds.nix:25,34` configures the internal
substituter as `http://10.1.1.110:50000` while the module comments describe a
post-build upload to a “nexus cache” (`:111-113`). The configured key is named
`zephyr-cache-1` (`:46,55`), and the cache service modules also identify the
cache as Zephyr-owned. Other repository comments describe a Nexus cache. This
is not proof that the live cache is broken, but it is a source-of-truth and
trust-boundary mismatch that must be resolved before tightening `require-sigs`.

**Recommendation:** designate one canonical cache owner and endpoint; verify
that the endpoint serves the declared signing key; verify `nix copy` pushes to
the same service; then add an evaluation/integration check that endpoint,
service host, key name, and substituter configuration agree. Do not solve this
by disabling signature verification.

#### A3. Builder metadata and generated text can drift

The builder module has comments claiming broader system support while the
machine records currently advertise `x86_64-linux`. It also mixes generated
machine-file formatting, SSH protocol workarounds, per-builder timeouts, and
capacity policy in one large module.

**Recommendation:** define a typed `cluster.builders` attrset once, containing
hostname, address, systems, jobs, speed factor, features, protocol, and role.
Render `/etc/nix/machines`, Colmena `machines`, and documentation from it. Add
an assertion that all systems are valid, no builder is a workload-forbidden
host, and every address equals the canonical host registry.

#### A4. `big-parallel` is used correctly conceptually, but policy is implicit

`big-parallel` is a builder feature label, not an architecture target and not a
thread count. The repo correctly documents that distinction. However, there is
no repository-level test proving that derivations requiring `big-parallel` have
at least one reachable builder with that feature, or that ordinary derivations
are not accidentally made dependent on it.

**Recommendation:** add a small builder capability matrix test and document the
intended use of `meta.requiredSystemFeatures = [ "big-parallel" ]` only for
known memory/parallelism-heavy derivations. Keep the generic system target
`x86_64-linux`; do not turn `big-parallel` into an architecture abstraction.

#### A5. Flake evaluation is stronger than the CI contract

The repository has `flake.lock` and a configured `nix flake check --no-build`
step, but other CI stages deliberately downgrade failures:

- `ci.yml` makes pre-deploy validation non-blocking and converts documentation
  audit failure to a warning.
- The security scan uses `|| true`.
- `cache.yml` is explicitly non-blocking.
- `secretspec-build.yml` marks the Nix build `continue-on-error`.
- `ci-test-automation.yml` records test failures as warnings and does not exit
  non-zero; its flake check and local CI steps are also non-blocking.

These may be reasonable for optional observability/cache jobs, but they are not
reasonable for required correctness/security gates.

**Recommendation:** split jobs into:

- correctness/security gates that branch protection marks as required: parse,
  flake evaluation, tests, generated-manifest validation, security policy, host
  build/eval;
- optional: cache population, SARIF upload, advisory docs freshness, experimental
  fork builds.

Optional jobs must be visibly named `advisory`/`best-effort`; required jobs must
fail on command failure and publish a summary artifact.

#### A6. Source-text tests are not semantic tests

Examples include `tests/nixos-eval.nix`, `tests/options-consistency.nix`, and
`tests/k8s-manifest-validation.nix`. They inspect strings such as `namespace`,
`labels`, `image =`, `mkIf`, and `resources` rather than evaluating the NixOS
module or generated Kubernetes object graph. This creates known limitations:

- comments can satisfy a check;
- generated/defaulted fields are invisible;
- a resource can be present in source but attached at the wrong object path;
- a literal image tag can be legitimate or a mutable local image;
- one module can generate many objects, while the test counts only files.

`tests/k8s-manifest-validation.nix` is also not in the explicit required test
list in `.github/workflows/ci.yml`.

**Recommendation:** retain source checks only as cheap lint, but make them
advisory. Add evaluated tests that import `kubernetes/default.nix`, traverse
`manifestAttrs`/`generated`, and inspect each emitted object by kind and path.

### B. easykubenix architecture

#### B1. Vendoring easykubenix is defensible, but the update contract is manual

`vendor/easykubenix/README.vendor.md` pins commit
`88a025fc04889f25b702f79030c6220c3ec48f9b` and explains that vendoring avoids
GitHub fetch hangs. This improves offline evaluation and reproducibility, but
manual `rm/curl/tar` updates are not integrity-verifiable in the documented
workflow.

**Recommendation:** store upstream commit, source hash, license, and a small
vendoring verification script. The update script should download a tarball,
verify its hash, compare the expected upstream commit, and run the vendored
validation/demo before replacing the tree. Keep the vendored source isolated
from application modules.

#### B2. easykubenix has underused high-value primitives

The vendored implementation supports:

- `kubernetes.objects` grouped by namespace/kind/name;
- automatic `apiVersion`, `kind`, metadata name, and namespace;
- `apiMappings` generated from a pinned API-resource JSON file;
- `generators`, `transformers`, and `filters` over evaluated objects;
- `generated` and `generatedByPath` views;
- an ephemeral etcd + kube-apiserver `validationScript` followed by kubeconform;
- optional Helm import and Kluctl deployment integration.

The repository currently uses objects and named lists extensively, but most
cross-cutting policy is repeated in individual modules and CI validates the
combined YAML with kubeconform rather than running the vendored API-server
validation path for every bundle.

**Recommendation:** use one policy transformer for labels/ownership and one
constructor layer for standard workloads. Use generators for derived objects
such as PDBs or NetworkPolicies only where the ownership semantics are clear.
Keep exceptions explicit rather than hiding all behavior in a global transform.

#### B3. Admission policy and module policy are not yet aligned

`kubernetes/modules/infrastructure.nix` defines a deny policy requiring CPU and
memory requests/limits, `runAsNonRoot`, and no privilege escalation, but its
binding explicitly excludes namespaces such as `ai-inference`, `tailscale`,
and `nix-csi`. This may be intentional for privileged/GPU workloads, but it
also means the strongest policy does not cover a large portion of the cluster.
A separate resource-limits policy is only in `Audit` mode.

There are also concrete drift risks in active modules:

- `kubernetes/modules/hermes-workspace.nix` has no resources or security context,
  pins the pod to Zephyr, and hardcodes Zephyr service IPs (around `:21-61`).
- `kubernetes/modules/vane.nix:27` uses `ghcr.io/reverb256/vane:latest`.
- `kubernetes/modules/mcp-servers.nix:168` uses `localhost/qdrant-mcp:latest`
  with `imagePullPolicy = "Never"`; this needs an explicit local-image exception
  and immutable build identity.
- In the Grafana MCP object, `kubernetes/modules/mcp-servers.nix:94-106`
  places `securityContext` inside `resources`, which is not a Kubernetes
  container security-context location; the intended security context should be
  at pod or container level.
- `kubernetes/modules/infrastructure.nix:450-529` has a device-plugin object
  with `resources = {}` and privileged/hostPath behavior; it needs a documented
  system-workload exception rather than relying on broad namespace exclusions.

**Recommendation:** create a policy matrix:

| Class | Default policy | Required exception |
|---|---|---|
| ordinary service | restricted-style context, requests/limits, probes | none |
| AI/GPU | resources, probes, non-root where possible | GPU/privileged/hostPath reason + namespace |
| node/device plugin | system priority, host paths, privileged as required | component owner + capability reason |
| local development image | immutable local content digest or build ID | `imagePullPolicy=Never`, node/image contract |

Then test the evaluated object against the matrix.

#### B4. Raw YAML and generated Nix are too easy to confuse

The repository contains 32 easykubenix module files and 311 non-archived YAML
files under `kubernetes-manifests`/`k8s` by the audit count; this inventory count
does not establish that every file is deployed. The `justfile` still has
imperative `kubectl apply`/`kubectl delete` recipes for Mosaic assets, while
Nix/easykubenix has a boot auto-apply path and generated manifest outputs.
This is not automatically wrong, but it is a source-of-truth ambiguity.

**Recommendation:** classify every raw YAML directory as exactly one of:

1. generated artifact (never hand-edit);
2. bootstrap/CRD asset (explicit owner and lifecycle);
3. vendor/reference example (not deployed);
4. legacy migration candidate.

Add a manifest inventory with owner, namespace, deployment mechanism, and
whether pruning is safe. CI should reject a new deployable YAML file without an
inventory entry and should ensure no object identity is emitted by both paths.

#### B5. Image identity is inconsistent

Many images have immutable-looking version tags, but tags are not immutable
identity. The active easykubenix set includes `latest` images and several
unqualified images (`python:...`, `postgres:...`, `redis:...`, `registry:2`).
The raw-manifest audit also found `:latest` images despite a declared
latest-tag admission policy; whether that policy is bound and enforcing remains
unverified from this read-only source audit.

**Recommendation:** use `registry/repository@sha256:digest` for third-party
images where feasible. If tags are retained for local builds, centralize them
in a version registry and require a comment/attribute containing the source
revision and digest update date. Add a generated-manifest check that rejects
mutable tags except for a narrowly enumerated local-development exception.

### C. Deployment and GitOps

#### C1. The Nexus dispatcher design is good but not universal yet

The checked-in dispatcher makes Zephyr the authoring host and Nexus the build /
deployment executor. The normal `just deploy` recipes route through it. However,
`.github/workflows/deploy.yml` still builds on the runner, stops/starts mining
with `systemctl` (`:63-66` and `:159-165`), and invokes Colmena directly
(`:101-112`). This creates a second production path with different preflight,
rollback, and source-refresh semantics.

**Recommendation:** make the workflow call the same dispatcher entrypoint (or a
Nexus RPC wrapper that executes the exact same script), and remove its direct
Colmena/systemd operations. Keep workflow permissions minimal and make the
workflow wait for and report the dispatcher job result. The explicit
`deploy-direct-legacy` recipe should remain break-glass only, ideally requiring
an acknowledgement flag and emitting a prominent audit log.

#### C2. Rollback should be a single tested transaction

The workflow attempts rollback after Colmena failure, while the dispatcher and
manual recipes have their own rollback behavior. Mining pause/resume and health
checks are also implemented in multiple places.

**Recommendation:** model deployment as stages: preflight → build → closure
transfer → activate → health gate → resume workloads. Put this in one script,
with target-aware rollback and a durable job result. Test it with a local fake
executor and shell-level failure injection; do not test failure behavior first
on the live cluster.

### D. Kubernetes design improvements

#### D1. Standard workload contract

For ordinary Deployments/StatefulSets, define a generated contract requiring:

- explicit replicas and revision history;
- a deliberate rollout strategy (`maxSurge=0` where cluster capacity requires
  it, otherwise an explicit reason);
- requests and limits for every init/container;
- startup/readiness/liveness probes appropriate to the service;
- pod/container security context;
- labels for app, component, owner, managed-by, and policy class;
- node affinity/tolerations rather than accidental scheduling;
- NetworkPolicy for ingress and egress;
- PDB only where multiple replicas and disruption semantics justify one;
- immutable image identity.

Do not force probes onto batch jobs or device plugins without an appropriate
exception type.

#### D2. Endpoint and IP hygiene

The earlier audit identified raw YAML with hardcoded `10.1.1.x` endpoints and
wrong/unknown llama ports. `kubernetes/modules/hermes-workspace.nix` is another
active example. In-cluster communication should use Service DNS. Host IPs are
appropriate only for explicitly documented host-network or node-local cases.

Add a test that rejects private host IPs in container environment values unless
an object carries `networkingException = "host-network"` or an equivalent
machine-readable annotation. Validate that every referenced Service/port exists
in the generated object graph or canonical service registry.

#### D3. NetworkPolicy needs negative tests

The repo has useful default-deny and allow policies, but policy presence alone
does not prove traffic intent. Add tests for expected allowed edges and denied
edges using a small policy model, then run live conformance probes where the
cluster supports it. Avoid broad `ingress = [{}]`/`egress = [{}]` exceptions
unless the object is explicitly a system component.

## Research-backed practices

### Nix / NixOS / Colmena

- Nix flakes are locked by `flake.lock`; `nix flake check` evaluates flake
  outputs and is the baseline consistency gate.
- NixOS module `assertions` should fail evaluation for unsafe combinations;
  `warnings` are appropriate for transitional/deprecated behavior.
- Remote builders are a trust boundary. Builder machine records must have
  correct field ordering, systems, features, max jobs, and signatures.
- Binary substitutes should retain signature verification (`require-sigs`) and
  use a minimal trusted-user set. Secrets must not be embedded into derivations
  or otherwise placed unencrypted in the Nix store.
- Colmena `targetHost` identifies the activation target; `buildOnTarget` controls
  where derivations are built; `allowLocalDeployment` permits local activation.
  These settings should be tested as a matrix, not inferred from comments.

Primary sources:

- Nix flakes: <https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html>
- Nix distributed builds: <https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html>
- Nix security and signatures: <https://nixos.org/manual/nix/stable/advanced-topics/security.html>
- NixOS assertions: <https://nixos.org/manual/nixos/stable/options.html#opt-assertions>
- Colmena documentation: <https://colmena.cli.rs/>

### easykubenix

The vendored source is the immediate implementation authority:

- `vendor/easykubenix/README.md`
- `vendor/easykubenix/kubernetes.nix`
- `vendor/easykubenix/validation.nix`
- `vendor/easykubenix/assertions.nix`

The upstream project is <https://github.com/Lillecarl/easykubenix>. The key
practices are to keep resources in the Nix module graph, use API mappings rather
than hand-writing repetitive metadata, use transformers/generators for
cross-cutting derived objects, and run the provided ephemeral API-server
validation instead of relying only on YAML syntax.

### Kubernetes

Primary official references:

- Declarative management: <https://kubernetes.io/docs/concepts/cluster-administration/manage-deployment/>
- Resource requests and limits: <https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/>
- Probes: <https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/>
- Security context: <https://kubernetes.io/docs/tasks/configure-pod-container/security-context/>
- Pod Security Standards: <https://kubernetes.io/docs/concepts/security/pod-security-standards/>
- NetworkPolicy: <https://kubernetes.io/docs/concepts/services-networking/network-policies/>
- PodDisruptionBudget: <https://kubernetes.io/docs/tasks/run-application/configure-pdb/>
- Deployment rollouts: <https://kubernetes.io/docs/concepts/workloads/controllers/deployment/>
- Image identity and digests: <https://kubernetes.io/docs/concepts/containers/images/>
- Server-side apply: <https://kubernetes.io/docs/reference/using-api/server-side-apply/>

## Recommended implementation sequence

### Slice 1 — Make correctness gates real

1. Remove `continue-on-error` and `|| true` from required CI jobs.
2. Make the test runner exit non-zero when any test reports `passed != true`.
3. Add `tests/k8s-manifest-validation.nix` to required CI or replace it with the
   evaluated-manifest test below.
4. Keep cache push and advisory docs checks separate and visibly non-blocking.

**Gate:** a deliberately failing fixture causes CI to fail; a cache outage does
not fail a correct PR.

### Slice 2 — Consolidate builder configuration and secure Nix

1. Remove or quarantine `nix-distributed-builders.nix`.
2. Restore signature verification and narrow trusted users.
3. Create one typed builder registry and render `/etc/nix/machines` from it.
4. Add canonical host-address and feature assertions.

**Gate:** evaluate all four hosts; inspect generated machine files; prove Nexus,
Sentry, Forge, and Zephyr map to the intended addresses; run a signed-cache
substitute test.

### Slice 3 — Unify deployment

1. Refactor `.github/workflows/deploy.yml` to invoke the Nexus dispatcher.
2. Remove direct Colmena and imperative mining operations from the workflow.
3. Make dispatcher status/rollback machine-readable.
4. Require an explicit break-glass acknowledgement for direct deployment.

**Gate:** dry-run dispatcher tests cover all targets, local Nexus activation,
remote activation, preflight failure, duplicate job, target-host mismatch,
activation failure, rollback, and disconnect-safe async operation.

### Slice 4 — Evaluate easykubenix objects and validate against an API server

1. Expose a flake check/app for each active manifest bundle's
   `validationScript`.
2. Parse `generated`/`generatedByPath` and assert object-level contracts.
3. Run kubeconform against the Kubernetes version actually pinned by the flake.
4. Add a raw-YAML inventory and identity collision check.

**Gate:** generated manifests validate against an ephemeral API server and no
object is deployed by both generated and raw paths.

### Slice 5 — Apply the Kubernetes workload contract

1. Fix the known active exceptions first: Hermes workspace placement/endpoints,
   Vane image identity, Qdrant local image identity, and the misplaced Grafana
   MCP security context.
2. Add shared constructors/transformers for standard workload defaults.
3. Add explicit exception metadata for GPU, device-plugin, hostPath, and local
   image workloads.
4. Add resources/probes/security context/PDB/NetworkPolicy only where semantically
   appropriate.

**Gate:** every generated object is classified as standard or exception, with a
machine-readable reason and a passing policy report.

## Brainstorm: high-value experiments

1. **Manifest contract dashboard:** generate a JSON report per bundle with counts
   of resources, images, namespaces, policy exceptions, missing probes, missing
   resources, and raw-IP references; publish it as a CI artifact and Grafana
   input.
2. **Builder canary:** a tiny derivation requiring `big-parallel` and a tiny
   ordinary derivation; assert each selects the intended builder class without
   touching production hosts.
3. **Nix evaluation budget:** record evaluation time and closure size per host and
   manifest bundle; fail only on large regressions, not absolute machine-specific
   timings.
4. **Generated service graph:** derive a graph from Service selectors, env DNS
   references, NetworkPolicies, and Caddy routes; flag endpoints with no backing
   Service or policy path.
5. **Policy exception registry:** one Nix attrset for all privileged, hostNetwork,
   hostPath, local-image, and fixed-node workloads. Every exception gets owner,
   reason, scope, and expiry/review date.
6. **Drift sentinel:** compare live managed object identities and labels against
   generated `generatedByPath`; report unmanaged or duplicate objects without
   mutating the cluster.
7. **Reproducible local image pipeline:** build local images from Nix or a pinned
   source revision, push to the local registry under a content-addressed tag,
   and emit the resulting digest into the Kubernetes module rather than using
   `localhost:*:latest`.

## What not to do

- Do not add another deployment framework before the current source-of-truth
  boundary is explicit.
- Do not globally force `restricted` Pod Security on GPU/device-plugin workloads;
  classify and isolate their required privileges instead.
- Do not replace all raw YAML in one large migration; inventory and migrate one
  ownership boundary at a time.
- Do not make Zephyr build locally to improve throughput; the current OOM-driven
  `max-jobs=0` policy is intentional.
- Do not treat `big-parallel` as x86-64-v3 or as a CPU optimization flag.
- Do not put runtime secrets into generated manifests or Nix store paths.

## Suggested first implementation PRs

1. **`ci: make required validation fail closed`** — test runner, required jobs,
   manifest validation wiring.
2. **`nix: remove duplicate builder module and restore trust defaults`** —
   builder registry/assertions, cache ownership verification, generated
   machine-file tests.
3. **`deploy: route GitHub workflow through Nexus dispatcher`** — one executor,
   status protocol, failure-injection tests.
4. **`k8s: add evaluated easykubenix policy contract`** — object traversal,
   standard/exception classes, API-server validation.
5. **`k8s: migrate endpoint/image exceptions`** — Hermes/Vane/Qdrant/Grafana MCP,
   raw manifest inventory, digest policy.

Each PR should remain independently reviewable and should not include a live
cluster switch as part of CI validation.
