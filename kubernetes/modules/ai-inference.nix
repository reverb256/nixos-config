# AI Inference namespace — gateway, LLM servers, monitoring, web UIs
#
# Deploys: grafana, open-webui, ai-inference-gateway, configmaps, secrets
# Ingresses: llama-server, openwebui
#
# Uses importyaml for the cleaned live manifest. Complex multi-container
# deployments with secrets are preserved from the running cluster state.
# TODO: Incrementally convert to native Nix modules for type safety.
{
  pkgs,
  lib,
  ...
}: {
  config.kubernetes.objects.none.Namespace.ai-inference = {
    metadata.labels = {
      name = "ai-inference";
    };
  };

  # Import cleaned live AI inference resources
  # This includes: Deployments (grafana, open-webui), Services, Ingresses,
  # ConfigMaps, Secrets, ServiceAccounts, Roles, RoleBindings
  config.importyaml.ai-inference = {
    src = pkgs.runCommand "ai-inference.yaml" { } ''
      cp ${../../kubernetes-manifests/ai-inference/ai-inference-clean.yaml} $out
    '';
  };
}
