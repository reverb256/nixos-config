# PeakMiner module regression checks (static grep).
#
# Cheap tests that catch the most likely regressions to the NixOS module:
#   - Stale fan flag names that don't exist in peakminer 1.0.8
#     (`--gpu-fan-temp`, `--gpu-fan-max-temp`).
#   - Stale option names for the same (`fanTempStart`, `fanTempMax`).
#   - Pool scheme assertion accidentally removed from the module.
#   - `--legacy-auth` removed from `extraArgs` default (Kryptex hangs without it).
#
# Each entry is a tiny derivation that fails its build if the regression is
# detected, surfacing in `just check` / `nix flake check` output.

{ pkgs }:

let
  module = ../modules/services/peakminer.nix;

  # Wrapper that grep-asserts a banned pattern is absent from the module.
  assertAbsent = name: pattern:
    pkgs.runCommand "peakminer-${name}" { inherit pattern; } ''
      if grep -qF "$pattern" ${module}; then
        echo "FAIL: '$pattern' is present in ${module} \u2014 should be removed" >&2
        exit 1
      fi
      echo "OK: '$pattern' is absent from ${module}" >&2
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
  noStaleFanTempFlag    = assertAbsent "no-stale-fan-temp-flag"     "--gpu-fan-temp";
  noStaleFanMaxTempFlag = assertAbsent "no-stale-fan-max-temp-flag" "--gpu-fan-max-temp";

  # ── Stale option names (must be fanTarget/fanMin/fanMax now) ────────────
  noStaleFanOptionStart = assertAbsent "no-stale-fan-option-start" "fanTempStart";
  noStaleFanOptionMax   = assertAbsent "no-stale-fan-option-max"   "fanTempMax";

  # ── Pool URL scheme correctness ──────────────────────────────────────────
  # Tight marker: the assertion code itself, regex form so `nixfmt` reformatting
  # of the surrounding whitespace/trailing-comma doesn't silently break the test.
  hasPoolSchemeAssertion = assertPresent {
    name = "has-pool-scheme-assertion-code";
    # `lib\.all\(` anchors to the actual call form (followed by `(`) so future
    # identifiers like `lib.allSomething` don't silently satisfy the gate.
    pattern = "assertion[[:space:]]*=[[:space:]]*lib\\.all\\(";
    isRegex = true;
  };

  # ── Kryptex Stratum V1 auth compatibility ────────────────────────────────
  legacyAuthInDefault  = assertPresent {
    name = "legacy-auth-in-default";
    pattern = "--legacy-auth";
    isRegex = false;
  };
}
