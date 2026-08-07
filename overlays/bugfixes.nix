{ inputs, _final, prev }:
{
  # 2026-08-04: gjs/gtk4/libsecret/qtbase dontCheck overrides REMOVED.
  # Cache-evidence audit: the VANILLA (checks-ON) derivations for all four
  # substitute from cache.nixos.org (narinfo HTTP 200):
  #   gjs 3qvw2ws…, gtk4 qq86wi0…, libsecret xplgg6b…, qt5.qtbase wmza0wv…
  # Hydra builds these WITH tests enabled and passing — the dontCheck flags
  # only re-forked the derivations off-cache, forcing the gtk4→chromium
  # family to recompile (same disease as the cups overlay fork, fixed 2026-08-04).
  # Removal restores those packages to cache substitution.

  # webkitgtk: KEPT — vanilla webkitgtk is genuinely NOT in cache.nixos.org
  # (404), so this is a real from-source build either way; dontCheck avoids
  # the pinned cluster sandbox's flaky test suite on the nexus builder.
  webkitgtk = prev.webkitgtk.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  # 2026-08-07: caddy caddytest/integration suite fails in the nix sandbox
  # (reverse_proxy health-checker test probes a %2F-encoded unix socket URL —
  # "invalid URL escape"; the suite also needs live ports). Vanilla caddy IS
  # in cache.nixos.org, but this cluster's nixpkgs rev pulls caddy 2.11.4
  # whose check phase re-runs the flaky integration suite on every fresh
  # (non-cached) build — e.g. sentry's zephyr-toplevel build. caddy-with-modules
  # already sets doCheck = false; align the base package.
  caddy = prev.caddy.overrideAttrs (old: {
    doCheck = false;
  });
}
