# Tailscale - Secure mesh VPN
# Based on OpenClaw patterns for secure networking

{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.tailscale-custom;
in {
  options.services.tailscale-custom = {
    enable = mkEnableOption "Tailscale mesh VPN";

    advertiseRoutes = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["10.0.0.0/24"];
      description = "Routes to advertise to the Tailscale network";
    };

    acceptRoutes = mkOption {
      type = types.bool;
      default = false;
      description = "Accept routes from Tailsacle network";
    };

    useRoutingFeatures = mkOption {
      type = types.enum ["client" "server" "both"];
      default = "client";
      description = "Enable routing features";
    };
  };

  config = mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = cfg.useRoutingFeatures;
    };

    # Allow tailscale through firewall
    networking.firewall.interfaces.lo.allowedTCPPorts = [41641];  # Tailscale wireguard
    networking.firewall.interfaces.lo.allowedUDPPorts = [41641];  # Tailscale wireguard

    # Optional: advertise routes to the tailnet
    # This requires the --advertise-routes flag in tailscaled
    # systemd.services.tailscaled.serviceConfig.Environment = [
    #   "TS_ADVERTISE_ROUTES=${builtins.concatStringsSep "," cfg.advertiseRoutes}"
    # ];
  };
}
