{ config, lib, ... }:
let
  cfg = config.cluster.config;
in {
  # Storage class definitions are applied via easykubenix or kubectl
  # This module documents the intended storage classes
  # Actual K8s manifests should be generated from these definitions
}
