# Issue #10: upstream cachix PR for `sops://` feature

**Priority:** LOW (long-term; months-out due to cachix maintainer response time)  \n**Status:** Open  \n**Created:** 2026-07-25  \n**Origin:** Drift-cycle Stream 7a of comprehensive plan + repeated mentions across
phases  \n**Depends on:** Issue #3 cargo check (must compile before pushing) + cachix fork
`feature/sops-provider-subprocess-dispatch` branch being pushed to origin + cachix
maintainer response window  \n**Blocks:** long-term Option C migration (flake-input `git+https://github.com/cachix/secretspec?rev=<release-tag>`); once merged, removes the local-fork + patch-series
hack

## Context

The cluster's `secretspec` validator system depends on a `sops://` Provider that the
upstream `cachix/secretspec` does NOT yet expose. Workaround: maintain a local fork of
`cachix/secretspec` on `feature/sops-provider-subprocess-dispatch`, apply
`secretspec-fork-patches/0001-add-sops-provider.patch`, and pin the fork checkout as
the `src` of the Nix build (`pkgs/secretspec/default.nix`).

Long-term (Stream 7a of the drift-cycle plan, repeated 4+ times in session notes):
push the fork branch back to upstream as a PR for cachix/secretspec#98 or follow-up.
When upstream merges + tags a release with the sops feature, the cluster can swap the
Nix build from `src = ../Projects/secretspec-core` to
`src = fetchFromGitHub { ... rev = "v0.X.Y"; sha256 = "..."; }`, eliminating the fork
entirely.

This issue exists to track that PR work-stream as a discrete unit of work; today we
don't even know the PR is open.

## Acceptance Criteria

- Fork branch `feature/sops-provider-subprocess-dispatch` is pushed to
  `https://github.com/cachix/secretspec` (requires cachix write access — none today; PR
  workflow via fork-of-fork).
- PR description outlines:
  - What the sops feature adds (Provider trait impl, NDJSON handshake protocol,
    subprocess dispatch lifecycle).
  - Why dispatch-via-subprocess (not libsops linkage) — sandbox-friendly, no native
    rebuild for sops upgrades, matches cachix/secretspec's existing Provider trait ergonomics.
  - Test plan: secretspec Unit + integration + a documented smoke-test (echo roundtrip).
- CI on cachix/secretspec repo passes for the PR branch.
- Cachix maintainer merges the PR OR explicitly defers with a reason; cluster is notified.
- When merged: a follow-up issue opens to flip `pkgs/secretspec/default.nix` src attr
  to `fetchFromGitHub` (closes the Drift Cycle's Option-C migration path).

## Approach

1. **Push the fork branch** to a personal fork (`https://github.com/reverb256/secretspec`)
   first: `git push reverb256 feature/sops-provider-subprocess-dispatch`. (Reverb256 is
   the cluster operator's GitHub handle; cachix/secretspec#98 is unknown until actually
   opened.)
2. **Open a PR** at `cachix/secretspec#98` (or follow-up-number) via the GitHub web UI.
   Title: `feat(provider): add sops:// subprocess Provider`. Body: link to
   `secret-rfc#XXX`, link to the cluster's drift-cycle plan doc, link to
   `secretspec-fork-patches/0001-add-sops-provider.patch` for review convenience.
3. **Watch for review iteration** — cachix maintainer may ask for: docs, more tests,
   feature-flag default toggle defaults, error-handling improvement. Respond in
   `.plans/2026-XX-XX-cachix-pr-iteration.md`.
4. **On merge**: Open Issue #10b (follower) to flip the `src` attr. Until then, the
   fork-checkout + local-patch workaround in `pkgs/secretspec/default.nix` remains
   operator-burden.

## Risk

- **PR may never get reviewed.** Cachix is a small maintainer team; response time
  varies. The fork may persist for months.
- **PR may be rejected** if cachix prefers a libsops-linkage approach over subprocess
  dispatch. If rejected, **fork it longer-term** + document the rejection rationale.
- **PR may break other providers' API contracts** if upstream cachix/secretspec Provider
  trait evolves. Mitigate by syncing fork to upstream main weekly.
- **PR credentials leak** — pushing fork branch requires a GitHub PAT with `repo`
  scope; this is in `secrets/github-token.age` (encrypted). The sops:// feature PR
  would be authored using the same PAT. If the PAT rotates, the local
  `~/.gitconfig` push URL may break.

## Related

- `cachix/secretspec` upstream repo (PR target)
- `cachix/secretspec#98` (the originating discussion — verify before creating new PR)
- `~/Projects/secretspec-core` (local fork)
- `secretspec-fork-patches/0001-add-sops-provider.patch` (review-friendly patch series)
- `pkgs/secretspec/default.nix` (Nix build; post-merge target)
- `pkgs/secretspec-provider-sops/default.nix` (Nix build; post-merge target)
- `.plans/2026-07-25-cluster-localSealSupport-scope.md` (drift-cycle plan doc;
  Stream 7a followup)
- Issue #3 (cargo check — must pass before push)
- Issue #6 (SHA pinning — replace with release tag on merge)
- Issue #9 (bootstrap recipe clean-state — testable while PR is in flight)
