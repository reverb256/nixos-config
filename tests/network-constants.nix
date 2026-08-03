{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  # SSOT sources: modules/network-constants.nix was refactored (2026-07-24)
  # into a thin wrapper; the constants now live in kubernetes/cluster.nix
  # (subnet, host IPs, VIP, api port, cluster DNS) and
  # modules/network-options/default.nix (option defaults incl. ports, DNS).
  clusterSrc = builtins.readFile ../kubernetes/cluster.nix;
  optionsSrc = builtins.readFile ../modules/network-options/default.nix;

  expectedHosts = [
    "zephyr"
    "nexus"
    "forge"
    "sentry"
  ];

  hostPresent = host: lib.strings.hasInfix "${host}Ip =" clusterSrc;

  missingHosts = builtins.filter (h: !(hostPresent h)) expectedHosts;

  hasSubnet = lib.strings.hasInfix "10.1.1.0/24" clusterSrc;

  # Gateway default lives in network-options (cluster.gateway or "10.1.1.1")
  hasGateway = lib.strings.hasInfix "10.1.1.1" optionsSrc;

  expectedIPs = {
    zephyr = "10.1.1.110";
    nexus = "10.1.1.120";
    forge = "10.1.1.130";
    sentry = "10.1.1.140";
  };

  ipPresent = host: ip: lib.strings.hasInfix "${host}Ip = \"${ip}\"" clusterSrc;

  missingIPs = lib.filterAttrs (_host: ip: !(ipPresent _host ip)) expectedIPs;

  allIPs = lib.attrValues expectedIPs;
  uniqueIPs = lib.unique allIPs;
  noDuplicateIPs = builtins.length allIPs == builtins.length uniqueIPs;

  hasK8sVIP = lib.strings.hasInfix "vip = \"10.1.1.100\"" clusterSrc;
  hasK8sPort = lib.strings.hasInfix "apiPort = 6443" clusterSrc;

  hasLocalDNS = lib.strings.hasInfix "127.0.0.1" optionsSrc;

  hasTailscaleDomain = lib.strings.hasInfix "taila21e09.ts.net" optionsSrc;

  # Well-known ports are declared in the network-options ports submodule.
  requiredPorts = [
    "prometheus"
    "grafana"
    "node-exporter"
    "caddy-http"
    "caddy-https"
  ];

  missingPorts = builtins.filter (port: !(lib.strings.hasInfix "${port} = mkOption" optionsSrc)) requiredPorts;

  # svcOpts DNS uses service name (prevent regression of hostname-mismatch bug)
  hasSvcOptsSubmoduleFn = lib.strings.hasInfix "{name, ...}: {" optionsSrc;
  hasDnsWithServiceName = lib.strings.hasInfix ''"''${name}.''${namespace}.svc.cluster.local:''${toString port}"'' optionsSrc;

  isReadOnly = lib.strings.hasInfix "readOnly = true" optionsSrc;

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
