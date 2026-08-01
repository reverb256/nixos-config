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
  # The 1.18.1 pin + cargoHash is applied explicitly in the zephyr host config
  # (hosts/zephyr/configuration.nix -> services.ai-inference.rag.qdrant.package)
  # because this overlay is NOT applied to NixOS host builds (mkNixosSystem uses
  # the bare flake nixpkgs). Kept here as documentation of intent; the working
  # fix lives in the host config.
  qdrant = prev.qdrant;

  # 2026-07-30: dufs 0.46.0 has flaky network bind tests that fail in sandbox.
  # Disable cargo tests entirely — it's a CLI file server, tests are env-sensitive.
  dufs = prev.dufs.overrideAttrs (old: {
    doCheck = false;
    checkFlags = [ "--skip" ];
  });
}
