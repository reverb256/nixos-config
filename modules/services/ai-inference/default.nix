# AI Inference Service - Main Module Entry Point
#
# This file imports all sub-modules that together form the AI inference service.
# The module is split into:
#   options.nix           - Option declarations (types, defaults, descriptions)
#   config-assertions.nix - Configuration validation
#   config-backend.nix    - System packages, Prometheus, Redis
#   config-networking.nix - Firewall rules
#   gateway.nix           - API gateway server
#   router.nix            - Model routing logic
#   monitor.nix           - Prometheus metrics
#   health-monitor.nix    - Health check endpoints
#   auth/                 - Authentication backends
#   qdrant.nix            - Qdrant vector database
{
  imports = [
    ./options.nix
    ./config-assertions.nix
    ./config-backend.nix
    ./config-networking.nix
  ];
}
