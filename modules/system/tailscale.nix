{
  lib,
  config,
  ...
}: let
  inherit (lib) mkIf mkOption types mkDefault;
in {
  options.services.tailscale-cluster = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Tailscale with cluster-standard settings";
    };
    role = mkOption {
      type = types.enum ["workstation" "server" "mining"];
      default = "server";
      description = "Host role - maps to the tailnet ACL tag (tag:<role>)";
    };
    advertiseRoutes = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Subnets to advertise (e.g. [\"10.1.1.0/24\"])";
    };
    authKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "sops-managed preauth key file (tagged, non-expiring join)";
    };
    acceptDns = mkOption {
      type = types.bool;
      default = true;
      description = "Accept MagicDNS (must be on for hostname addressing)";
    };
    ssh = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Tailscale SSH broker";
    };
  };

  config = mkIf config.services.tailscale-cluster.enable {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      inherit (config.services.tailscale-cluster) authKeyFile;
      extraUpFlags =
        [ "--advertise-tags=tag:${config.services.tailscale-cluster.role}" ]
        ++ (lib.optional (config.services.tailscale-cluster.advertiseRoutes != [])
          "--advertise-routes=${lib.concatStringsSep "," config.services.tailscale-cluster.advertiseRoutes}")
        ++ (lib.optional (!config.services.tailscale-cluster.acceptDns) "--accept-dns=false");
      extraSetFlags =
        [ "--ssh=${if config.services.tailscale-cluster.ssh then "true" else "false"}" ]
        ++ (lib.optional config.services.tailscale-cluster.acceptDns "--accept-dns=true");
    };

    # Boot race fix (nixpkgs #527403) - REQUIRED for MagicDNS:
    # inert After= edge lets tailscaled claim DNS before connectivity exists.
    systemd.services.tailscaled = {
      wants = ["network-online.target"];
      after = ["network-online.target"];
      environment = {
        TS_LOG_LEVEL = "info";
        TS_DEBUG_FIREWALL_MODE = "nftables";
      };
    };

    # Cluster-standard firewall: tailscale0 is trusted, everything else is not.
    networking.firewall = {
      enable = true;
      trustedInterfaces = [config.services.tailscale.interfaceName];
      allowedUDPPorts = lib.mkOptionDefault [config.services.tailscale.port];
    };
  };
}
