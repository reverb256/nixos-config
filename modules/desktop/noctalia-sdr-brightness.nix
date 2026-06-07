{
  lib,
  pkgs,
  config,
  ...
}: let
  needsPatch = config.programs.niri.enable;
in {
  nixpkgs.overlays = lib.mkIf needsPatch [
    (final: prev: {
      noctalia-shell = prev.noctalia-shell.overrideAttrs (old: {
        preFixup =
          (old.preFixup or "")
          + ''
            echo "Applying SDR brightness patch to BrightnessService.qml..."
            ${prev.python3}/bin/python3 ${./patch-noctalia-brightness.py} \
              $out/share/noctalia-shell/Services/Hardware/BrightnessService.qml
            echo "SDR brightness patch applied successfully"
          '';
      });
    })
  ];
}
