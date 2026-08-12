{ lib, fetchFromCratesIo, rustPlatform }:
rustPlatform.buildRustPackage rec {
  pname = "switchyard-server";
  version = "0.2.0"; # pin exact published version; adjust if newer is needed
  src = fetchFromCratesIo {
    pname = "switchyard-server";
    version = version;
    # sha256 and cargoHash will be filled in from the first nix-build run error message.
    # To get them: build once on nexus with this placeholder, capture the error
    # message that says e.g. "got: sha256-... expected: sha256-...", then fill both in.
    sha256 = "sha256-placeholder";
  };
  cargoHash = "cargoHash-placeholder";
  meta = with lib; {
    description = "LLM routing proxy from NVIDIA Switchyard";
    license = licenses.asl20;
    mainProgram = "switchyard-server";
  };
}
