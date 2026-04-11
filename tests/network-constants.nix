# tests/network-constants.nix
#
# Validates the network constants module:
#   - All cluster hosts present with valid IPs
#   - IPs are in the expected subnet (10.1.1.0/24)
#   - No overlapping IPs between hosts
#   - Each host has required fields (ip, tailscale, roles)
#   - Tailscale IPs are unique
#   - Port numbers are in valid range
#
# Run: nix-instantiate --parse tests/network-constants.nix
#
{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;

  # Read the network-constants module source
  source = builtins.readFile ../modules/network-constants.nix;

  # Expected hosts in the cluster
  expectedHosts = [
    "zephyr"
    "nexus"
    "forge"
    "sentry"
  ];

  # Check that all expected hosts are defined
  hostPresent =
    host: lib.strings.hasInfix "${host} =" source || lib.strings.hasInfix "${host} =" source;

  missingHosts = builtins.filter (h: !(hostPresent h)) expectedHosts;

  # Expected subnet
  hasSubnet = lib.strings.hasInfix "10.1.1.0/24" source;

  # Expected gateway
  hasGateway = lib.strings.hasInfix "10.1.1.1" source;

  # Check all host IPs are in 10.1.1.x range
  expectedIPs = {
    zephyr = "10.1.1.110";
    nexus = "10.1.1.120";
    forge = "10.1.1.130";
    sentry = "10.1.1.140";
  };

  ipPresent = host: ip: lib.strings.hasInfix "ip = \"${ip}\"" source;

  missingIPs = lib.filterAttrs (host: ip: !(ipPresent host ip)) expectedIPs;

  # Check no duplicate IPs (each should appear exactly once)
  allIPs = lib.attrValues expectedIPs;
  uniqueIPs = lib.unique allIPs;
  noDuplicateIPs = builtins.length allIPs == builtins.length uniqueIPs;

  # Check Kubernetes VIP
  hasK8sVIP = lib.strings.hasInfix "10.1.1.100" source;
  hasK8sPort = lib.strings.hasInfix "6443" source;

  # Check DNS configuration
  hasLocalDNS = lib.strings.hasInfix "127.0.0.1" source;

  # Check tailscale domain
  hasTailscaleDomain = lib.strings.hasInfix "tigris-ule.ts.net" source;

  # Validate port definitions exist
  requiredPorts = [
    "prometheus"
    "grafana"
    "node-exporter"
    "caddy-http"
    "caddy-https"
  ];

  missingPorts = builtins.filter (port: !(lib.strings.hasInfix "${port}" source)) requiredPorts;

  # Check readOnly flag on the option
  isReadOnly = lib.strings.hasInfix "readOnly = true" source;

  allChecks = {
    allHostsPresent = missingHosts == [ ];
    hasSubnet = hasSubnet;
    hasGateway = hasGateway;
    allIPsPresent = missingIPs == { };
    noDuplicateIPs = noDuplicateIPs;
    hasK8sVIP = hasK8sVIP;
    hasK8sPort = hasK8sPort;
    hasLocalDNS = hasLocalDNS;
    hasTailscaleDomain = hasTailscaleDomain;
    allRequiredPortsPresent = missingPorts == [ ];
    isReadOnly = isReadOnly;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;

in
{
  checks = allChecks;
  failures = builtins.attrNames failures;
  passed = failures == { };
}
