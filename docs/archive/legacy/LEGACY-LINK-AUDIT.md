# Legacy Documentation Link Audit

> **Status:** Historical migration record
> **Created:** 2026-08-10
> **Scope:** `docs/archive/legacy/`

The former uppercase archive and former `docs/LIVE` snapshots were preserved under this
path without flattening their contents. A repository-relative Markdown scan reports 17
link-like targets that do not resolve from the relocated historical files.

## Classification

- One target is a relocation-sensitive navigation link in the former LIVE index:
  `../meta/DOCUMENTATION-STRATEGY.md`. The historical index predates the current
  authority model and is retained unchanged as evidence.
- The remaining targets are historical references to files that originally lived at the
  repository root, or shell/template literals inside archived implementation plans. They
  are not current navigation links and are intentionally not rewritten.

The canonical archive index, current-state document, LIVE compatibility pointers, and
maintained subsystem documentation have their own link checks. Historical archive files
are non-authoritative and must not be used as operational procedures without independent
verification. This historical-link audit is intentionally non-blocking; only maintained
navigation and active-document links are release gates.
