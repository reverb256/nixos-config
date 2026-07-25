# Issue #8: cluster-mode description field de-indent

**Priority:** LOW (whitespace; doesn't affect eval)  \n**Status:** Open  \n**Created:** 2026-07-25  \n**Origin:** Drift-cycle Stream 5c of comprehensive plan — prior session left a long
description `mkOption` field over-indented relative to surrounding module convention  \n**Depends on:** Issue #1 cluster-wide-validation (parallelizable)  \n**Blocks:** nothing; no eval change

## Context

`modules/system/secretspec-cluster-mode.nix` declares the `cluster.localSealSupport`
option with a `description = "...";` field. The description string is long and was edited
across multiple sessions; over time it accumulated leading spaces inside the string
literal and the `mkOption` block's own indentation got out of sync with surrounding
code. Specifically, the `description = ''...'';` block sits at 4-space indent while
the surrounding `mkOption { ... }` siblings sit at 6-space indent.

Today this is benign (Nix tolerates whitespace inside string literals seamlessly), but:
- `alejandra` formatter flags the mismatched indentation in its diff output, which is
  cosmetic noise we should still clean up.
- Future maintainers who run the formatter on the file (`just lint`) will see a large
  diff that obscures real changes.
- The drift-cycle Stream 3d lint pass cited this as a `alejandra` finding.

## Acceptance Criteria

- `modules/system/secretspec-cluster-mode.nix` line containing the description's `mkOption`
  block has consistent indentation matching surrounding `mkOption` declarations in the
  same file.
- `alejandra --check modules/system/secretspec-cluster-mode.nix` exits 0 (no delta).
- `nix-instantiate --parse modules/system/secretspec-cluster-mode.nix` exits 0 (no parse
  regression from the whitespace change).
- `just secretspec-validate-local` still exits 0 (no functional change).

## Approach

1. Open `modules/system/secretspec-cluster-mode.nix`; identify the `description = ''...'';`
   block inside the `cluster.localSealSupport` option.
2. Compare indent depth with sibling `mkOption` declarations in the same file (search
   `^[[:space:]]*description = ''` in nearby lines).
3. Run `alejandra --check modules/system/secretspec-cluster-mode.nix` to confirm
   formatter expectations.
4. Adjust the indent levels of the `description = ''` block + the `default = ...` block
   that follows.
5. Re-run the formatter to ensure the file round-trips cleanly.
6. Re-run `just secretspec-validate-local` for the lossless check.

## Risk

- Pure whitespace change → zero functional risk in this case.
- String literal content: if the string contains `'''` (which would terminate the
  multiline string), the intent might be `\n'''` etc — visual resync may consume those.
  Mitigate by re-reading the entire `''...''` block before/after and confirming the
  literal content is unchanged.
- If the description contains tab characters mixed with spaces, the formatter will
  normalize them and the diff may include large whitespace deltas.

## Related

- `modules/system/secretspec-cluster-mode.nix` (target file)
- `alejandra` formatter configuration (Nix project default)
- Issue #2 (CI gating — runs same lint pass)
- `.pre-commit-config.yaml` — would surface this if added
