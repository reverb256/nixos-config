{
  config,
  lib,
  pkgs,
  ...
}: let
  niriEnabled = config.programs.niri.enable or false;
  anyCompositor = niriEnabled;
in {
  config = lib.mkIf anyCompositor {
    environment.systemPackages = [
      pkgs.noctalia-shell

      pkgs.cliphist

      pkgs.wf-recorder

      pkgs.gpu-screen-recorder

      pkgs.adwaita-icon-theme

      (pkgs.tesseract.override {languages = pkgs.tesseract.languages.eng;})
    ];

    services.gnome.gnome-keyring.enable = lib.mkForce false;
    services.gnome.gcr-ssh-agent.enable = lib.mkDefault false;
  };
}
