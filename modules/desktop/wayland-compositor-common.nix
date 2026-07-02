{
  config,
  lib,
  pkgs,
  inputs,
  hostName,
  ...
}: let
  niriEnabled = config.programs.niri.enable or false;
  anyCompositor = niriEnabled;
  
  noctaliaInput = inputs.noctalia or (builtins.getEnv "NOCTALIA_INPUT");
  noctaliaAvailable = noctaliaInput != null && noctaliaInput ? packages && noctaliaInput.packages ? ${pkgs.stdenv.hostPlatform.system};
  
  getNoctalia = pkgs: if noctaliaAvailable
    then noctaliaInput.packages.${pkgs.stdenv.hostPlatform.system}.default
    else pkgs.noctalia-shell;

in {
  config = lib.mkIf anyCompositor {
    environment.systemPackages = [
      (getNoctalia pkgs)

      pkgs.cliphist

      pkgs.wf-recorder

      pkgs.gpu-screen-recorder

      pkgs.adwaita-icon-theme

        (pkgs.tesseract.override {languages = pkgs.tesseract.languages.eng;})
      ];

      services.gnome.gnome-keyring.enable = lib.mkForce false;
      services.gnome.gcr-ssh-agent.enable = lib.mkDefault false;
      
      # Update documentation references to noctalia-shell -> noctalia
      # Note: Documentation files are informational only
    };
  }
