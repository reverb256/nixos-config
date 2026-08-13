# llama-swap — model swapping proxy for llama.cpp (mostlygeek/llama-swap v240)
#
# Transparent OpenAI-compatible proxy that owns a catalog of model definitions
# and hot-swaps the upstream llama-server when a request names a different
# model. Used across the fleet: zephyr runs it via home-manager; this package
# gives the NixOS system layer the same binary (nexus/forge/sentry).
#
# v240 is the version zephyr already runs (store path llama-swap-240). Not in
# the pinned nixpkgs rev — packaged here per nixpkgs' own llama-swap recipe
# (buildGoModule, version ldflags, excluded regression tools).
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
}: buildGoModule (finalAttrs: {
  pname = "llama-swap";
  version = "240";

  src = fetchFromGitHub {
    owner = "mostlygeek";
    repo = "llama-swap";
    tag = "v${finalAttrs.version}";
    hash = "sha256-3NlA4LnAJ1qCy1+Jcv6wrPg/7trQhpwx00Sk98V7ZdY=";
    leaveDotGit = true;
    postFetch = ''
      cd "$out"
      git rev-parse HEAD > $out/COMMIT
      date -u -d "@$(git log -1 --pretty=%ct)" "+%Y-%m-%dT%H:%M:%SZ" > $out/SOURCE_DATE_EPOCH
      find "$out" -name .git -print0 | xargs -0 rm -rf
    '';
  };

  vendorHash = "sha256-5mmciFAGe8ZEIQvXejhYN+ocJL3wOVwevIieDuokhGU=";

  nativeBuildInputs = [ versionCheckHook ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
  ];

  preBuild = ''
    ldflags+=" -X main.commit=$(cat COMMIT)"
    ldflags+=" -X main.date=$(cat SOURCE_DATE_EPOCH)"
    # proxy/ui_embed.go does //go:embed ui_dist but the GitHub tarball omits
    # the built web UI (see pkg.go.dev docs: 'the compilation requires the
    # folder proxy/ui_dist that does not exist within the source code').
    # Upstream-documented fix: provide a minimalist ui_dist/index.html so the
    # embed pattern resolves. The /ui route degrades to a placeholder.
    mkdir -p proxy/ui_dist
    cat > proxy/ui_dist/index.html <<'HTML'
    <!doctype html><html><head><title>llama-swap</title></head>
    <body><h1>llama-swap</h1><p>UI bundle not built; API is at /v1.</p></body></html>
    HTML
  '';

  excludedPackages = [
    "misc/process-cmd-test"
    "misc/benchmark-chatcompletion"
  ];

  doCheck = false;

  doInstallCheck = true;
  versionCheckProgramArg = "-version";

  meta = {
    homepage = "https://github.com/mostlygeek/llama-swap";
    description = "Model swapping for llama.cpp (or any local OpenAI-compatible server)";
    license = lib.licenses.mit;
    mainProgram = "llama-swap";
  };
})
