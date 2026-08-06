{
  lib,
  rustPlatform,
  inputs,
  ...
}:
let
  forkSrc = inputs.secretspec-provider-sops;
  src = lib.cleanSource (toString forkSrc + "/provider-rust");
  lockFile = toString forkSrc + "/provider-rust/Cargo.lock";
in
rustPlatform.buildRustPackage {
  pname = "secretspec-provider-sops";
  version = "0.1.0";
  inherit src;
  cargoLock = {inherit lockFile;};
  doCheck = false;
  meta = {
    description = "SOPS provider backend and SecretSpec protocol dispatcher";
    homepage = "https://github.com/reverb256/secretspec-provider-sops";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
