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
  assertPresent = name: pattern:
    pkgs.runCommand "peakminer-${name}" { inherit pattern; } ''
      if ! grep -qF "$pattern" ${module}; then
        echo "FAIL: '$pattern' is missing from ${module}" >&2
        exit 1
      fi
      echo "OK: '$pattern' is present in ${module}" >&2
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
  # Tight marker: the assertion code itself (not just any `stratum+` substring,
  # which would also match the default value, comments, and host configs).
  hasPoolSchemeAssertion = assertPresent "has-pool-scheme-assertion-code"
    "assertion = lib.all (i:";

  # ── Kryptex Stratum V1 auth compatibility ────────────────────────────────
  legacyAuthInDefault  = assertPresent "legacy-auth-in-default" "--legacy-auth";
}
