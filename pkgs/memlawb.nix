{ lib, stdenv, bun, makeWrapper, memlawb }:

# memlawb — encrypted, zero-knowledge agent memory server (Bun app).
#
# Source comes from the `memlawb` flake input (git+https://github.com/Gitlawb/memlawb,
# pinned to a rev in flake.nix) and is copied verbatim into the Nix store. We do NOT
# compile a binary (buildBunApp) because the running service model is `bun run
# src/index.ts` — bun stays a runtime dependency and the server is launched from the
# store copy. Dependencies are vendored at build time via `bun install` into a
# store-local node_modules so the closure is self-contained.
#
# The upstream repo tracks a `bun.lock` (modern text lockfile), so installs are
# frozen for a reproducible dependency set; if no lockfile is present we fall back
# to an unfrozen install (the same fallback the service used at /persistent/memlawb).
stdenv.mkDerivation rec {
  pname = "memlawb";
  version = "0.1.0"; # keep in sync with package.json

  src = memlawb;

  nativeBuildInputs = [ bun makeWrapper ];

  # bun install fetches npm tarballs at build time. The fleet's nix sandbox
  # blocks network (sandbox = true everywhere), so this derivation must opt
  # out of the sandbox to reach registry.npmjs.org. This is the standard
  # escape hatch for build-time-fetching derivations; everything else stays
  # sandboxed. Without it the deploy fails with:
  #   error: ConnectionRefused downloading tarball <pkg>
  __noChroot = true;

  buildPhase = ''
    runHook preBuild
    if [ -f bun.lock ] || [ -f bun.lockb ]; then
      bun install --frozen-lockfile
    else
      bun install
    fi
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    # bun's install cache leaves symlinks into the build dir (node_modules/.cache);
    # they would dangle in the final store path and trip noBrokenSymlinks. Drop
    # the cache — it is only needed at install time, not at runtime.
    rm -rf node_modules/.cache
    mkdir -p "$out/share/memlawb"
    # Copy the full tree (server src + mcp client + bin + client + vendored
    # node_modules) into the store so the closure is self-contained.
    cp -r . "$out/share/memlawb"

    mkdir -p "$out/bin"
    makeWrapper "${bun}/bin/bun" "$out/bin/memlawb-server" \
      --add-flags "run" \
      --add-flags "$out/share/memlawb/src/index.ts"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Encrypted, zero-knowledge agent memory server (Bun, fs blobstore)";
    license = licenses.mit;
    mainProgram = "memlawb-server";
  };
}
