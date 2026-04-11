# Profile Networking Helper
#
# Reusable function for generating networking configuration from profile data.
# Extracted from node-profiles.nix so other modules can derive networking
# config from the same profile attributes without duplicating the logic.
#
# Usage:
#   mkNetworkingConfig profileCfg
#
# Where profileCfg has:
#   networking.ipAddress         - static IP (null = skip)
#   networking.interfaceName     - network interface
#   networking.unboundListenAddress - DNS listen address
#   networking.wireless.enable   - enable wireless
#
# Returns a NixOS config attrset with clusterNetworking, networking.firewall, etc.
{ lib }:
let
  inherit (lib) mkIf;
in
{
  mkNetworkingConfig =
    profileCfg:
    let
      # Extract networking config - handle both nested and direct formats
      networkingCfgBase =
        profileCfg.networking or {
          ipAddress = profileCfg.ipAddress or null;
          interfaceName = profileCfg.interfaceName or null;
          unboundListenAddress = profileCfg.unboundListenAddress or null;
          wireless = profileCfg.wireless or { enable = false; };
        };
      # Ensure wireless has a default value
      networkingCfg = networkingCfgBase // {
        wireless = networkingCfgBase.wireless or { enable = false; };
      };
    in
    {
      # Cluster networking (static IP, unbound DNS)
      # Only applied when ipAddress is set
      clusterNetworking = mkIf (networkingCfg.ipAddress != null) {
        enable = true;
        inherit (networkingCfg) ipAddress;
        inherit (networkingCfg) interfaceName;
        wireless = lib.mkDefault networkingCfg.wireless;
        unbound = {
          enable = true;
          listenAddress = networkingCfg.unboundListenAddress;
        };
      };

      # DHCP control
      networking.dhcpcd.enable = mkIf (profileCfg.disableDHCP or false) (lib.mkForce false);

      # Extra firewall rules from profile
      networking.firewall = {
        allowedTCPPorts = lib.mkOptionDefault (profileCfg.firewallExtraTCPPorts or [ ]);
        allowedTCPPortRanges = lib.mkOptionDefault (profileCfg.firewallExtraTCPPortRanges or [ ]);
        allowedUDPPorts = lib.mkOptionDefault (profileCfg.firewallExtraUDPPorts or [ ]);
      };
    };
}
