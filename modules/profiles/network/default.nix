# modules/profiles/network/default.nix --- Network profiles
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkOption;
in {
  options.profiles.network.tailscale = {
    enable = mkEnableOption "Tailscale VPN";
    advertiseRoutes = mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Routes to advertise on Tailscale";
    };
  };

  config = lib.mkIf config.profiles.network.tailscale.enable {
    services.tailscale.enable = true;

    systemd.services.tailscaled.environment = lib.mkMerge [
      (lib.mkIf (config.profiles.network.tailscale.advertiseRoutes != []) {
        TS_ADVERTISE_ROUTES = builtins.concatStringsSep " " config.profiles.network.tailscale.advertiseRoutes;
      })
      {TS_SSH = "true";}
    ];
  };
}
