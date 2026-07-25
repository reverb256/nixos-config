{ config, lib, pkgs, ... }:
# Module: cluster.localSealSupport — opt-in impure-eval for secretspec local-fork hosts.
#
# Why this exists:
#   Nix flakes use `pure-eval = true` by default (Lix 2.95.2+, Nix ≥2.4).
#   Pure-eval disallows `builtins.pathExists` on absolute paths outside the
#   flake's directory tree. The cachix-fork checkout at
#   /home/j_kro/Projects/secretspec-core and the provider-rust fork at
#   /home/j_kro/Projects/secretspec/provider-rust are external absolute
#   paths. With pure-eval enabled, the buildRustPackage branch in
#   pkgs/secretspec/default.nix silently evaluates `useLocalFork = false`
#   and falls through to the upstream cachix tarball — which has NO sops://
#   provider module. Cluster rebuild still succeeds but at runtime
#   `secretspec check` errors with "Provider backend 'sops' not found".
#
# Why opt-in (manual gate):
#   `pure-eval = false` is unprobed filesystem access during evaluation.
#   Default-false keeps non-fork hosts (= CI runners, fresh-clone hosts)
#   safely evaluate under pure-eval semantics. Hosts with the local fork
#   checkout opt in by setting:
#
#     cluster.localSealSupport = true;
#
#   in their per-host configuration.nix.
#
# When to enable:
#   ✅ Enable on hosts with /home/j_kro/Projects/secretspec-core (cachix fork)
#      AND/OR /home/j_kro/Projects/secretspec/provider-rust (NDJSON dispatcher fork)
#      checked out, that ALSO build pkgs.secretspec via `nix build` (vs.
#      consuming a closure copied via nix-copy-closure from another host).  #      Validate-local (`just secretspec-validate-local`) must pass with
  #      "[ci] OK: secretspec built from local fork" — without impure-eval,
  #      that line never appears and the build falls back to the upstream
  #      tarball silently.
  #   ❌ Do NOT enable on CI runners / fresh-clone hosts: they don't have the fork
  #      AND impure-eval lowers the evaluation-time safety boundary. Those
  #      environments legitimately use the upstream cachix tarball fallback.
  # ─── DEFAULT-COUPLED to sops-secrets-registry.enable (Option B implemented) ──────
  # The default for `cluster.localSealSupport` is now auto-coupled to
  # `config.services.sops-secrets-registry.enable` — any host with the sops
  # registry enabled ALSO gets impure-eval accessible for the cachix-fork
  # local-checkout probe. Mirrors the validator pattern in
  # modules/system/secretspec-validator.nix. Operators who want to opt OUT
  # still can (set `cluster.localSealSupport = false;`).
  #
  # Hosts without the local fork checkout (CI runners, fresh-clone hosts) get
  # the upstream cachix tarball fallback path (no sops:// registration, the
  # validator fails loudly at runtime — fail-loud by design). Those hosts
  # SHOULD set `cluster.localSealSupport = false;` (or be a host without
  # sops-secrets-registry.enable) so pure-eval semantics aren't relaxed.
  # ────────────────────────────────────────────────────────────────
{
  options.cluster.localSealSupport = lib.mkOption {
    type = lib.types.bool;
    # Auto-couple default: any host with the sops-registry enabled ALSO gets
    # impure-eval accessible. Mirrors the validator pattern.
    default = config.services.sops-secrets-registry.enable;
    defaultText = lib.literalExpression "config.services.sops-secrets-registry.enable";
    description = ''
      Allow Nix flake eval to probe absolute paths outside the flake tree
      (e.g., /home/j_kro/Projects/secretspec-core), enabling the cachix-fork
      buildRustPackage branch in pkgs/secretspec/{default,provider-sops}.nix.

      Default is auto-coupled to `services.sops-secrets-registry.enable` —
      any host with sops-registry on also gets impure-eval on. Set to false
      explicitly on CI runners / fresh-clone hosts where the local fork
      checkout isn't present.
    '';
  };

  config = lib.mkIf config.cluster.localSealSupport {
    # Setting pure-eval = false here is the NixOS-module-level companion
    # to the per-invocation `--option pure-eval false` flags in justfile
    # (validate-local, secretspec-rebuild, build, hermes-update*, deploy-nexus).
    # Without either, the cluster's nixos-rebuild switch|test chain falls
    # through to the upstream cachix tarball at secretspec build-time, and
    # the validator unit on multi-user.target ends up running a binary
    # without sops:// — silent resolution drift at runtime.
    nix.settings.pure-eval = false;
  };
}
