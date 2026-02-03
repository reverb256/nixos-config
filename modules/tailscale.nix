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
      default = ["10.1.1.0/24"];
      example = ["10.0.0.0/24"];
      description = "Routes to advertise to the Tailscale network";
    };

    advertiseExitNode = mkOption {
      type = types.bool;
      default = false;
      description = "Advertise this node as an exit node";
    };

    acceptRoutes = mkOption {
      type = types.bool;
      default = true;
      description = "Accept routes from Tailscale network";
    };

    useRoutingFeatures = mkOption {
      type = types.enum ["client" "server" "both"];
      default = "client";
      description = "Enable routing features";
    };

    enableSSH = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Tailscale SSH access";
    };
  };

  config = mkIf cfg.enable {
    # Enable IP forwarding for routing
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    services.tailscale = {
      enable = true;
      useRoutingFeatures = cfg.useRoutingFeatures;
    };

    # Configure tailscaled with auth key and settings
    systemd.services.tailscaled.serviceConfig = mkIf (cfg.advertiseRoutes != [] || cfg.advertiseExitNode) {
      Environment = mkIf (cfg.advertiseRoutes != []) [
        "TS_ADVERTISE_ROUTES=${builtins.concatStringsSep "," cfg.advertiseRoutes}"
      ] ++ mkIf cfg.enableSSH [
        "TS_SSH=true"
      ];
    };

    # Allow tailscale through firewall
    networking.firewall.interfaces.lo.allowedTCPPorts = [41641];
    networking.firewall.interfaces.lo.allowedUDPPorts = [41641];

    # Enable Tailscale SSH
    programs.tailscale.enableSSHForwarding = cfg.enableSSH;
  };
}
