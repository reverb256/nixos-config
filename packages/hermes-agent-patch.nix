# packages/hermes-agent-patch.nix
#
# Patches hermes-agent v0.10.0 run_agent.py to scope `think=false` to
# Ollama-style endpoints only. Without this, NVIDIA NIM and other OpenAI-
# compatible providers reject the unknown `think` field with HTTP 400.
#
# Bug: hermes-agent sends `extra_body["think"] = False` to ALL custom
# providers when reasoning_effort is "none". NVIDIA NIM returns 400.
# Fix: only send `think=false` when the base_url looks like Ollama.
#
# Approach: create a new wrapper package identical to the original, but
# with an overlay directory prepended to PYTHONPATH containing the patched
# run_agent.py. Python resolves the overlay first, shadowing the original.

{
  lib,
  stdenv,
  makeWrapper,
  hermes-pkg,
}:

let
  # Extract the venv store path from the wrapper script.
  # The wrapper contains: exec "/nix/store/...-hermes-agent-env/bin/hermes" "$@"
  wrapperContent = builtins.readFile "${hermes-pkg}/bin/hermes";
  venvMatches = builtins.match ".*(/nix/store/[a-z0-9]+-hermes-agent-env).*" wrapperContent;
  venvPath =
    if venvMatches == null then
      throw "hermes-agent-patch: could not extract venv path from wrapper"
    else
      builtins.head venvMatches;

  # Locate the original run_agent.py to patch
  originalRunAgent = "${venvPath}/lib/python3.11/site-packages/run_agent.py";

  # Overlay directory containing the patched run_agent.py.
  # This will be prepended to PYTHONPATH so Python finds it before the venv copy.
  overlay = stdenv.mkDerivation {
    pname = "hermes-think-fix-overlay";
    version = "0.10.0-patch1";

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/site-packages

      # Copy the original file and apply the patch
      cp ${originalRunAgent} $out/site-packages/run_agent.py
      chmod u+w $out/site-packages/run_agent.py

      # ── The patch ──────────────────────────────────────────────────────
      # Original (line 6789):
      #   if self.provider == "custom" and self.reasoning_config and isinstance(self.reasoning_config, dict):
      #
      # Fixed: additionally require the base_url to look like an Ollama endpoint.
      # Uses the same detection patterns already proven in the codebase:
      #   - "ollama" in _base_url_lower  (from _is_ollama_glm_backend, line 2133)
      #   - ":11434" in _base_url_lower  (Ollama's default port)
      #   - is_local_endpoint(base_url)   (imported from model_metadata, line 91)
      #
      # NVIDIA NIM (https://integrate.api.nvidia.com/v1) fails all three checks
      # → think=false is skipped → no HTTP 400.

      substituteInPlace $out/site-packages/run_agent.py \
        --replace-fail \
          'if self.provider == "custom" and self.reasoning_config and isinstance(self.reasoning_config, dict):' \
          'if self.provider == "custom" and self.reasoning_config and isinstance(self.reasoning_config, dict) and ("ollama" in self._base_url_lower or ":11434" in self._base_url_lower or (self.base_url and is_local_endpoint(self.base_url))):'

      runHook postInstall
    '';
  };

in
stdenv.mkDerivation {
  pname = "hermes-agent";
  version = "0.10.0";

  dontUnpack = true;
  dontBuild = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    # Copy everything from the original package (skills, web_dist, tui, etc.)
    cp -r ${hermes-pkg} $out
    chmod -R u+w $out

    # Replace each wrapper script to:
    #   1. Keep all the original env vars (PATH suffixes, HERMES_* vars)
    #   2. Prepend our overlay to PYTHONPATH so Python finds patched run_agent.py
    for bin in $out/bin/hermes $out/bin/hermes-agent $out/bin/hermes-acp; do
      [ -f "$bin" ] || continue

      # Inject PYTHONPATH prepend before the exec line.
      # The overlay's site-packages comes first, shadowing the venv's run_agent.py.
      sed -i "/^exec /i export PYTHONPATH=\"${overlay}/site-packages\''${PYTHONPATH:+:\$PYTHONPATH}\"" "$bin"
    done

    runHook postInstall
  '';

  passthru = {
    inherit overlay venvPath;
    originalPackage = hermes-pkg;
    patchDescription = "Scope think=false to Ollama/local endpoints only (fixes NVIDIA NIM HTTP 400)";
  };

  meta = hermes-pkg.meta or { };
}
