# Caddy Ingress Controller
# Imported directly — complex controller with RBAC, ConfigMap, DaemonSet
{ pkgs, ... }:
{
  config.importyaml.caddy-ingress-controller = {
    src = pkgs.runCommand "caddy-ingress-controller.yaml" { } ''
      cp ${../../kubernetes-manifests/ingress-system/caddy-ingress-controller.yaml} $out
    '';
  };
}
