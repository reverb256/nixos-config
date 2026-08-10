# Documentation Cleanup Manifest

> **Status:** Audit manifest — Batch A complete; no archive moves or deletes performed
> **Created:** 2026-08-09
> **Last Verified:** 2026-08-09
> **Owner:** j_kro
> **Scope:** Repository documentation structure, navigation, freshness, and operational safety

## Purpose

This manifest is the review gate for the comprehensive documentation cleanup. It records
what is authoritative, what is historical, what is generated, and what should be
consolidated. Batch A updated this manifest and the canonical navigation documents; no
archive moves or deletes were performed.

The repository currently contains approximately 313 documentation/text files when
Markdown, text, reStructuredText, and AsciiDoc files are counted outside `.git` and
`vendor`. The count includes agent instructions, module READMEs, Kubernetes runbooks,
incident reports, archived research, templates, and generated/status material; it does
not mean all files need the same treatment.

## Safety boundaries

- Preserve incident reports, audit evidence, recovery history, and research.
- Do not delete a document solely because it is old.
- Do not change Nix, shell, YAML, workflow, or deployment files during the documentation
  pass unless a later approved phase explicitly adds a documentation-tooling fix.
- Do not touch the pre-existing working-tree change in `docs/incus-gamepass-migration.md`.
- Do not stage, commit, merge, rebase, or deploy as part of this manifest phase.
- Treat commands in historical or unverified documents as unsafe until checked against
  `AGENTS.md`, `justfile`, and the current source configuration.

## Classification vocabulary

| Class | Meaning | Default treatment |
|---|---|---|
| **Canonical** | Required source of truth for workflow, policy, navigation, or architecture | Keep; maintain deliberately |
| **Active** | Current plan, operational guide, or issue tracker that operators may follow | Keep only with verification metadata and tested commands |
| **Reference** | Stable technical explanation that is not a live-state claim | Keep; refresh links and ownership |
| **Generated** | Produced from code or live state | Keep generator authoritative; do not hand-edit generated body |
| **Historical** | Incident, audit, migration result, or research record | Preserve; clearly mark historical |
| **Deprecated** | Superseded guidance that should not be followed | Tombstone or move to archive with redirect |
| **Duplicate** | Overlapping document whose useful material belongs elsewhere | Merge after content comparison; preserve history |
| **Template** | Reusable blank incident/plan/checklist template | Keep in a clearly named template location |

## Canonical documentation set

The following files form the Batch A navigation spine. Batch A established the
current-state reference and updated the top-level navigation; later batches still need
to reconcile the broader legacy catalog.

| Path | Role | Decision |
|---|---|---|
| `README.md` | Project entry point and quickstart | Keep; remove stale external-path references and keep links high-level |
| `AGENTS.md` | Universal safety and operating rules | Keep canonical; update immediately when a rule is wrong |
| `CONTRIBUTING.md` | Branch/worktree/PR workflow | Keep canonical; reconcile with actual branch protection |
| `DOCUMENTATION_INDEX.md` | Repository-wide catalog | Keep canonical; regenerate/rewrite to match actual paths |
| `DOCS-MAINTENANCE.md` | Documentation policy and freshness rules | Keep canonical; align claimed enforcement with actual scripts |
| `knowledge.md` | High-signal agent/project context | Keep; verify dates and route claims to current-state docs |
| `ACTION-ITEMS.md` | Consolidated operational backlog | Keep only after reconciling stale/completed entries |
| `ROADMAP.md` | Historical migration roadmap plus remaining hardening | Keep as roadmap/history; stop presenting it as live cluster state |
| `STATUS.md` | Generated status snapshot | Keep only if generator and freshness contract are repaired; otherwise rename its role |
| `SOPS-NIX.md` | Secrets architecture reference | Keep, but clearly distinguish legacy sops-nix compatibility from SecretSpec |
| `docs/current-state.md` | Concise checked-in architecture and authority boundaries | **Created and linked in Batch A; maintain as active reference** |

## Current structural findings

### 1. Competing archive roots

The repository previously had two archive roots: `docs/ARCHIVE/` and `docs/archive/`.
The uppercase tree has now been preserved intact under `docs/archive/legacy/ARCHIVE/`.
The lowercase `docs/archive/` tree is canonical. The old LIVE files are preserved under
`docs/archive/legacy/live-snapshots/`, with compatibility pointers retained at `docs/LIVE/`.

**Completed migration:**

1. preserved the uppercase tree without flattening nested external content;
2. moved stale LIVE snapshots to the legacy archive;
3. retained old LIVE paths as non-authoritative pointers;
4. updated the canonical archive index and affected navigation;
5. validated maintained links and authority claims.

### 2. Competing status layers

The repository has one generated status file (`STATUS.md`) and one checked-in architecture
reference (`docs/current-state.md`). `cluster-state.nix` and `scripts/update-status.sh`
provide status provenance. The former LIVE status/runbook files are preserved historical
snapshots with compatibility pointers; they are not authority sources.

**Completed migration:** the verifier and active CI documentation checks now target the
explicit active-document set and repository-relative source paths. Historical files are
excluded from freshness checks without changing their original dates.

### 3. Multiple indexes/catalogs

The navigation spine is now:

- root `README.md`: project entry point;
- `DOCUMENTATION_INDEX.md`: global catalog;
- `docs/current-state.md`: checked-in architecture and authority boundaries;
- `docs/archive/ARCHIVE_INDEX.md`: historical catalog;
- subsystem READMEs: local navigation only;
- `docs/LIVE/`: compatibility pointers only.

### 4. Metadata policy is stronger than enforcement

`DOCS-MAINTENANCE.md` and `knowledge.md` describe a Last Verified/Pocock rule and
frontmatter expectations. Existing checks mostly warn, check selected paths, or enforce
line counts. Many documents lack consistent metadata.

**Proposed action:** first define metadata by class, then enforce it incrementally:

- canonical/active: `Status`, `Last Verified`, `Owner`;
- reference: `Status`, `Last Verified`, `Owner` or `Source`;
- historical: `Status: Historical`, `Date`, `Source`;
- generated: `Status: Generated`, `Generated By`, `Source of Truth`;
- template: `Status: Template`, `Owner`.

Do not mass-add misleading dates without verifying the content.

## Root-document manifest

| Path | Classification | Proposed action |
|---|---|---|
| `AGENTS.md` | Canonical | Keep; verify operational claims during implementation |
| `CLAUDE.md` | Canonical agent context | Keep; reconcile duplicated instructions with `AGENTS.md` |
| `CONTRIBUTING.md` | Canonical | Keep; update branch-protection expectations after GitHub configuration |
| `README.md` | Canonical entry point | Keep; repair links and reduce duplicate status narrative |
| `DOCUMENTATION_INDEX.md` | Canonical catalog | Rewrite catalog after path decisions |
| `DOCS-MAINTENANCE.md` | Canonical policy | Keep; separate policy from enforcement and add metadata matrix |
| `knowledge.md` | Canonical high-signal context | Keep; use `docs/current-state.md` for live claims |
| `ACTION-ITEMS.md` | Active backlog | Reconcile with GitHub issues and current audit; mark stale items |
| `ROADMAP.md` | Roadmap/history | Keep; label historical sections and remove live-state authority wording |
| `STATUS.md` | Generated snapshot, currently stale | Repair generator contract or explicitly mark historical snapshot |
| `SOPS-NIX.md` | Reference | Keep; update dual-path/SecretSpec boundary and verification date |
| `BACKUP-STATUS.md` | Historical snapshot | Archive or replace with verified backup status |
| `CLUSTER_RECOVERY_PLAN.md` | Historical incident plan | Archive with historical banner; route operators to current rescue runbooks |
| `context.md` | Historical/reference mining migration | Archive or move to subsystem reference after link check |
| `DEPLOYMENT-LESSONS.md` | Reference/lessons learned | Keep as safety reference; verify commands and date |
| `NETWORK_AUDIT_REPORT.md` | Historical audit | Archive; preserve evidence and link to current network reference |
| `SECURITY-INCIDENT-2026-07-25.md` | Historical incident | Preserve; mark historical and link current secret runbook |
| `SENTRY-DISK-LAYOUT.md` | Reference/history | Archive if the layout is now encoded in `disko.nix`; otherwise keep as reference |
| `SENTRY-MIGRATION-PLAN.md` | Executed migration plan | Archive; retain warning that it is not a live procedure |
| `HEY.md` | Active coordination log | Keep outside canonical operational docs; define retention policy |
| `hey.md` | Duplicate/deprecated coordination log | Tombstone/merge into `HEY.md` after checking references |
| `coredns-troubleshooting-guide.md` | Reference/runbook | Move to operations/reference after command verification |
| `DOCUMENTATION_AUDIT_2026-03-21.md` | Historical audit | Archive |
| `DOCUMENTATION_AUDIT_SUMMARY.md` | Historical cleanup report | Archive |
| `DOCUMENTATION_CLEANUP_SUMMARY.md` | Historical cleanup report | Archive or retain as prior cleanup history |

The existing `docs/incus-gamepass-migration.md` is explicitly excluded from this phase's
edits because it has pre-existing working-tree changes.

## Active operations and runbook manifest

| Area | Files | Proposed treatment |
|---|---|---|
| Rescue | `docs/runbooks/nixos-usb-rescue.md`, `docs/runbooks/cluster-rescue-quick-reference.md`, `docs/sentry-usb-rescue-recovery-runbook.md`, `scripts/rescue/RESCUE-GUIDE.md` | Keep as a small canonical rescue set; verify command ordering and cross-links |
| CI/CD | `docs/ci-cd/README.md` | Keep canonical; reconcile with actual workflows and required checks |
| Deployment | `docs/plans/2026-07-16-deploy-pipeline-reconcile-plan.md`, `DEPLOYMENT-LESSONS.md` | Mark plan executed/pending explicitly; keep lessons reference |
| Secrets | `SOPS-NIX.md`, `docs/security/secrets-encryption-gap-analysis.md`, incident report | Keep reference/incident; rewrite gap analysis only after live verification |
| Kubernetes security | `docs/kubernetes/security-runbook.md`, `docs/security/data-retention-policy.md`, security audit docs | Keep active only after command review; archive completed implementation summaries |
| Storage | `docs/kubernetes/storage/README.md`, storage-class mapping, PVC guides | Keep one operational guide plus historical implementation notes |
| Mining/GPU | `docs/operations/mining-management-guide.md`, GPU inventory, K8s mining README | Keep, but reconcile systemd/Kubernetes ownership and host identities |
| Cloudflare | `docs/cloudflare/README.md`, domain strategy | Keep reference; archive duplicate completed tunnel-fix reports |
| Banking | three `docs/banking/*` guides | Merge into one setup/troubleshooting reference, preserving details |
| SearXNG | `docs/gateway/searxng/README.md` and `docs/searxng-*` | Verify decommission status; archive stale deployment docs or label historical |

## Kubernetes documentation manifest

### Keep/maintain locally

- `kubernetes-manifests/AGENTS.md`
- active subsystem READMEs for AI tools, inference, llama.cpp, mining, storage,
  resource allocation, security/network, and GitOps
- `PREVENT_POD_EXPLOSION.md` and `ROLLBACK.md` only after command safety review

### Consolidate or label

- `ai-coding-tools/README.md`, `QUICKSTART.md`, `SUMMARY.md`: merge navigation and
  avoid three competing setup descriptions;
- scheduler retrospectives: `INSTABILITY_ROOT_CAUSE_ANALYSIS.md`,
  `VOLCANO_MIGRATION_COMPLETE.md`, `YUNIKORN_PREEMPTION_ANALYSIS.md`; distinguish
  current scheduler policy from historical migration evidence;
- Calico and Caddy reports: keep under explicit archive paths;
- `search-archive/SEARXNG_REFACTOR_GUIDE.md`: move only after determining whether the
  guide is historical or an active maintenance plan.

### Source-of-truth warning

The documentation must state whether a deployment is sourced from Easykubenix/Nix,
raw YAML, Helm, bootstrap manifests, or an operator. A document containing `kubectl
apply` is not automatically an active deployment source. Each subsystem README should
name its source-of-truth path and the safe deploy command.

## Archive manifest and migration map

### Historical material to preserve

- `docs/ARCHIVE/external/lucebox-hub/`
- `docs/ARCHIVE/old-kubernetes-archive/`
- `docs/ARCHIVE/research/` and security/privacy research
- dated incident reports and completed audits
- completed migration plans with their original dates and outcomes

### Likely obsolete operational material

- completed dated plans under `docs/ARCHIVE/plans/`
- duplicate completed Cloudflare/tunnel reports
- stale SearXNG/Calico/HA migration instructions
- old audit summaries that predate the 2026-07-27 audit

### Proposed archive policy

1. Choose one archive root after path/reference audit.
2. Add an archive banner rather than silently changing historical text:

   ```markdown
   > **Status:** Historical / Archived
   > **Last Verified:** YYYY-MM-DD (historical verification date)
   > **Do not follow operational commands without re-validating them against the current repo.**
   ```

3. Add a tombstone only when a path must remain for tooling or human discoverability.
4. Update the archive index in the same change as each move batch.
5. Do not merge documents merely because their titles overlap; preserve distinct incident
   timelines and link them from a consolidated summary.

## Proposed implementation batches after approval

### Batch A — canonical navigation and metadata — COMPLETE 2026-08-09

- created `docs/current-state.md` from checked-in facts and explicit authority boundaries;
- updated `README.md`, `DOCUMENTATION_INDEX.md`, and `DOCS-MAINTENANCE.md`;
- defined metadata class rules;
- made no archive moves or deletes.

Validation: Batch A links and diff checks pass. The existing verification suite still
reports stale `docs/LIVE/*` documents; that is deferred to Batch B rather than hidden by
refreshing historical timestamps.

### Batch B — stale status and completed root docs — IN PROGRESS

- reconcile `ACTION-ITEMS.md` with GitHub and the current audit;
- mark/archive completed root audits and snapshots;
- review the generated `STATUS.md` content against a fresh safe generator run;
- preserve historical files.

### Batch C — operations/runbook consolidation

- consolidate banking and rescue navigation;
- verify every command against `justfile` and current modules;
- archive completed implementation summaries;
- keep dangerous commands behind explicit break-glass warnings.

### Batch D — Kubernetes documentation boundaries

- add source-of-truth declaration to subsystem READMEs;
- merge duplicate quickstarts/summaries;
- separate active operations from archived scheduler/CNI/ingress histories;
- fix internal links.

### Batch E — archive normalization

- choose one archive root;
- move only classified historical files;
- add tombstones/redirects where needed;
- regenerate indexes.

### Batch F — enforcement

Requires a separate approved tooling change:

- make internal-link checking repository-relative rather than `/etc/nixos`-hardcoded;
- make stale active-doc metadata fail CI only after migration is complete;
- make generated-status freshness explicit;
- ensure doc checks do not silently warn on required active documentation.

## Acceptance criteria

The cleanup is complete only when:

- every root and `docs/` document has one classification;
- one canonical navigation index exists and links to real paths;
- active operational docs have owner/status/verification metadata;
- generated docs identify their generator and source of truth;
- historical docs are preserved and visibly non-authoritative;
- no active doc claims current state without a verification date;
- no known internal links point to removed paths;
- documentation validation passes;
- the diff contains no unrelated `.nix`, `.sh`, `.yaml`, or deployment changes;
- pre-existing `docs/incus-gamepass-migration.md` content is preserved;
- current code/worktree changes remain unmodified and unstaged by this operation.

## Open decisions for review

1. Reconcile `ACTION-ITEMS.md` with the current GitHub issue/PR state.
2. Decide whether `HEY.md` is retained as an active coordination log or moved to a session workspace.
3. Decide whether `ROADMAP.md` remains a historical migration roadmap or is split into a short active roadmap plus archived history.
4. Review remaining root documentation for historical banners and duplicate operational guidance.
