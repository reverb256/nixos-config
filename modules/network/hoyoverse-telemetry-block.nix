{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkEnableOption;
in {
  options.networking.hoyoverse-telemetry-block = {
    enable = mkEnableOption "block Hoyoverse telemetry domains in /etc/hosts";
  };

  config = mkIf config.networking.hoyoverse-telemetry-block.enable {
    # Block Hoyoverse telemetry domains by redirecting to 0.0.0.0
    # Reference: https://github.com/an-anime-team/an-anime-game-launcher/issues/44
    # Reference: https://github.com/an-anime-team/the-honkers-railway-launcher/issues/57
    networking.extraHosts = lib.mkOptionDefault ''
      # Hoyoverse telemetry domains (all games: Genshin Impact, Honkai Star Rail, Zenless Zone Zero)
      0.0.0.0 log-upload-os.hoyoverse.com
      0.0.0.0 sg-public-data-api.hoyoverse.com
      0.0.0.0 hkrpg-log-upload-os.hoyoverse.com
      0.0.0.0 ys-log-upload-os.hoyoverse.com
      0.0.0.0 sdk-log-upload-os.hoyoverse.com
      # YuanShen spider/telemetry domains (CN version)
      0.0.0.0 overseauspider.yuanshen.com
      0.0.0.0 uspider.yuanshen.com
      0.0.0.0 osuspider.yuanshen.com
    '';
  };
}