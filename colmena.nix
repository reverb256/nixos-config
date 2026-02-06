# Colmena Cluster Deployment Configuration
# Modern flake-integrated configuration for 4-node NixOS cluster
# Uses proper module imports from flake.nix definitions
{
  # Import deployment options module
  inputs,
  lib,
  ...
}: let
  # Node definitions from flake.nix
  nodes = {
    zephyr = {
      imports = [
        # Base configuration
        ./configuration.nix
        # Host-specific configuration
        ./hosts/zephyr/configuration.nix
      ];
      deployment.targetHost = "10.1.1.110";
      deployment.targetUser = "j_kro";
      # SSH key configuration
      deployment.sshUser = "j_kro";
      deployment.sshKey = "/home/j_kro/.ssh/id_ed25519";
    };

    nexus = {
      imports = [
        ./configuration.nix
        ./hosts/nexus/configuration.nix
      ];
      deployment.targetHost = "10.1.1.120";
      deployment.targetUser = "j_kro";
      deployment.sshUser = "j_kro";
      deployment.sshKey = "/home/j_kro/.ssh/id_ed25519";
    };

    forge = {
      imports = [
        ./configuration.nix
        ./hosts/forge/configuration.nix
      ];
      deployment.targetHost = "10.1.1.130";
      deployment.targetUser = "j_kro";
      deployment.sshUser = "j_kro";
      deployment.sshKey = "/home/j_kro/.ssh/id_ed25519";
    };

    sentry = {
      imports = [
        ./configuration.nix
        ./hosts/sentry/configuration.nix
      ];
      deployment.targetHost = "10.1.1.140";
      deployment.targetUser = "j_kro";
      deployment.sshUser = "j_kro";
      deployment.sshKey = "/home/j_kro/.ssh/id_ed25519";
    };
  };
in {
  # Meta configuration - using modern flake integration
  meta = {
    # In modern flake-based Colmena, nixpkgs comes from the flake inputs
    # This avoids the "Passing a path to Nixpkgs as meta.nixpkgs is no longer accepted" error
    allowUnfree = true;
  };

  # Default deployment settings for all nodes
  defaults = {...}: {
    deployment = {
      # Allow local deployment (useful for testing)
      allowLocalDeployment = true;

      # Timeout for nix-copy-closure operations
      copyTimeout = 1800; # 30 minutes

      # Retry failed builds
      retry = 2;

      # Use incremental builds when possible
      incremental = true;

      # SSH optimization settings
      sshOptions = [
        "-o"
        "ConnectTimeout=10"
        "-o"
        "ServerAliveInterval=60"
        "-o"
        "ServerAliveCountMax=3"
      ];
    };
  };

  # Node configurations
  inherit nodes;
}
