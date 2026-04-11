# AI Inference Service - Networking Config
#
# Firewall rules for AI inference services.
# Gateway runs in K8s, so only Qdrant port is opened on the host
# when RAG is enabled with a non-localhost bind address.
{ config, lib, ... }:
let
  cfg = config.services.ai-inference;
in
{
  config = lib.mkIf cfg.enable {
    # Only open Qdrant port if RAG is enabled with non-localhost bind
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault (
      lib.optional (
        cfg.rag.enable && cfg.rag.qdrant.enable && cfg.rag.qdrant.host != "127.0.0.1"
      ) cfg.rag.qdrant.port
    );
  };
}
