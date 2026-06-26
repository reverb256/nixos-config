{lib}: let
  inherit (lib) mkIf;
in {
  mkNetworkingConfig = profileCfg: let
    networkingCfgBase =
      profileCfg.networking or {
        ipAddress = profileCfg.ipAddress or null;
        interfaceName = profileCfg.interfaceName or null;
        unboundListenAddress = profileCfg.unboundListenAddress or null;
        wireless = profileCfg.wireless or {enable = false;};
      };
    networkingCfg =
      networkingCfgBase
      // {
        wireless = networkingCfgBase.wireless or {enable = false;};
      };
  in {
    clusterNetworking = mkIf (networkingCfg.ipAddress != null) {
      enable = true;
      ipAddress = lib.mkDefault networkingCfg.ipAddress;
      interfaceName = lib.mkDefault networkingCfg.interfaceName;
      wireless = lib.mkDefault networkingCfg.wireless;
      unbound = {
        enable = true;
        listenAddress = networkingCfg.unboundListenAddress;
      };
    };

    networking.dhcpcd.enable = mkIf (profileCfg.disableDHCP or false) (lib.mkForce false);

    networking.firewall = {
      allowedTCPPorts = lib.mkOptionDefault (profileCfg.firewallExtraTCPPorts or []);
      allowedTCPPortRanges = lib.mkOptionDefault (profileCfg.firewallExtraTCPPortRanges or []);
      allowedUDPPorts = lib.mkOptionDefault (profileCfg.firewallExtraUDPPorts or []);
    };
  };
}
