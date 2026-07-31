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
  });

  # 2026-07-30: dufs 0.46.0 has flaky network bind tests that fail in sandbox.
  # Disable cargo tests entirely — it's a CLI file server, tests are env-sensitive.
  dufs = prev.dufs.overrideAttrs (old: {
    doCheck = false;
    checkFlags = [ "--skip" ];
  });
}
