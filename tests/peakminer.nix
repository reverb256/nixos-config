# PeakMiner module regression checks (static grep).
#
# Cheap tests that catch the most likely regressions to the NixOS module:
#   - Stale fan flag names that don't exist in peakminer 1.0.8
#     (`--gpu-fan-temp`, `--gpu-fan-max-temp`).
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
  # ── Stale flag names that do not exist in peakminer 1.0.8 CLI ─────────────
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
  # Kryptex PRL pool negotiates Stratum V1 named-params authorize and peakminer
  # 1.0.8 auto-detects this dialect. Adding --legacy-auth on this pool causes
  # jobs to flow but share submission to silently stall -- the array-form
  # authorize is accepted by the auth layer but shares never reach the share
  # queue. This gate catches any future re-introduction of --legacy-auth into
  # the `extraArgs` default as a regression. NOTE: only gates the default;
  # per-instance `extraArgs = [\u0022--legacy-auth\u0022]` overrides slip through
  # by design (they may be required for non-Kryptex pools). See
  # modules/services/peakminer.nix.
  noLegacyAuthInDefault = assertAbsent {
    name = "no-legacy-auth-in-default";
    # Regex: tolerate whitespace around the `[` and `]` so `nixfmt` reformatting
    # (`default = ["--legacy-auth"];` → `default = [ "--legacy-auth" ];`) doesn't
    # silently break the gate. Still ignores ad-hoc mentions in doc strings or
    # per-instance overrides where the flag could legitimately appear.
    pattern = ''default\s*=\s*\[\s*\"--legacy-auth\"\s*\]'';
    isRegex = true;
  };
}
