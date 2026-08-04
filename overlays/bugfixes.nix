{ inputs, _final, prev }:

# Per-package test suppressions required by the pinned cluster sandbox
# (build-time test suites that fail under the sandbox/network restrictions).
# KEEP NARROW: never widen to a global `doCheck = false`. Re-evaluate every
# entry on each nixpkgs roll-forward — upstream often fixes these and the
# entry becomes removable (tracked: docs/audit-2026-08-04-bandaids.md WS5).
{
  # gjs/gtk4/webkitgtk/qtbase: their test suites require dbus session, Xvfb
  # and network in the sandbox; failures are environmental, not regressions
  # we own. Verify against the pinned nixpkgs on roll-forward (upstream
  # may already disable these).
  gjs = prev.gjs.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  gtk4 = prev.gtk4.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  webkitgtk = prev.webkitgtk.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  qtbase = prev.qt5.qtbase.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  # 2026-07-31: libsecret's DBus test-collection check aborts in the
  # pinned cluster sandbox (NoReply from the session bus, SIGABRT). Keep
  # this workaround package-specific; do not disable checks globally.
  libsecret = prev.libsecret.overrideAttrs (_old: {
    doCheck = false;
  });

}
