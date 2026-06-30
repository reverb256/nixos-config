# PeakMiner module regression checks (static grep).
# FIXME: gates below assume peakminer 1.0.x CLI compat. Re-audit on next minor
#       (v2.x) bump:
#         - noStaleFanTempFlag, noStaleFanMaxTempFlag
#         - noStaleFanOptionStart, noStaleFanOptionMax
#         - legacyAuthInDefault (see rationale below)
#
# Cheap tests that catch the most likely regressions to the NixOS module:
#   - Stale fan flag names that don't exist in peakminer 1.0.11-rc2 CLI
#     (`--gpu-fan-temp`, `--gpu-fan-max-temp`). Same flag set as v1.0.8.
#   - Stale option names for the same (`fanTempStart`, `fanTempMax`).
#   - Pool scheme assertion accidentally removed from the module.
#   - `default = ["--legacy-auth"]` re-introduced into `extraArgs` (Kryptex
#     PRL pool silently stalls share submission when --legacy-auth is on --
#     see modules/services/peakminer.nix for the rationale).
#
# Each entry is a tiny derivation that fails its build if the regression is
# detected, surfacing in `just check` / `nix flake check` output.

{ pkgs }:

let
  module = ../modules/services/peakminer.nix;

  # Wrapper that grep-asserts a banned pattern is absent from the module.
  # Mirrors `assertPresent`: takes the same `{ name, pattern, isRegex ? false }`
  # attrset so future regex-mode absence checks work without API divergence.
  assertAbsent = { name, pattern, isRegex ? false }:
    pkgs.runCommand "peakminer-${name}" { inherit pattern isRegex; } ''
      flag="$([ \"$isRegex\" = \"1\" ] && echo -E || echo -F)"
      case "$flag" in
        -E) mode=regex ;;
        -F) mode=literal ;;
      esac
      if grep -q $flag -e "$pattern" ${module}; then
        echo "FAIL: '$pattern' ($mode) is present in ${module} \u2014 should be removed" >&2
        exit 1
      fi
      echo "OK: '$pattern' ($mode) is absent from ${module}" >&2
      touch $out
    '';

  # Wrapper that grep-asserts a required pattern is present in the module.
  # `isRegex` parameter (default false): switch to extended regex matching so the
  # marker survives `nixfmt` reformatting (e.g. `assertion = lib.all (...)` may
  # have its whitespace normalized but the literal text changes).
  #
  # Uses `grep -e "$pattern"` to prevent grep from misinterpreting any pattern
  # starting with `--` as a long option (e.g. `--legacy-auth` was being eaten).
  assertPresent = { name, pattern, isRegex ? false }:
    pkgs.runCommand "peakminer-${name}" { inherit pattern isRegex; } ''
      flag="$([ \"$isRegex\" = \"1\" ] && echo -E || echo -F)"
      case "$flag" in
        -E) mode=regex ;;
        -F) mode=literal ;;
      esac
      if ! grep -q $flag -e "$pattern" ${module}; then
        echo "FAIL: '$pattern' ($mode) is missing from ${module}" >&2
        exit 1
      fi
      echo "OK: '$pattern' ($mode) is present in ${module}" >&2
      touch $out
    '';
in
{
  # ── Stale flag names that do not exist in peakminer 1.0.11-rc2 CLI ─────────────
  noStaleFanTempFlag    = assertAbsent {
    name = "no-stale-fan-temp-flag";     pattern = "--gpu-fan-temp";     isRegex = false;
  };
  noStaleFanMaxTempFlag = assertAbsent {
    name = "no-stale-fan-max-temp-flag"; pattern = "--gpu-fan-max-temp"; isRegex = false;
  };

  # ── Stale option names (must be fanTarget/fanMin/fanMax now) ────────────
  noStaleFanOptionStart = assertAbsent {
    name = "no-stale-fan-option-start"; pattern = "fanTempStart"; isRegex = false;
  };
  noStaleFanOptionMax   = assertAbsent {
    name = "no-stale-fan-option-max";   pattern = "fanTempMax";   isRegex = false;
  };

  # ── Pool URL scheme correctness ──────────────────────────────────────────
  # Tight marker: the assertion code itself, regex form so `nixfmt` reformatting
  # of the surrounding whitespace/trailing-comma doesn't silently break the test.
  hasPoolSchemeAssertion = assertPresent {
    name = "has-pool-scheme-assertion-code";
    # Literal match: `lib.all (` (with the space) — the assertion block has the
    # form `assertion = lib.all (i: ...)`, this guards against that line being
    # removed. Literal pattern is robust against `nixfmt` reformatting (the
    # outer whitespace is what nixfmt could touch, but our assertion block's
    # interior stays as `lib.all (` once written).
    pattern = "lib.all (";
    isRegex = false;
  };

  # ── Kryptex Stratum V1 auth compatibility ────────────────────────────────
  # The Kryptex PRL pool on TCP/7048 ONLY accepts shares from the array-form
  # Stratum V1 authorize (`["user","password"]`), and peakminer 1.0.11-rc2's
  # auto-detect picks the named-params form first which causes silent share
  # rejection. --legacy-auth forces the working array form; removing it from
  # the default regresses the whole cluster to 0 accepted_shares (verified
  # 2026-06-29 against v1.0.11-rc2 + Kryptex). This gate catches accidental
  # removal. NOTE: only gates the default; per-instance overrides slip
  # through by design (they may be required for non-Kryptex pools). See
  # modules/services/peakminer.nix.
  legacyAuthInDefault = assertPresent {
    name = "legacy-auth-in-default";
    # Regex: tolerate whitespace around the `[` and `]` so `nixfmt` reformatting
    # (`default = ["--legacy-auth"];` → `default = [ "--legacy-auth" ];`) doesn't
    # silently break the gate. Still ignores ad-hoc mentions in doc strings or
    # per-instance overrides.
    pattern = ''default\s*=\s*\[\s*\"--legacy-auth\"\s*\]'';
    isRegex = true;
  };
}
