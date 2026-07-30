{
  description = "gitlawb Nix flake: packages, overlay, NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      # System-scoped outputs (packages + overlays) — wrapped by eachSystem
      perSystem = flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
        let
          pkgs = import nixpkgs { inherit system; };
          inherit (pkgs) lib stdenv fetchurl rust-bin;
          rust-toolchain = rust-bin.stable.latest.default.override { targets = [ system ]; };
          platform = pkgs.makeRustPlatform {
            inherit rust-toolchain;
            cargo = rust-toolchain;
            rustc = rust-toolchain;
          };
          gitlawb-src = fetchurl {
            url = "https://github.com/gitlawb/node/archive/refs/tags/v0.7.0.tar.gz";
            sha256 = "sha256-3F5qmHxn4A/3Y4GWjBBP7v7yWVfJR5MQT59qZ3Ix/qI=";
          };
          buildGitlawbCrate = crateName: platform.buildRustPackage rec {
            pname = crateName;
            version = "0.7.0";
            buildInputs = [ pkgs.git pkgs.openssl ];
            src = gitlawb-src;
            sourceRoot = "node-0.7.0";
            cargoBuildFlags = [ "-p" crateName ];
            cargoTestFlags = [ "-p" crateName ];
            doCheck = false;
            meta = with lib; {
              description = "Gitlawb crate: ${crateName}";
              homepage = "https://gitlawb.com";
              license = licenses.mit;
              platforms = platforms.linux;
              maintainers = [ ];
            };
          };
          gl = buildGitlawbCrate "gl";
          git-remote-gitlawb = buildGitlawbCrate "git-remote-gitlawb";
          gitlawb-node = buildGitlawbCrate "gitlawb-node";
        in {
          packages = {
            inherit gl git-remote-gitlawb gitlawb-node;
            default = gl;
          };

          overlays.default = final: prev: {
            gitlawb = {
              inherit gl git-remote-gitlawb gitlawb-node;
              package = gl;
              remoteHelper = git-remote-gitlawb;
              node = gitlawb-node;
            };
          };
        });
    in
    perSystem // {
      # Non-system-scoped outputs — NOT wrapped by eachSystem
      nixosModule = ./nixos-module.nix;
    };
}
