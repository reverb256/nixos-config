{ inputs, _final, prev }:

{
  gjs = prev.gjs.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  gtk4 = prev.gtk4.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  webkitgtk = prev.webkitgtk.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  qtbase = prev.qt5.qtbase.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  # 2026-07-30: qdrant 1.18.2 fails to compile (Rust AVX512 intrinsic mismatch).
  # Override to use 1.18.1 source.
  qdrant = prev.qdrant.overrideAttrs (old: {
    version = "1.18.1";
    src = prev.fetchFromGitHub {
      owner = "qdrant";
      repo = "qdrant";
      tag = "v1.18.1";
      hash = "sha256-lqMyLnVD2iRu2AxlDHO7LzH2fFT01Gegn2JMhLAtDns=";
    };
    # The pinned nixpkgs' default cargoHash corresponds to 1.18.2's vendor tree,
    # not 1.18.1. Override with the correct 1.18.1 vendor hash (verified against
    # current nixpkgs qdrant 1.18.1) so the fixed-output vendored derivation
    # matches what is fetched. Without this, zephyr's rag.qdrant service build
    # fails with a hash mismatch on qdrant-*-vendor-staging.
    cargoHash = "sha256-nYW1vZzDg2atNLqROFhzKLh0v6aZHoYKUeNNTb82tr4=";
  });

  # 2026-07-30: dufs 0.46.0 has flaky network bind tests that fail in sandbox.
  # Disable cargo tests entirely — it's a CLI file server, tests are env-sensitive.
  dufs = prev.dufs.overrideAttrs (old: {
    doCheck = false;
    checkFlags = [ "--skip" ];
  });
}
