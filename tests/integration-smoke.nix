{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  modules = {
    k3s = builtins.readFile ../modules/services/k3s-cluster.nix;
    caddy = builtins.readFile ../modules/services/caddy.nix;
    monitoring =
      if builtins.pathExists ../modules/services/monitoring/default.nix
      then builtins.readFile ../modules/services/monitoring/default.nix
      else "";
    tailscale = builtins.readFile ../modules/system/tailscale.nix;
    containerScanning = builtins.readFile ../modules/services/container-scanning.nix;
    # Network identity is owned by the cluster constants and typed inventory,
    # not by the NixOS option shim in modules/network-constants.nix.
    networkConstants = builtins.readFile ../kubernetes/cluster.nix;
    hostInventory = builtins.attrNames (import ../contracts/host-inventory.nix).hosts;
    ssh = builtins.readFile ../modules/system/ssh.nix;
  };

  hasEnableOption = source:
    lib.strings.hasInfix "mkEnableOption" source || lib.strings.hasInfix "enable = mkOption" source;

  hasConditionalConfig = source: lib.strings.hasInfix "mkIf" source || lib.strings.hasInfix "mkMerge" source;

  checks = {
    k3s = {
      hasModule = modules.k3s != "";
      hasEnable = hasEnableOption modules.k3s;
      hasConditionalConfig = hasConditionalConfig modules.k3s;
      hasRoleOption = lib.strings.hasInfix "role" modules.k3s;
      hasFirewallConfig = lib.strings.hasInfix "allowedTCPPorts" modules.k3s;
    };

    caddy = {
      hasModule = modules.caddy != "";
      hasConfig = lib.strings.hasInfix "services.caddy" modules.caddy;
    };

    monitoring = {
      hasModule = modules.monitoring != "";
      importsPrometheus =
        lib.strings.hasInfix "prometheus" modules.monitoring
        || lib.strings.hasInfix "Prometheus" modules.monitoring;
      importsGrafana =
        lib.strings.hasInfix "grafana" modules.monitoring
        || lib.strings.hasInfix "Grafana" modules.monitoring;
    };

    tailscale = {
      hasModule = modules.tailscale != "";
      hasEnable = lib.strings.hasInfix "services.tailscale" modules.tailscale
        && lib.strings.hasInfix "enable =" modules.tailscale;
      hasPackage = lib.strings.hasInfix "tailscale" modules.tailscale;
    };

    containerScanning = {
      hasModule = modules.containerScanning != "";
      hasEnable = hasEnableOption modules.containerScanning;
      hasTrivy = lib.strings.hasInfix "trivy" modules.containerScanning;
      hasPodman = lib.strings.hasInfix "podman" modules.containerScanning;
    };

    networkConstants = {
      hasModule = modules.networkConstants != "";
      hasSubnet = lib.strings.hasInfix "10.1.1.0/24" modules.networkConstants;
      hasHosts = builtins.all (h: builtins.elem h modules.hostInventory) [
        "zephyr"
        "nexus"
        "forge"
        "sentry"
      ];
    };

    ssh = {
      hasModule = modules.ssh != "";
      hasSSHConfig =
        lib.strings.hasInfix "services.openssh" modules.ssh
        || lib.strings.hasInfix "programs.ssh" modules.ssh;
    };
  };

  flattenChecks = attrs:
    lib.foldl' (
      acc: name: let
        val = builtins.getAttr name attrs;
      in
        if builtins.isAttrs val
        then acc // (flattenChecks val)
        else acc // {${name} = val;}
    ) {} (builtins.attrNames attrs);

  flatChecks = flattenChecks checks;
  failures = lib.filterAttrs (_: v: v == false) flatChecks;
in {
  services = builtins.mapAttrs (_: v: v) checks;
  passed = builtins.attrNames failures == [];
  failureCount = builtins.length (builtins.attrNames failures);
}
