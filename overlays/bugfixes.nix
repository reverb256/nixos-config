{ inputs, _final, prev }:

{
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
