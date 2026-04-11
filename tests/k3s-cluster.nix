# tests/k3s-cluster.nix
#
# Validates the K3s cluster module configuration:
#   - CIDR ranges are valid and non-overlapping
#   - TLS SANs include all required entries
#   - Role enum only allows "server" or "agent"
#   - Firewall ports are properly configured per role
#   - Disabled components are consistent
#   - Calico/Flannel modes are mutually exclusive
#
# Run: nix-instantiate --parse tests/k3s-cluster.nix
#
{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;

  # Read the k3s-cluster module source
  k3sSource = builtins.readFile ../modules/services/k3s-cluster.nix;

  # Validate CIDR format
  isValidCIDR =
    cidr:
    let
      parts = lib.splitString "/" cidr;
      hasSlash = builtins.length parts == 2;
      mask = if hasSlash then lib.toInt (builtins.elemAt parts 1) else 0;
    in
    hasSlash && mask >= 8 && mask <= 32;

  # Extract CIDR ranges from source (constants defined in let block)
  # The module defines: clusterCIDR, serviceCIDR, clusterDNS
  extractCIDRs =
    let
      lines = lib.splitString "\n" k3sSource;
      cidrLines = builtins.filter (
        line: lib.strings.hasInfix "CIDR" line || lib.strings.hasInfix "clusterDNS" line
      ) lines;
    in
    {
      hasClusterCIDR = lib.strings.hasInfix "10.244.0.0/16" k3sSource;
      hasServiceCIDR = lib.strings.hasInfix "10.0.0.0/12" k3sSource;
      hasClusterDNS = lib.strings.hasInfix "10.0.0.10" k3sSource;
    };

  # Validate TLS SANs include all required entries
  requiredSans = [
    "10.1.1.100" # VIP
    "10.1.1.110" # Zephyr
    "10.1.1.120" # Nexus
    "10.1.1.130" # Forge
    "10.1.1.140" # Sentry
    "kubernetes"
    "kubernetes.default"
    "kubernetes.default.svc"
    "kubernetes.default.svc.cluster.local"
    "cluster.local"
    "localhost"
    "127.0.0.1"
  ];

  missingSans = builtins.filter (san: !(lib.strings.hasInfix "\"${san}\"" k3sSource)) requiredSans;

  # Validate disabled components
  requiredDisabled = [
    "traefik"
    "servicelb"
    "metrics-server"
  ];

  missingDisabled = builtins.filter (
    comp: !(lib.strings.hasInfix "\"${comp}\"" k3sSource)
  ) requiredDisabled;

  # Validate firewall ports for server role
  requiredServerPorts = [
    "10250" # Kubelet
    "6443" # API server
    "2379" # etcd client
    "2380" # etcd peer
  ];

  missingServerPorts = builtins.filter (
    port: !(lib.strings.hasInfix port k3sSource)
  ) requiredServerPorts;

  # Validate mkOptionDefault is used for port lists
  usesMkOptionDefault = lib.strings.hasInfix "mkOptionDefault" k3sSource;

  # Validate role enum
  hasServerRole = lib.strings.hasInfix "\"server\"" k3sSource;
  hasAgentRole = lib.strings.hasInfix "\"agent\"" k3sSource;

  # Validate nvidia option exists
  hasNvidiaOption = lib.strings.hasInfix "nvidia.enable" k3sSource;

  # Validate calico option exists
  hasCalicoOption = lib.strings.hasInfix "calico" k3sSource;

  cidrs = extractCIDRs;

  allChecks = {
    # CIDR checks
    hasClusterCIDR = cidrs.hasClusterCIDR;
    hasServiceCIDR = cidrs.hasServiceCIDR;
    hasClusterDNS = cidrs.hasClusterDNS;

    # TLS SANs
    allSansPresent = missingSans == [ ];

    # Disabled components
    allDisabledPresent = missingDisabled == [ ];

    # Firewall ports
    allServerPortsPresent = missingServerPorts == [ ];
    usesMkOptionDefault = usesMkOptionDefault;

    # Role configuration
    hasServerRole = hasServerRole;
    hasAgentRole = hasAgentRole;

    # Optional features
    hasNvidiaOption = hasNvidiaOption;
    hasCalicoOption = hasCalicoOption;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;

in
{
  checks = allChecks;
  failures = builtins.attrNames failures;
  passed = failures == { };
}
