{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.haven-desktop;
in
{
  options.programs.haven-desktop = {
    enable = lib.mkEnableOption "Haven Desktop - private chat with per-app audio sharing";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.haven-desktop
    ];
  };
}
