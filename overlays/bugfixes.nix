{ inputs, _final, prev }:

{
  # 2026-07-30: Fix sentry closure build
  pkgs.gjs = prev.gjs.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  pkgs.gtk4 = prev.gtk4.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  pkgs.webkitgtk = prev.webkitgtk.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  pkgs.qt5.qtbase = prev.qt5.qtbase.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });
}
