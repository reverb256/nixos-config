{
  description = "gitlawb Nix flake: prebuilt binaries, overlay, NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      perSystem = flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
        let
          pkgs = import nixpkgs { inherit system; };
          inherit (pkgs) lib stdenv fetchurl;
          version = "0.7.0";

          gitlawb-src = fetchurl {
            url = "https://github.com/gitlawb/node/releases/download/v${version}/gitlawb-node-${version}-x86_64-unknown-linux-musl.tar.gz";
            sha256 = "sha256-wozpwZXT000Foi1Wz/sc0MpTKLzU4isS2ny9y1IPqJo=";
          };

          gitlawb-bin = stdenv.mkDerivation {
            pname = "gitlawb";
            inherit version;
            src = gitlawb-src;
            sourceRoot = ".";

            dontConfigure = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              find . -type f -executable | while read -r bin; do
                name=$(basename "$bin")
                cp "$bin" "$out/bin/$name"
                chmod +x "$out/bin/$name"
              done
              runHook postInstall
            '';

            meta = with lib; {
              description = "gitlawb: self-hosted decentralized git (gl + git-remote-gitlawb + gitlawb-node)";
              homepage = "https://gitlawb.com";
              license = licenses.mit;
              platforms = platforms.linux;
              maintainers = [ ];
            };
          };
        in {
          packages = {
            default = gitlawb-bin;
            gitlawb = gitlawb-bin;
            gl = gitlawb-bin;
            git-remote-gitlawb = gitlawb-bin;
            gitlawb-node = gitlawb-bin;
          };

          overlays.default = final: prev: {
            gitlawb = {
              package = gitlawb-bin;
              gl = gitlawb-bin;
              remoteHelper = gitlawb-bin;
              node = gitlawb-bin;
            };
          };
        });
    in
    perSystem // {
      nixosModule = ./nixos-module.nix;
    };
}
