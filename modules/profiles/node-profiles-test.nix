let
  lib = import <nixpkgs/lib>;

  mkTestConfig =
    profileModule:
    let
      networkingHelper = import ./networking.nix { inherit lib; };
      mkNetworkingConfig = networkingHelper.mkNetworkingConfig;
    in
    {
      inherit mkNetworkingConfig;
    };

  helper = mkTestConfig null;

  testProfiles = {
    zephyr = {
      enable = true;
      nvidia = {
        enable = true;
        multiGpu = true;
      };
      networking = {
        ipAddress = "10.1.1.110";
        interfaceName = "enp38s0";
        unboundListenAddress = "10.1.1.110";
        wireless.enable = true;
      };
      firewallExtraTCPPorts = [
        9757
        18789
        18790
        19898
        1234
        8080
        53317
        8888
      ];
      firewallExtraUDPPorts = [
        9757
        9758
        9759
        27031
        27036
        5353
        9947
        53317
      ];
    };

    nexus = {
      enable = true;
      nvidia = {
        enable = true;
        multiGpu = false;
      };
      networking = {
        ipAddress = "10.1.1.120";
        interfaceName = "enp7s0";
        unboundListenAddress = "10.1.1.120";
        wireless.enable = true;
      };
      firewallExtraTCPPorts = [ 10250 ];
      firewallExtraTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      firewallExtraUDPPorts = [ ];
    };

    forge = {
      enable = true;
      nvidia = {
        enable = true;
        multiGpu = true;
      };
      amdgpu = {
        enable = true;
        wayland = true;
      };
      networking = {
        ipAddress = "10.1.1.130";
        interfaceName = "enp0s31f6";
        unboundListenAddress = "10.1.1.130";
        wireless.enable = false;
      };
      disableDHCP = true;
      firewallExtraTCPPorts = [ 10250 ];
      firewallExtraTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      firewallExtraUDPPorts = [ ];
    };

    sentry = {
      enable = true;
      amdgpu = {
        enable = true;
        wayland = true;
      };
      networking = {
        ipAddress = "10.1.1.140";
        interfaceName = "enp7s0";
        unboundListenAddress = "10.1.1.140";
        wireless.enable = false;
      };
      firewallExtraTCPPorts = [ 10250 ];
      firewallExtraTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      firewallExtraUDPPorts = [ ];
    };
  };

  testNetworking =
    let
      mkTest =
        name: profile:
        let
          result = helper.mkNetworkingConfig profile;
          clusterNet = result.clusterNetworking.content or null;
        in
        {
          ${name} = {
            hasClusterNetworking = clusterNet != null;
            correctIP =
              if clusterNet != null then clusterNet.ipAddress == profile.networking.ipAddress else false;
            correctInterface =
              if clusterNet != null then clusterNet.interfaceName == profile.networking.interfaceName else false;
            unboundEnabled = if clusterNet != null then clusterNet.unbound.enable == true else false;
            hasFirewallTCPPorts = result.networking.firewall.allowedTCPPorts != [ ];
            dhcpDisabled = result.networking.dhcpcd.enable.content or true != false || name != "forge";
          };
        };
    in
    lib.foldl' (acc: name: acc // (mkTest name testProfiles.${name})) { } (
      builtins.attrNames testProfiles
    );

  allIPs = lib.mapAttrsToList (_: p: p.networking.ipAddress) testProfiles;
  uniqueIPs = lib.unique allIPs;
  allIPsUnique = builtins.length allIPs == builtins.length uniqueIPs;

  allInterfaces = lib.mapAttrsToList (_: p: p.networking.interfaceName) testProfiles;
  uniqueInterfaces = lib.unique allInterfaces;
  allInterfacesUnique = builtins.length allInterfaces == builtins.length uniqueInterfaces;

  allTests = {
    networking = testNetworking;
    ipsUnique = allIPsUnique;
    interfacesUnique = allInterfacesUnique;
    profileCount = builtins.length (builtins.attrNames testProfiles);

    zephyrHasNvidia = testProfiles.zephyr.nvidia.enable == true;
    zephyrMultiGpu = testProfiles.zephyr.nvidia.multiGpu == true;
    forgeHasBothGPUs =
      testProfiles.forge.nvidia.enable == true && testProfiles.forge.amdgpu.enable == true;
    sentryHasAmd = testProfiles.sentry.amdgpu.enable == true;
    nexusSingleGpu = testProfiles.nexus.nvidia.multiGpu == false;
  };
in
allTests
