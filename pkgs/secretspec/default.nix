{
  lib,
  rustPlatform,
  inputs,
  ...
}:
rustPlatform.buildRustPackage {
  pname = "secretspec";
  version = "0.16.0-fork.1";
  src = lib.cleanSource inputs.secretspec;
  buildAndTestSubdir = "secretspec";
  cargoLock.lockFile = "${inputs.secretspec}/Cargo.lock";
  buildNoDefaultFeatures = true;
  buildFeatures = ["cli" "sops"];
  doCheck = false;
  meta = with lib; {
    description = "Declarative secrets resolution with the cluster sops provider";
    homepage = "https://github.com/reverb256/secretspec";
    license = licenses.asl20;
    platforms = platforms.linux;
    mainProgram = "secretspec";
  };
}
