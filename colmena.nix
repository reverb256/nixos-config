# Simplified Colmena Cluster Deployment Configuration
# Basic configuration for 4-node NixOS cluster
{
  # Import deployment options module
  inputs,
  lib,
  ...
}: let
  # Define the nixpkgs to use for evaluation
  nixpkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
in {
  # Meta configuration
  meta = {
    inherit nixpkgs;
  };

  # Default deployment settings for all nodes
  defaults = {
    deployment = {
      # Allow local deployment (useful for testing)
      allowLocalDeployment = true;
    };
  };

  # Node configurations
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
}