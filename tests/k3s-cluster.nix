{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  k3sSource = builtins.readFile ../modules/services/k3s-cluster.nix;

  extractCIDRs = let
    lines = lib.splitString "\n" k3sSource;
    cidrLines =
      builtins.filter (
        line: lib.strings.hasInfix "CIDR" line || lib.strings.hasInfix "clusterDNS" line
      )
      lines;
  in {
    hasClusterCIDR = lib.strings.hasInfix "10.42.0.0/16" k3sSource;
    hasServiceCIDR = lib.strings.hasInfix "10.43.0.0/16" k3sSource;
    hasClusterDNS = lib.strings.hasInfix "10.43.0.10" k3sSource;
  };

  # The module derives addresses from the canonical cluster option set, so
  # assert the source expressions rather than interpolated runtime values.
  requiredSans = [
    "cluster.kubernetes.vip"
    "cluster.hosts.zephyr.ip"
    "cluster.hosts.nexus.ip"
    "cluster.hosts.forge.ip"
    "cluster.hosts.sentry.ip"
    "\"kubernetes\""
    "\"kubernetes.default\""
    "\"kubernetes.default.svc\""
    "\"kubernetes.default.svc.cluster.local\""
    "\"cluster.local\""
    "\"localhost\""
    "\"127.0.0.1\""
  ];

  missingSans = builtins.filter (san: !(lib.strings.hasInfix san k3sSource)) requiredSans;

  requiredDisabled = [
    "traefik"
    "metrics-server"
  ];

  missingDisabled =
    builtins.filter (
      comp: !(lib.strings.hasInfix "\"${comp}\"" k3sSource)
    )
    requiredDisabled;

  requiredServerPorts = [
    "10250"
    "6443"
    "2379"
    "2380"
  ];

  missingServerPorts =
    builtins.filter (
      port: !(lib.strings.hasInfix port k3sSource)
    )
    requiredServerPorts;

  usesMkOptionDefault = lib.strings.hasInfix "mkOptionDefault" k3sSource;

  hasServerRole = lib.strings.hasInfix "\"server\"" k3sSource;
  hasAgentRole = lib.strings.hasInfix "\"agent\"" k3sSource;

  hasNvidiaOption = lib.strings.hasInfix "nvidia.enable" k3sSource;

  hasCalicoOption = lib.strings.hasInfix "calico" k3sSource;

  cidrs = extractCIDRs;

  allChecks = {
    inherit (cidrs) hasClusterCIDR;
    inherit (cidrs) hasServiceCIDR;
    inherit (cidrs) hasClusterDNS;

    allSansPresent = missingSans == [];

    allDisabledPresent = missingDisabled == [];

    allServerPortsPresent = missingServerPorts == [];
    inherit usesMkOptionDefault;

    inherit hasServerRole;
    inherit hasAgentRole;

    inherit hasNvidiaOption;
    inherit hasCalicoOption;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks = allChecks;
  failures = builtins.attrNames failures;
  passed = builtins.attrNames failures == [];
}
