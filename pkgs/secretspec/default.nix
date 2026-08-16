{
  lib,
  rustPlatform,
  fetchCrate,
  ...
}:
# Upstream cachix/secretspec 0.19.1 with the native sops provider
# (integrated upstream in 0.17, PR cachix/secretspec#58). The reverb256
# sops-provider fork (0.16.0-fork.1) was deleted 2026-08-07 — upstream's
# native sops provider subsumed it. The cluster's secretspec.toml uses
# per-file sops:// provider aliases and SOPS_AGE_KEY_FILE (see
# modules/system/secretspec-validator.nix). See the 0.18 blog post:
# https://secretspec.dev/blog/secretspec-0-17-scopes-secrets-caching-age-and-systemd-credentials/
rustPlatform.buildRustPackage {
  pname = "secretspec";
  version = "0.19.1";
  src = fetchCrate {
    pname = "secretspec";
    version = "0.19.1";
    hash = "sha256-hntOPTOrCfVWE4MaNmXfPQ4WAlOG1CFG5/ykSyviJ3A=";
  };
  cargoHash = "sha256-KRC3b6AqSYxjSInULchYNQGm9hw97lDws0+stFZasmc=";
  doCheck = false;
  meta = with lib; {
    description = "Declarative secrets resolution with the native sops provider (upstream 0.19.1)";
    homepage = "https://github.com/cachix/secretspec";
    license = licenses.asl20;
    platforms = platforms.linux;
    mainProgram = "secretspec";
  };
}