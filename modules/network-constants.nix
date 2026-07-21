{lib, ...}: let
  # Import helpers that route to the SSOT (kubernetes/service-ports.nix + cluster.nix)
  helpers = import ./port-helpers.nix {inherit lib;};
  inherit (helpers) ports;
  inherit (helpers) cluster;
in {
  options = import ./network-options { inherit lib ports cluster; };
}
