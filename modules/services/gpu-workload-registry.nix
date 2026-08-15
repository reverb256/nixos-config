# GPU Workload Registry — Single Source of Truth for the fuzzel menu
#
# One declaration of every GPU LLM workload on the cluster, per host. Generates
# /etc/cluster/workloads.json on each host — the runtime registry the zephyr
# fuzzel menu reads over SSH at menu-open. Menu rows can never drift from
# deployed services: deploy = the signal. (House pattern: mcp-server-registry.nix
# and sops-secrets-registry.nix — one declaration, N generated artifacts.)
#
# Entry kinds:
#   "gguf"   — swappable via llama-swap. Menu load = POST /upstream/:swapId on
#              the host's swapPort (unload-first); unload = /api/models/unload.
#              alwaysOn=false (ttl 600): unloads when idle.
#   "direct" — always-on systemd unit (bonsai-1bit-* etc). Menu shows live state
#              via port probe only; no load/unload (they never unload).
#
# Populated by the owning modules:
#   - llama-swap-cluster.nix emits gguf entries from its model catalogs
#   - bonsai.nix emits direct entries from its mk1bitService units
#
# Hosts import this module and the file is written per-host (its own entries).
{
  config,
  lib,
  ... 
}: with lib; let
  cfg = config.services.gpu-workload-registry;
  host = config.networking.hostName;
in {
  options.services.gpu-workload-registry = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Write /etc/cluster/workloads.json (fuzzel menu discovery).";
    };

    workloads = mkOption {
      type = types.attrsOf (types.listOf (types.submodule {
        options = {
          id = mkOption {
            type = types.str;
            description = "Unique workload id (menu token + llama-swap swapId).";
          };
          name = mkOption {
            type = types.str;
            description = "Display name in the fuzzel menu.";
          };
          gpuLabel = mkOption {
            type = types.str;
            description = "GPU label for the menu row (e.g. \"5700 XT-0\").";
          };
          kind = mkOption {
            type = types.enum ["gguf" "direct"];
            description = "gguf = llama-swap swappable; direct = always-on unit.";
          };
          port = mkOption {
            type = types.port;
            description = "Model serving port (state probe / direct unit port).";
          };
          swapId = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "llama-swap catalog id (gguf only).";
          };
          swapPort = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "llama-swap proxy port on the host (gguf only).";
          };
          alwaysOn = mkOption {
            type = types.bool;
            default = false;
            description = "ttl:0 unit that never unloads (menu shows state only).";
          };
        };
      }));
      default = {};
      description = "GPU LLM workloads per host — the single source for the fuzzel menu.";
    };
  };

  config = mkIf cfg.enable {
    environment.etc."cluster/workloads.json" = {
      text = builtins.toJSON (cfg.workloads.${host} or []);
      mode = "0444";
    };
  };
}
