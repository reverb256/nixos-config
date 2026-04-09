# AI Inference namespace — gateway, LLM servers, monitoring, web UIs
#
# Complex namespace with multi-doc YAMLs that conflict with importyaml.
# Files are provided as kluctl extras to be applied alongside generated manifests.
# TODO: Incrementally convert to native Nix modules.
{ pkgs, lib, ... }:
let
  activeFiles = [
    "ai-inference-gateway-secrets.yaml"
    "gateway-deployment.yaml"
    "gateway-service.yaml"
    "gateway-external-service.yaml"
    "llama-server-deployment.yaml"
    "llama-server-service.yaml"
    "open-webui-deployment.yaml"
    "open-webui-network-policy.yaml"
    "redis-deployment.yaml"
    "qdrant-deployment.yaml"
    "searxng-mcp-deployment.yaml"
    "sglang-deployment.yaml"
    "mcp-gateway-proxy-daemonset.yaml"
    "observability.yaml"
    "allow-search-ingress.yaml"
  ];
in
{
  config.kluctl.files = lib.listToAttrs (
    lib.imap0 (i: f: {
      name = "ai-inference/${toString i}-${f}";
      value = builtins.readFile "${../../kubernetes-manifests/ai-inference}/${f}";
    }) activeFiles
  );
}
