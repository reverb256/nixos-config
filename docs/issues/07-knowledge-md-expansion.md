# Issue #7: knowledge.md Other services section expansion

**Priority:** LOW (documentation only)  \n**Status:** Open  \n**Created:** 2026-07-25  \n**Origin:** Drift-cycle Stream 4e of comprehensive plan  \n**Depends on:** none  \n**Blocks:** nothing; reduces AI agent context loss in future sessions

## Context

`/etc/nixos/knowledge.md` is the AI agent context file `freebuff/dev` reads at the start
of every assistant turn. Currently it has an "Other services" section but only covers
3-4 services in a single bullet each. The cluster actually has ~20 named services
visible from `STATUS.md`'s pod inventory, and only a small subset are catalog'd in
knowledge.md. When the assistant gets a question about `gitea-runner`, `n8n`, or
`garage`, it has to rg-search the codebase before answering — wasting context.

The drift-cycle audit also revealed that `validate-local` recipe + CI gating
recommendations aren't in knowledge.md's "Operational gotchas" or "Conventions"
sections. Future sessions will repeat the cure-discovery sweat.

## Acceptance Criteria

- `knowledge.md` "Other services" section grows to cover at least:
  - **gitea** — self-hosted Git, runs on nexus, CI runner on nexus, Argo tunnel to
    `gitea.lan` via Caddy
  - **vaultwarden** — admin-only OIDC client of Casdoor; behind Caddy forward_auth for
    operator convenience; user vault data OUT of cluster
  - **n8n** — workflow automation; ingress at `n8n.lan`; Postgres in-cluster; non-OIDC
    (forward_auth ONLY); operator-tags to `localhost:5678` for direct access
  - **garage** — S3-compatible object store; multi-host replication; admin at
    `s3-admin.lan` (if exposed) or operator-only; used for syncthing-folder-id backup +
    LibreNMS collector uploads
  - **searxng** — public meta-search; cluster-wide result limiter (k8s ConfigMap); uses
    `cf-connecting-ip` from Cloudflare for IP-based rate-limiting
  - **GlitchTip** — Sentry alternative; Postgres in-cluster; ingress via Caddy
  - **casdoor** — central IdP; see SOPS-NIX.md for auth integration
  - **mission-control** (`mission-control.lan`) — orchestration dashboard; behind
    forward_auth; the only web UI exposing the AI agent seed-tasks
- "Operational gotchas" section appends: secretspec validate-local MUST be run before
  any cluster-wide rebuild (Plan-doc Step 3).
- "Conventions" section appends: the Option-B auto-coupling contract that links
  `cluster.localSealSupport` to `services.sops-secrets-registry.enable` (so future
  agents don't re-discover the drift).

## Approach

1. Open `knowledge.md`; locate the "Other services" section.
2. Add 1-2 line bullets per service in alphabetical order (matches existing convention
   if any).
3. Add the drift-cycle disclosure paragraph to "Operational gotchas".
4. Add the Option-B auto-coupling contract to "Conventions".
5. Verify prose is short and high-signal — no extended tutorials.

## Risk

- knowledge.md is read on every assistant turn; bloating it increases context cost for
  every future session. Cap expansion at 1-2 lines per item; prefer cross-references
  (`see STATUS.md`, `see SOPS-NIX.md`) over inline detail.
- If section is renamed or restructured, edit anchors break. Match existing
  capitalization / emoji conventions if any.

## Related

- `knowledge.md` — the file being edited
- `STATUS.md` — pod inventory cross-reference
- `SOPS-NIX.md` — sops / casdoor / hermes cross-reference
- `INFRASTRUCTURE-AUDIT.md` — service classification cross-reference
- `.plans/2026-07-25-cluster-localSealSupport-scope.md` — the drift-cycle plan doc
