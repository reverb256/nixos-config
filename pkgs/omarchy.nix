{
  lib,
  stdenvNoCC,
  omarchy,
}:

# omarchy — basecamp/omarchy UX layer, consumed as a verbatim source tree
# (Tier 1 port, per issue #655/#656).
#
# Upstream installs to /usr/share/omarchy (the OMARCHY_PATH runtime root) and
# exposes bin/omarchy* on PATH. We reproduce that layout in the Nix store:
#   $out/share/omarchy/          — the full verbatim tree (bin, themes, shell,
#                                  config, default, applications, manual,
#                                  install, migrations, version)
#   $out/bin/omarchy*            — symlink farm so the `omarchy` router and its
#                                  ~160 `omarchy-*` commands resolve on PATH
#                                  exactly as upstream's /usr/bin layout does
#
# The router (bin/omarchy) locates its sibling commands via
#   OMARCHY_BIN_DIR=$(dirname "$BASH_SOURCE[0]")
# and every command resolves data via the OMARCHY_PATH env var (default
# /usr/share/omarchy). So the NixOS module that consumes this package must set
#   environment.sessionVariables.OMARCHY_PATH = "${omarchy}/share/omarchy";
# for themes/plugins/config/dots to resolve. Nothing here is compiled or
# patched — Tier 1 is byte-identical upstream, and upstream sync is a rev bump.
stdenvNoCC.mkDerivation {
  pname = "omarchy";
  version = lib.removeSuffix "\n" (builtins.readFile "${omarchy}/version");

  src = omarchy;

  # The only mutation: strip the .git dir (it's a flake=false fetch, so this is
  # normally absent) and skip the repo-only trees that are not part of the
  # runtime install (agents/, docs/, test/, plans/, .github/). Everything that
  # upstream's file-layout.md maps into /usr/share/omarchy stays verbatim.
  installPhase = ''
    runHook preInstall

    runtime_root="$out/share/omarchy"
    mkdir -p "$runtime_root" "$out/bin"

    # Runtime trees (mirror upstream's /usr/share/omarchy layout).
    for tree in bin themes shell config default applications manual install migrations; do
      if [ -d "$tree" ]; then
        cp -r "$tree" "$runtime_root/"
      fi
    done
    if [ -f version ]; then
      cp version "$runtime_root/version"
    fi
    # Branding assets resolved via $OMARCHY_PATH/<file> by
    # omarchy-show-logo / omarchy-branding-about / -screensaver, plus the
    # PNG/SVG that default/ symlinks (default/chromium/extensions/*/icon.png
    # -> ../../../../icon.png) resolve against.
    for asset in logo.txt icon.txt icon.png logo.svg; do
      [ -f "$asset" ] && cp "$asset" "$runtime_root/$asset"
    done

    # Symlink farm: bin/omarchy + every bin/omarchy-* onto PATH.
    # The router resolves OMARCHY_BIN_DIR from its own realpath, so symlinking
    # (rather than wrapping) keeps its dirname = $runtime_root/bin, where the
    # sibling commands actually live.
    for f in "$runtime_root/bin/omarchy" "$runtime_root/bin/omarchy-"*; do
      [ -e "$f" ] || continue
      ln -s "$f" "$out/bin/$(basename "$f")"
    done

    runHook postInstall
  '';

  meta = with lib; {
    description = "Omarchy UX layer — themes, router, plugins, shell, dots (verbatim Tier-1 port)";
    homepage = "https://github.com/basecamp/omarchy";
    license = licenses.mit;
    mainProgram = "omarchy";
    platforms = platforms.all;
  };
}
