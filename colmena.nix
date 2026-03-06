# Colmena Cluster Deployment Configuration
# Single-source-of-truth: Host definitions from flake.nix
{
  inputs,
  self,
  hosts,
  ...
}: let
  # ========================================================================
  # HELPER FUNCTION - Add deployment metadata to host config
  # ========================================================================
  mkHost = {
    hostName,
    targetHost,
  }: { ... }: {
    imports = [
      ./hosts/${hostName}/configuration.nix
    ];

    deployment = {
      inherit targetHost;
      targetUser = "j_kro";
      allowLocalDeployment = true;
    };
  };

  # ========================================================================
  # DEPLOYMENT METADATA - Target host addresses
  # Uses Tailscale DNS for reliable cluster connectivity
  # ========================================================================
  hostDeployment = {
    zephyr = { targetHost = "zephyr"; };
    nexus = { targetHost = "nexus"; };
    forge = { targetHost = "forge"; };
    sentry = { targetHost = "sentry"; };
  };

in {
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
    specialArgs = { inherit inputs self; };
  };

  # ========================================================================
  # GENERATE HOST CONFIGURATIONS
  # ========================================================================
  zephyr = mkHost {
    hostName = "zephyr";
    targetHost = hostDeployment.zephyr.targetHost;
  };

  nexus = mkHost {
    hostName = "nexus";
    targetHost = hostDeployment.nexus.targetHost;
  };

  forge = mkHost {
    hostName = "forge";
    targetHost = hostDeployment.forge.targetHost;
  };

  sentry = mkHost {
    hostName = "sentry";
    targetHost = hostDeployment.sentry.targetHost;
  };
}
