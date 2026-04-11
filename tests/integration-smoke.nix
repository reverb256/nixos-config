# tests/integration-smoke.nix
#
# Integration smoke test for critical cluster services.
# Validates that key modules have proper structure to start:
#   - K3s (Kubernetes) module has all required options
#   - Caddy reverse proxy has valid configuration
#   - Monitoring stack (Prometheus, Grafana, exporters) present
#   - Tailscale mesh VPN configured
#   - Container scanning can be enabled
#   - NFS server/client present
#   - Network constants resolve properly
#
# This is a source-level validation (no nix eval).
# Run: nix-instantiate --parse tests/integration-smoke.nix
#
{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;

  # Module sources for smoke testing
  modules = {
    k3s = builtins.readFile ../modules/services/k3s-cluster.nix;
    caddy = builtins.readFile ../modules/services/caddy.nix;
    monitoring =
      if builtins.pathExists ../modules/services/monitoring/default.nix then
        builtins.readFile ../modules/services/monitoring/default.nix
      else
        "";
    tailscale = builtins.readFile ../modules/system/tailscale.nix;
    containerScanning = builtins.readFile ../modules/services/container-scanning.nix;
    networkConstants = builtins.readFile ../modules/network-constants.nix;
    ssh = builtins.readFile ../modules/system/ssh.nix;
    nfsServer =
      if builtins.pathExists ../modules/services/nfs-server.nix then
        builtins.readFile ../modules/services/nfs-server.nix
      else
        "";
  };

  # Check that a module has enable option
  hasEnableOption =
    source:
    lib.strings.hasInfix "mkEnableOption" source || lib.strings.hasInfix "enable = mkOption" source;

  # Check that a module uses mkIf for conditional config
  hasConditionalConfig =
    source: lib.strings.hasInfix "mkIf" source || lib.strings.hasInfix "mkMerge" source;

  # Smoke test results
  checks = {
    # K3s - Kubernetes control plane
    k3s = {
      hasModule = modules.k3s != "";
      hasEnable = hasEnableOption modules.k3s;
      hasConditionalConfig = hasConditionalConfig modules.k3s;
      hasRoleOption = lib.strings.hasInfix "role" modules.k3s;
      hasFirewallConfig = lib.strings.hasInfix "allowedTCPPorts" modules.k3s;
    };

    # Caddy - Reverse proxy
    caddy = {
      hasModule = modules.caddy != "";
      hasConfig = lib.strings.hasInfix "services.caddy" modules.caddy;
    };

    # Monitoring stack
    monitoring = {
      hasModule = modules.monitoring != "";
      importsPrometheus =
        lib.strings.hasInfix "prometheus" modules.monitoring
        || lib.strings.hasInfix "Prometheus" modules.monitoring;
      importsGrafana =
        lib.strings.hasInfix "grafana" modules.monitoring
        || lib.strings.hasInfix "Grafana" modules.monitoring;
    };

    # Tailscale - Mesh VPN
    tailscale = {
      hasModule = modules.tailscale != "";
      hasEnable = hasEnableOption modules.tailscale;
      hasPackage = lib.strings.hasInfix "tailscale" modules.tailscale;
    };

    # Container scanning
    containerScanning = {
      hasModule = modules.containerScanning != "";
      hasEnable = hasEnableOption modules.containerScanning;
      hasTrivy = lib.strings.hasInfix "trivy" modules.containerScanning;
      hasPodman = lib.strings.hasInfix "podman" modules.containerScanning;
    };

    # Network constants
    networkConstants = {
      hasModule = modules.networkConstants != "";
      hasSubnet = lib.strings.hasInfix "10.1.1.0/24" modules.networkConstants;
      hasHosts = builtins.all (h: lib.strings.hasInfix h modules.networkConstants) [
        "zephyr"
        "nexus"
        "forge"
        "sentry"
      ];
    };

    # SSH - Critical for remote access
    ssh = {
      hasModule = modules.ssh != "";
      hasSSHConfig =
        lib.strings.hasInfix "services.openssh" modules.ssh
        || lib.strings.hasInfix "programs.ssh" modules.ssh;
    };

    # NFS
    nfs = {
      hasServerModule = modules.nfsServer != "";
    };
  };

  # Flatten to pass/fail
  flattenChecks =
    attrs:
    lib.foldl' (
      acc: name:
      let
        val = builtins.getAttr name attrs;
      in
      if builtins.isAttrs val then acc // (flattenChecks val) else acc // { ${name} = val; }
    ) { } (builtins.attrNames attrs);

  flatChecks = flattenChecks checks;
  failures = lib.filterAttrs (_: v: v == false) flatChecks;

in
{
  services = builtins.mapAttrs (_: v: v) checks;
  passed = failures == { };
  failureCount = builtins.length (builtins.attrNames failures);
}
