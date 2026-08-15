# Shared Hermes A2A mesh peers — one source of truth for the 4-host mesh.
#
# Dendritic pattern: Nix manages the peer STRUCTURE (url, capabilities,
# timeout). Token values stay in each host's ~/.hermes/config.yaml (hermes
# owns them; NEVER put tokens in the Nix store — the emitter deep-merges
# per-peer so existing token fields survive). Enable inbound A2A per host
# via managedGatewayA2a (port 9900).
{
  config,
  lib,
  ...
}: let
  # Cluster host IPs — read from the same central cluster inventory that
  # networking uses, so peer URLs can never drift from the DNS/firewall.
  cluster = config.networking.cluster or {};
  ipOf = host: (cluster.hosts.${host}.ip or null);
in {
  options.services.hermes-a2a = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the shared A2A mesh peer definitions for this host.";
    };
  };

  config = lib.mkIf (config.services.hermes-a2a.enable && config.services.hermes-cli.enable or false) {
    services.hermes-cli.managedGatewayA2a = {
      enabled = true;
      extra = {
        port = 9900;
      };
    };

    services.hermes-cli.managedA2aAgents =
      # Peers we can reach (all mesh hosts; self entries are harmless —
      # config.yaml already carries the local gateway's own entry).
      lib.filterAttrs (_: v: v != null) {
        hermes-sentry = lib.mkIf (ipOf "sentry" != null) {
          url = "http://${ipOf "sentry"}:9900";
          timeout = 300;
          capabilities = ["infra" "site-agency" "ai"];
        };
        hermes-nexus = lib.mkIf (ipOf "nexus" != null) {
          url = "http://${ipOf "nexus"}:9900";
          timeout = 300;
          capabilities = ["infra" "build" "ai"];
        };
        hermes-forge = lib.mkIf (ipOf "forge" != null) {
          url = "http://${ipOf "forge"}:9900";
          timeout = 300;
          capabilities = ["mining" "ai"];
        };
        hermes-zephyr = lib.mkIf (ipOf "zephyr" != null) {
          url = "http://${ipOf "zephyr"}:9900";
          timeout = 300;
          capabilities = ["infra" "coordinator" "ai"];
        };
      };
  };
}
