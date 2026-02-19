{
  description = "HyperWhisper - Real-time speech-to-text application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, rust-overlay, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay { inherit system; }) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Use the rust toolchain from overlay
        rustToolchain = pkgs.rust-bin.stable."1.83.0".default;

        runtimeDeps = with pkgs; [
          webkitgtk
          gtk3
          libappindicator-gtk3
          librsvg
          onnxruntime
          wtype
          ydotool
        ];

        buildDeps = with pkgs; [
          rustToolchain
          pkg-config
          patchelf
          bun
          nodejs-slim
          cargo-tauri
          wrapGAppsHook
        ];

      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "hyperwhisper";
          version = "0.1.0";

          src = pkgs.lib.cleanSource ./.;

          nativeBuildInputs = buildDeps;
          buildInputs = runtimeDeps;

          cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
            src = ./src-tauri;
            hash = "sha256-jj1Rov0DgulNQDFSwc95Vr7o1wDntAEKMbSebc0GZl0=";
          };

          buildPhase = ''
            runHook preBuild

            # Setup cargo vendor
            mkdir -p .cargo
            cat > .cargo/config.toml <<EOF
        [source.crates-io]
        replace-with = "vendored-sources"

        [source.vendored-sources]
        directory = "${cargoDeps}"
        EOF

            # Copy config to src-tauri for Tauri to find
            mkdir -p src-tauri/.cargo
            cp .cargo/config.toml src-tauri/.cargo/

            # Build frontend with bun
            export HOME=$(mktemp -d)
            bun install --frozen-lockfile
            bun run build

            # Verify frontend was built
            echo "=== Frontend build verification ==="
            ls -la dist/
            echo "======================================"

            # Use cargo-tauri to build with embedded frontend
            cargo tauri build --no-bundle --ci

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            cp src-tauri/target/release/hyperwhisper $out/bin/

            # Wrap with proper library paths
            wrapProgram $out/bin/hyperwhisper \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeDeps}" \
              --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.wtype pkgs.ydotool ]}"

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Real-time speech-to-text desktop application";
            homepage = "https://github.com/hyperwhisper/app";
            license = licenses.gpl3Plus;
            platforms = platforms.linux;
            mainProgram = "hyperwhisper";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = buildDeps ++ runtimeDeps;

          LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath runtimeDeps}";
          shellHook = ''
            export WEBKIT_DISABLE_COMPOSITING_MODE=1
          '';
        };
      }
    );
}
