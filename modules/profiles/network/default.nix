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

  # NOTE: superseded by services.tailscale-cluster (modules/system/tailscale.nix,
  # wired per-node in modules/profiles/node-profiles.nix). Kept only for the
  # option surface; the env injection was removed 2026-08-16 (issue #653) to
  # eliminate the TS_ADVERTISE_ROUTES contradiction.
  config = {};
}
