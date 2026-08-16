{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  # Astral Key is consumed as a source tree (flake = false) and built with
  # nixpkgs' rustPlatform — the same pattern as the lix fork. Building only
  # the root crate (-p astral-key) skips the mosaic bridge sidecars, which
  # the cluster doesn't run here.
  astral-key = pkgs.rustPlatform.buildRustPackage {
    pname = "astral-key";
    version = "0.1.0";
    src = inputs.astral-key;
    cargoLock = {
      lockFile = inputs.astral-key + "/Cargo.lock";
    };
    cargoBuildFlags = ["-p" "astral-key"];
    # reqwest/ethers/sqlx pull openssl-sys; sqlx-sqlite links sqlite3.
    nativeBuildInputs = with pkgs; [pkg-config];
    buildInputs = with pkgs; [openssl sqlite];
  };
in {
  imports = [ (inputs.astral-key + "/nix/nixos-module.nix") ];

  services.astral-key = {
    enable = true;
    package = astral-key;

    # Old casdoor slot — the auth.lan Caddy block already proxies the
    # default route here (127.0.0.1:32556). Loopback-only: Caddy terminates
    # TLS on nexus and is the only consumer.
    listenAddress = "127.0.0.1";
    port = 32556;

    environment = {
      OIDC_ENABLED = "true";
      OIDC_ISSUER = "https://auth.lan";
      OIDC_CLIENT_ID = "astral-key-oidc";
      # Materialized from the SAME secret central-auth uses, so client_id +
      # secret stay in lockstep with oauth2-proxy.
      OIDC_CLIENT_SECRET_FILE = "/run/secrets/astral-key-oidc-client-secret";
      OIDC_SIGNING_KEY_FILE = "/run/secrets/astral-key-oidc-signing-key";
      OIDC_REDIRECT_URIS = "https://auth.lan/oauth2/callback";
      JWT_SECRET_FILE = "/run/secrets/astral-key-jwt-secret";

      # WebAuthn RP must match the site origin served by Caddy.
      FIDO2_RP_ID = "auth.lan";
      FIDO2_RP_NAME = "Astral Key";
      FIDO2_ORIGINS = "https://auth.lan";
      ASTRAL_WEB3_DOMAIN = "auth.lan";
    };
  };

  # Secrets must be materialized before the service starts.
  systemd.services.astral-key = {
    after = ["secretspec-creds.service"];
    requires = ["secretspec-creds.service"];
  };
}
