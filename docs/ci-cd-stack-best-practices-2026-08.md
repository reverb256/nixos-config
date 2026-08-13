# CI/CD and Stack Best Practices

**Research date:** 2026-08-13  
**Last verified:** 2026-08-13  
**Scope:** GitHub Actions, self-hosted runners, NixOS, Home Manager, K3s/easykubenix, secrets, deployment safety, and mixed NVIDIA/AMD model serving.

## Executive summary

The repository has a strong declarative foundation. Flakes, locked inputs, NixOS modules, a dedicated Nexus builder, Home Manager layer separation, easykubenix manifests, encrypted secrets, canary deployment, rollback, and provenance checks are all good design choices.

The main weakness is the CI execution boundary. One persistent Nexus runner handles lightweight PR checks, heavy Nix builds, cache publication, diagnostics, and deployment. Every pull request also starts a serial four-host cache build. This creates a queue and gives untrusted workflow code access to a valuable, long-lived host.

The target architecture should use three separate lanes:

1. **Untrusted PR lane:** GitHub-hosted runners for parsing, linting, policy checks, and tests that do not need cluster access or secrets.
2. **Trusted build lane:** An isolated Nix build runner or Nexus build executor for pinned, trusted revisions. Publish caches only from `main` or an explicitly approved workflow.
3. **Deployment lane:** A serialized, manually approved environment that consumes a reviewed commit or immutable build artifact. It must call the canonical Nexus dispatcher and must not pull arbitrary working trees on cluster nodes.

The highest-priority changes are:

- Stop cache builds on every pull request.
- Add workflow and job concurrency plus timeouts.
- Remove wildcard Nix trust and disable automatic flake configuration acceptance.
- Keep secrets and deployment privileges out of untrusted PR workflows.
- Replace the persistent all-purpose runner with isolated runner roles. Use ephemeral runners where practical.
- Make the deployment workflow use a protected GitHub Environment and the canonical Nexus deployment path.
- Add one evidence-based gate for NixOS, Home Manager, Kubernetes, and model artifacts.

These changes improve queue time, security, reproducibility, and recovery without replacing the current NixOS architecture.

## Evidence from this repository

### Current CI and runner layout

- `.github/workflows/ci.yml` sends parse, quick check, lint, tests, security, and build jobs to `[self-hosted, nixos]`, except the Home Path Guard.
- `.github/workflows/cache.yml` runs on every pull request and push. It builds `zephyr`, `nexus`, `forge`, and `sentry` in series, then pushes each result to Nexus.
- `.github/workflows/ci-test-automation.yml` also targets the same self-hosted runner.
- `.github/workflows/pr-validation.yml` targets the same runner for policy checks that do not need cluster hardware.
- `.github/workflows/secretspec-build.yml` also runs on the self-hosted runner for pull requests. Its `validate-e2e` job passes `secrets.CACHIX_AUTH_TOKEN`, and its trusted build job can push to Cachix. This is a secret and cache-write boundary that must not share an ordinary untrusted PR lane.
- `.github/workflows/deploy.yml` targets the same runner and has access to `sudo`, SSH, Colmena, mining controls, and repository write permission.
- The main PR workflows also request broad `pull-requests: write` and, in `pr-validation.yml`, `checks: write` permissions even though most steps only inspect repository content.
- `modules/services/ci-runner.nix` defines a persistent systemd runner with a persistent home, a PAT or token file, access to `/run/secrets`, and a broad system toolchain.
- The runner registration service deletes old runner credentials and re-registers the runner. It does not register the runner with `--ephemeral`.
- Current live CI observations showed one online and busy `nexus-runner`, more than 30 queued jobs, and a cache job that had run for several hours. The cache job was still in `Build all host toplevels and push to nexus cache` when inspected.

### Current Nix and build layout

- `modules/system/distributed-builds.nix` makes Zephyr a dispatcher with `max-jobs = 0` and makes Nexus the primary builder.
- The same module enables signed substitutes, remote builders, sandboxing, build logs, garbage collection, and best-effort cache publication.
- `modules/system/nix-config.nix` defines the canonical cache policy and enables flakes.
- `modules/system/nix-config.nix` currently sets `accept-flake-config = true`.
- `modules/system/distributed-builds.nix` currently forces `trusted-users` to include `"*"` and `"@wheel"`.
- `justfile` already exposes a Nexus dispatcher, canary deployment, provenance collection, rollback, Home Manager build/switch, and health-check entrypoints.

### Current Home Manager layout

- The NixOS integration in `modules/system/home-manager.nix` is now a compatibility bridge.
- The active standalone configuration is the `home-manager-config` flake input.
- `useGlobalPkgs = true`, shared leaf modules, host-specific leaves, and `home-manager` backup handling are established.
- `justfile` provides independent Home Manager build, switch, and audit paths.

### Current Kubernetes and AI layout

- `kubernetes/default.nix` generates separate easykubenix manifests for combined, monitoring, AI inference, llama servers, and smaller service groups.
- `kubernetes/modules/ai-inference.nix` centralizes model routing, the gateway, NIM fallback, Qdrant, Redis, secrets, and network policies.
- `kubernetes/curated-models.nix` acts as the model registry and records local, NIM, vLLM, and llama.cpp backends.
- GPU workloads are intentionally split across NVIDIA and AMD hosts. Current scheduling uses explicit host placement and affinity in many manifests.
- The repository contains both pinned images and remaining floating `:latest` references in the manifest tree. The active/deprecated boundary must be audited rather than assumed.

## Official guidance and how it applies

### GitHub Actions runners

GitHub states that self-hosted runners are managed by the operator, including their operating system and installed software. GitHub recommends ephemeral runners for autoscaling because one runner receives one job and can then be cleaned. GitHub also warns that self-hosted runners are a security risk for untrusted workflow code, especially when pull requests can modify workflow files.

**Application here:** A persistent Nexus runner with a Nix store is useful as a build host, but it is not a good universal executor for untrusted pull requests, cache publication, and deployment. Preserve the Nix store as a cache. Isolate the workspace, credentials, runner identity, and deployment privileges.

GitHub also documents that jobs remain queued when no matching idle runner exists and can fail after the queue limit. A single runner therefore turns workflow fan-out into a serialized queue. Labels and runner groups should express capability and trust boundaries, not only operating system type.

The current `secretspec-build.yml` pull-request trigger is a concrete exception to the desired boundary: it runs on the persistent self-hosted runner and exposes a Cachix secret to a workflow that checks out pull-request content. Split its structural validation from its trusted end-to-end and cache-publish jobs before treating the runner as safe for external or low-trust contributions.

**Sources:** [GH-1], [GH-2], [GH-3]

### Workflow concurrency, permissions, and environments

GitHub supports workflow and job concurrency groups. Use them to cancel obsolete PR runs and to serialize deployments. Deployment environments can require reviewers, wait timers, branch restrictions, and protected secrets. The secure-use guidance recommends read-only default `GITHUB_TOKEN` permissions, least privilege at job level, intermediate environment variables for untrusted input, and full-SHA pinning for actions.

**Application here:**

- Add `concurrency` to PR workflows: cancel older runs for the same PR.
- Add a non-cancelling `concurrency` group to deployment: never run two cluster activations at once.
- Use a protected `homelab-production` environment for deployment approval.
- Change deployment permissions from broad `contents: write` and `id-token: write` to the minimum actually required. Remove `id-token: write` unless the job uses OIDC.
- Keep action references pinned to full commit SHAs. The repository already does this in most workflows.
- Narrow `pull-requests: write` and `checks: write` to the individual job that truly needs them. Most validation jobs should use only `contents: read`.
- Do not pass untrusted PR values directly into shell source. Put them in environment variables and quote them.

**Sources:** [GH-2], [GH-4], [GH-5], [GH-6]

### Nix configuration and remote builders

Nix provides sandboxed builds, signed substitutes, remote builders, and atomic store paths. The Nix manual documents that `trusted-users` can connect to the daemon with elevated trust, and that `accept-flake-config` accepts configuration supplied by a flake without prompting. A binary cache is safe only when its public key is configured and signature verification remains enabled.

The current cache workflow and `secretspec-build.yml` must be treated as separate trust domains. A PR may evaluate code, but it must not publish outputs with a cache write credential. A successful trusted build on `main` may publish a closure after the commit, lock file, and build result are recorded.

**Application here:**

- Keep `sandbox = true`, `require-sigs = true`, locked flakes, and remote builders.
- Remove `"*"` from `trusted-users`. Use only the smallest administrative set needed for the daemon. Do not treat all users as trusted because CI needs Nix.
- Set `accept-flake-config = false` in the effective daemon configuration. If a specific controlled command needs a flake setting, pass it explicitly and review that command.
- Evaluate the merged NixOS settings in tests. Source-text checks are not enough because `mkForce`, `mkDefault`, and module order can change the effective value.
- Keep `max-jobs = 0` on Zephyr if it is the dispatcher policy. Make the zero-local-build invariant a tested contract.
- Keep Nexus as a remote builder, but add health and queue telemetry. A dead or overloaded builder must fail quickly and visibly.
- Separate cache reads from cache writes. PRs may read public or internal cache data. Only trusted `main` builds should publish to the shared cache.
- Prefer one successful build of an immutable target set followed by `nix copy` of the resulting closure. Do not rebuild all four hosts independently in every PR cache job.
- Use the flake's pinned tools and inputs. Avoid workflows that install an unrelated `nixos-unstable` channel and then run tests against `<nixpkgs>` when the flake is locked to something else.

**Sources:** [NIX-1], [NIX-2], [NIX-3]

### Home Manager

Home Manager provides declarative user configuration and supports both NixOS integration and standalone operation. The repository's split between system configuration, Home Manager, and the user profile is sound.

**Application here:**

- Keep system services and hardware in NixOS.
- Keep user files, shells, editor configuration, and user applications in the standalone Home Manager flake.
- Build the exact Home Manager activation package in CI from a pinned commit.
- Test both entrypoints where the compatibility bridge remains active.
- Deploy the activation package from a reviewed commit. Do not let a host fetch an unpinned GitHub branch during activation.
- Keep the existing `hm-audit` idea and make it a required post-deployment evidence check.
- Document the ownership of every user-facing binary: system closure, standalone HM profile, or external profile layer.

**Source:** [HM-1]

### Secrets

`sops-nix` describes atomic, declarative secret provisioning. Secrets are decrypted during activation into access-controlled files, and encrypted files can remain in version control. GitHub's secure-use guidance still applies to workflow secrets: use least privilege, avoid structured secrets in logs, register transformed secret values, rotate credentials, and protect production secrets with environment reviewers.

**Application here:**

- Keep encrypted SOPS material in Git and decrypt only on approved hosts.
- Do not expose deployment credentials or cache write credentials to ordinary PR jobs.
- Replace the long-lived runner PAT with a short-lived registration token flow or a narrowly scoped GitHub App credential held only by the runner setup service.
- Do not mount `/run/secrets` into a runner that executes untrusted PR code. A deployment runner may access only the secrets required by its protected environment.
- Keep NIM, Cachix, registry, and deployment credentials separate. Rotate them independently.
- Add a secret-use inventory and a periodic rotation check.

**Sources:** [GH-2], [SOPS-1]

### Kubernetes and GitOps safety

Kubernetes Deployments provide controlled updates and rollback. Readiness probes remove unready Pods from Service traffic; liveness probes restart containers that cannot recover; startup probes protect slow-starting applications. Resource requests guide scheduling, and limits are enforced by cgroups, with memory overuse potentially causing OOM kills.

**Application here:**

- Keep easykubenix as the manifest source of truth.
- Generate manifests from the exact reviewed flake revision.
- Validate Nix evaluation, YAML/API schema, policy rules, and a server-side dry run before deployment.
- Use a deployment artifact rather than applying an arbitrary working tree.
- Add readiness and startup probes to every model gateway and inference server. Do not use liveness as a proxy for model-load readiness.
- Set explicit CPU, RAM, ephemeral-storage, and vendor-specific GPU requests and limits.
- Use node labels, taints, tolerations, and affinity to distinguish NVIDIA CUDA, AMD ROCm/Vulkan, CPU, monitoring, and mining roles. Use `nodeName` only for deliberate hardware pinning and document why.
- Set `revisionHistoryLimit`, rollout strategy, `maxUnavailable`, and `maxSurge` per workload. GPU workloads usually need a deliberate Recreate or single-replica strategy because two model copies may exceed VRAM.
- Keep NetworkPolicies, Pod Security labels, non-root settings, service accounts, and automount restrictions.
- Inventory all floating image tags. Replace active `:latest` references with immutable tags or digests. Ensure the admission rule is applied to the namespaces that run workloads.
- Remove or isolate imperative scripts that use `kubectl patch` or `kubectl apply`. If a resource is declarative, express the desired state in easykubenix.
- Add rollout status, Pod readiness, model health, and endpoint smoke tests to the deployment gate.

**Sources:** [K8S-1], [K8S-2], [K8S-3]

### Model serving on mixed GPUs

NVIDIA NIM is an NVIDIA-oriented production runtime with supported microservices and security updates. vLLM's production stack provides Kubernetes deployment, model-aware routing, observability, and KV-cache offload features. llama.cpp remains useful for GGUF portability, Vulkan, CPU/GPU offload, and low-VRAM experiments. These engines should not be treated as one interchangeable runtime.

The hardware split below is a repository engineering recommendation. It is not a claim that one official document defines every mixed NVIDIA/AMD boundary. Validate each model and engine against its current vendor support matrix before promotion.

**Application here:**

- Keep NIM on compatible NVIDIA nodes.
- Keep vLLM CUDA and vLLM ROCm deployments in separate hardware pools with separate tested images.
- Keep llama.cpp CUDA and Vulkan services separate and expose them through the gateway's common API.
- Pin container image digests, model repository revisions, GGUF checksums, quantization format, context length, and serving arguments.
- Store model metadata in the existing model registry, not in ad hoc Deployment command lines.
- Make model loading a readiness condition. A listening HTTP socket is not enough.
- Export request rate, queue depth, time to first token, generation rate, error rate, model-load time, CPU/RAM usage, and GPU memory/utilization.
- Add a canary benchmark for each model/hardware pair. Record expected throughput, latency, context, and OOM limits as evidence.
- Route by capability and policy: privacy-sensitive requests to local models, high-capability requests to approved NIM, and fallback only when the fallback is policy-compatible.
- Treat NeMo, NIM, and future portfolio tooling as an integration track. Do not replace the existing gateway until the new engine passes the same health, benchmark, security, and rollback gates.

**Sources:** [NIM-1], [VLLM-1]

## Target CI/CD architecture

### Lane A: PR validation

Run on GitHub-hosted runners whenever the job does not require the private LAN:

- Nix parse checks.
- `nix flake check --no-build` with the locked flake.
- Alejandra, Statix, Deadnix, shell syntax, Python compilation.
- Source and evaluated contract tests.
- Home-path and ownership checks.
- Kubernetes manifest evaluation and schema validation.
- Image-tag, digest, policy, and secret-reference checks.
- Documentation checks.

This lane must not have:

- NIM, Cachix push, registry push, SSH keys, `/run/secrets`, `sudo`, Kubernetes credentials, or access to the private LAN.

### Lane B: Trusted Nix build and cache

Run only for `main`, a release tag, or an explicitly approved trusted workflow:

1. Check out the exact commit.
2. Verify the commit and lock file.
3. Evaluate the target set.
4. Build through the Nexus builder pool.
5. Run host-specific build checks.
6. Push only successful closures to the private cache.
7. Emit a manifest containing commit, flake lock hash, system target, store paths, builder, and test results.

Use a dedicated runner label such as `nixos-build`. Keep the persistent Nix store, but use an isolated workspace and a clean runner identity. A disposable VM or NixOS container around the runner is preferable when the operational cost is acceptable.

Do not run the four-host serial cache build on every PR.

### Lane C: Deployment

Use a manually dispatched workflow with:

- `environment: homelab-production`.
- Required reviewer approval.
- Deployment branch restriction to `main` or release tags.
- A non-cancelling concurrency group.
- Read-only repository token unless a specific write is required.
- No unnecessary OIDC permission.
- Exact artifact or commit selection.
- Preflight, build/provenance verification, canary deployment, health checks, and automatic rollback.
- A final provenance artifact attached to the run.

The workflow should call `nexus-dispatch.sh` or the supported `just deploy` path. It should not run `git stash` and `git pull` on cluster nodes. Cluster checkouts must remain consumers of the canonical deployment process.

### Lane D: AI and Kubernetes release

Treat model-serving changes as release artifacts:

1. Build or select an immutable image.
2. Record the image digest.
3. Record model revision/checksum and serving parameters.
4. Validate generated manifests and policies.
5. Deploy one canary workload.
6. Check readiness, latency, error rate, GPU memory, and model output smoke tests.
7. Promote or roll back.

## Prioritized roadmap

### P0: Fix security and queue starvation

1. Change cache workflow triggers from every PR to `push: main` and `workflow_dispatch`.
2. Add PR concurrency with `cancel-in-progress: true`.
3. Add deployment concurrency with `cancel-in-progress: false`.
4. Add timeouts to every job, including the main CI and cache jobs.
5. Move lightweight PR jobs to GitHub-hosted runners.
6. Remove `trusted-users = ["*"]` from the effective Nix daemon settings.
7. Set effective `accept-flake-config = false`.
8. Remove deployment secrets from workflows triggered by ordinary PR events.
9. Add a protected deployment environment.
10. Review and minimize `deploy.yml` permissions.

### P1: Make builds reproducible and observable

1. Create reusable workflows for PR checks, trusted builds, and deployment.
2. Use flake-pinned tools instead of a separate unstable channel for CI behavior.
3. Publish build provenance with each cache publication.
4. Add queue-age, job-duration, cache-hit, builder-health, and disk-space monitoring.
5. Add evaluated tests for effective Nix settings and generated `/etc/nix/machines`.
6. Add a Home Manager exact-revision build and post-deploy audit gate.
7. Add a generated-manifest artifact and server-side dry-run gate.
8. Add image digest and model checksum tests.

### P2: Improve isolation and capacity

1. Add a dedicated trusted build runner or ephemeral runner pool.
2. Keep deployment on a separate labeled runner with no general PR routing.
3. Add a second Nix builder if Nexus queue time remains high.
4. Consider ARC only if runner demand justifies Kubernetes-native autoscaling. GitHub identifies ARC as its recommended Kubernetes autoscaling implementation; it is not needed for the immediate one-runner fix.
5. Add signed container images and attestations for custom gateway and inference images.
6. Add model canary history and performance regression alerts.

## Decision rules

- **Do not add more hardware before removing avoidable queue work.** The cache workflow is the first capacity problem.
- **Do not give trusted Nix daemon access to all users to simplify CI.** Fix the runner boundary instead.
- **Do not use NIM as the universal runtime.** NIM is the NVIDIA lane; vLLM and llama.cpp cover other hardware and use cases.
- **Do not make Kubernetes the source of truth for NixOS-owned services.** Keep the existing layer boundaries.
- **Do not deploy a model because its process listens on a port.** Require model readiness and benchmark evidence.
- **Do not merge a deployment gate that only checks source text when module evaluation changes the effective setting.** Evaluate the merged configuration.

## Source index

### GitHub

- [GH-1: Self-hosted runners](https://docs.github.com/en/actions/concepts/runners/self-hosted-runners)
- [GH-2: Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)
- [GH-3: Self-hosted runner reference and autoscaling](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [GH-4: Managing environments for deployment](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
- [GH-5: Workflow syntax and concurrency](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#concurrency)
- [GH-6: Workflow permissions](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#permissions)

### Nix and Home Manager

- [NIX-1: Nix configuration reference](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html)
- [NIX-2: NixOS distributed builds](https://nixos.org/manual/nixos/stable/index.html#sec-distributed-builds)
- [NIX-3: Serving a Nix store through a binary cache](https://nixos.org/manual/nix/stable/package-management/binary-cache-substituter.html)
- [NIX-4: Nix post-build hooks and signing](https://nixos.org/manual/nix/stable/advanced-topics/post-build-hook.html)
- [HM-1: Home Manager manual](https://nix-community.github.io/home-manager/)
- [SOPS-1: sops-nix](https://github.com/Mic92/sops-nix)

### Kubernetes and model serving

- [K8S-1: Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [K8S-2: Kubernetes probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [K8S-3: Kubernetes resource management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [K8S-4: Kubernetes container images](https://kubernetes.io/docs/concepts/containers/images/)
- [NIM-1: NVIDIA NIM documentation](https://docs.nvidia.com/nim/)
- [VLLM-1: vLLM production stack](https://docs.vllm.ai/en/latest/deployment/integrations/production-stack/)

## Research limits

This report is a design review, not a claim that every live cluster setting was checked. It uses repository source and official documentation. The next implementation phase must verify live runner groups, branch protection, environment settings, effective Nix daemon settings on every host, active Kubernetes resources, and actual model health before changing deployment behavior.
