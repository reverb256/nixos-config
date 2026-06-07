{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  source = builtins.readFile ../modules/network-constants.nix;

  expectedHosts = [
    "zephyr"
    "nexus"
    "forge"
    "sentry"
  ];

  hostPresent = host: lib.strings.hasInfix "${host} =" source || lib.strings.hasInfix "${host} =" source;

  missingHosts = builtins.filter (h: !(hostPresent h)) expectedHosts;

  hasSubnet = lib.strings.hasInfix "10.1.1.0/24" source;

  hasGateway = lib.strings.hasInfix "10.1.1.1" source;

  expectedIPs = {
    zephyr = "10.1.1.110";
    nexus = "10.1.1.120";
    forge = "10.1.1.130";
    sentry = "10.1.1.140";
  };

  ipPresent = host: ip: lib.strings.hasInfix "ip = \"${ip}\"" source;

  missingIPs = lib.filterAttrs (_host: ip: !(ipPresent _host ip)) expectedIPs;

  allIPs = lib.attrValues expectedIPs;
  uniqueIPs = lib.unique allIPs;
  noDuplicateIPs = builtins.length allIPs == builtins.length uniqueIPs;

  hasK8sVIP = lib.strings.hasInfix "10.1.1.100" source;
  hasK8sPort = lib.strings.hasInfix "6443" source;

  hasLocalDNS = lib.strings.hasInfix "127.0.0.1" source;

  hasTailscaleDomain = lib.strings.hasInfix "taila21e09.ts.net" source;

  requiredPorts = [
    "prometheus"
    "grafana"
    "node-exporter"
    "caddy-http"
    "caddy-https"
  ];

  missingPorts = builtins.filter (port: !(lib.strings.hasInfix "${port}" source)) requiredPorts;

  # svcOpts DNS uses service name (prevent regression of hostname-mismatch bug)
  hasSvcOptsSubmoduleFn = lib.strings.hasInfix "{ name, ... }:" source;
  hasDnsWithServiceName = lib.strings.hasInfix ''"''${name}.''${namespace}.svc.cluster.local:''${toString port}";'' source;

  isReadOnly = lib.strings.hasInfix "readOnly = true" source;

  allChecks = {
    allHostsPresent = missingHosts == [];
    inherit hasSubnet;
    inherit hasGateway;
    allIPsPresent = missingIPs == {};
    inherit noDuplicateIPs;
    inherit hasK8sVIP;
    inherit hasSvcOptsSubmoduleFn;
    inherit hasDnsWithServiceName;
    inherit hasLocalDNS;
    inherit hasTailscaleDomain;
    allRequiredPortsPresent = missingPorts == [];
    inherit isReadOnly;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks = allChecks;
  failures = builtins.attrNames failures;
  passed = failures == {};
}
