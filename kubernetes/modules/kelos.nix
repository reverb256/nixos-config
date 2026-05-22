# Kelos task orchestration module.
# Controller self-manages Workspaces, TaskSpawners, AgentConfigs.
# This module bootstraps the initial config and provides fallback definitions.
# See: https://github.com/reverb256/kelos-controller
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kubernetes.kelos;
  inherit (cfg) repo;

  # Shared opencode.json config with NIM models via AI Inference Gateway
  opencodeConfig = lib.generators.toJSON {} {
    "$schema" = "https://opencode.ai/config.json";
    model = "nvidia/nemotron-3-super-120b-a12b";
    enabled_providers = ["nvidia"];
    provider.nvidia = {
      options = {
        baseURL = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1";
      };
      models = {
        "nemotron-3-super-120b-a12b" = { "name": "Nemotron 3 Super 120B", "id": "nvidia/nemotron-3-super-120b-a12b" };
        "nemotron-3-nano-30b-a3b" = { "name": "Nemotron 3 Nano 30B", "id": "nvidia/nemotron-3-nano-30b-a3b" };
        "nemotron-3-nano-omni-30b-a3b-reasoning" = { "name": "Nemotron 3 Nano Omni 30B", "id": "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning" };
      };
    };
  };
