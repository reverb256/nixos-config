{lib, ...}: let
  # Import the service port registry (SSOT)
  rawPorts = import ../kubernetes/service-ports.nix;
  # Import cluster constants (SSOT for subnet, VIP, host IPs, etc)
  rawCluster = import ../kubernetes/cluster.nix;
in {
  # Re-export raw imports for modules that need the raw attrset
  ports = rawPorts;
  cluster = rawCluster;

  # Get a specific port by service name
  getPort = name: rawPorts.${name} or (builtins.trace "Port ${name} not found" null);

  # Get multiple ports as an attrset
  getPorts = names:
    builtins.intersectAttrs (builtins.listToAttrs (map (n: {
        name = n;
        value = n;
      })
      names))
    rawPorts;

  # Get port for a service with fallback
  getPortWithFallback = name: fallback: rawPorts.${name} or fallback;

  # Check if a port is defined
  hasPort = name: lib.attrNames rawPorts == name;

  # Get all port names
  allPortNames = lib.attrNames rawPorts;

  # Get nodePort for a service (for NodePort access)
  getNodePort = name: rawPorts.${name} or (builtins.trace "NodePort ${name} not found" null);
}
