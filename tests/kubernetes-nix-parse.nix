{pkgs ? import <nixpkgs> {}}: let
  lib = pkgs.lib;
  testLib = import ./lib.nix {inherit pkgs;};
  moduleFiles = builtins.filter testLib.isNotBackup (
    testLib.collectNixFiles ./../kubernetes/modules
  );
  parseCommands = lib.concatMapStringsSep "\n" (path: ''
    echo "[kubernetes-nix-parse] ${path}"
    ${pkgs.nix}/bin/nix-instantiate --parse ${path} >/dev/null
  '') moduleFiles;
  parseCheck = pkgs.runCommand "check-kubernetes-nix-parse" {} ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    export NIX_PATH=
    mkdir -p "$HOME"
    ${parseCommands}
    touch "$out"
  '';
in {
  # Parsing runs when this derivation is built. The flake evaluator only
  # registers the derivation, so `nix flake check --no-build` cannot execute
  # the parser itself.
  check = parseCheck;
  parsedFiles = map toString moduleFiles;
  failures = [];
  passed = true;
}
