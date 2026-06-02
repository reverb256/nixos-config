# MapleSpike Ingress — Nginx/NGINX Ingress Controller (for non-NixOS K8s clusters)
# This provides ingress for clusters without NixOS + Caddy
# For NixOS clusters, Caddy in `hosts/nexus/services.nix` provides ingress instead

{ config, lib, pkgs, ... }:
let
  cfg = config.services.maplespike-ingress;
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in
{
  options.services.maplespike-ingress = {
    enable = lib.mkEnableOption "MapleSpike Ingress (NGINX Ingress Controller)";

    ingressClassName = lib.mkOption {
      type = lib.types.str;
      default = "nginx";
      description = "IngressClassName for the NGINX Ingress Controller";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "maplespike.lan";
      description = "Base domain for maplespike services (e.g., maplespike.lan)";
    };

    prodNamespace = lib.mkOption {
      type = lib.types.str;
      default = "maplespike-prod";
      description = "Namespace for prod deployment";
    };

    devNamespace = lib.mkOption {
      type = lib.types.str;
      default = "maplespike-staging";
      description = "Namespace for dev deployment";
    };

    ingressAnnotations = lib.mkOption {
      type = lib.types.attrsOf (lib.types.str);
      default = {
        "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
        "nginx.ingress.kubernetes.io/permanent-redirect" = "true";
      };
      description = "Annotations for Ingress resources (e.g., Let's Encrypt)";
    };
  };

  config.kubernetes.objects = lib.mkIf cfg.enable {
    "maplespike-${cfg.ingressClassName}".Ingress.ingressMaplespike = {
      metadata.labels = managed;
      annotations = cfg.ingressAnnotations;
      spec = {
        ingressClassName = cfg.ingressClassName;
        rules = [
          {
            host = cfg.domain;
            http.paths = [
              # API
              {
                path = "/api/v1";
                pathType = "Prefix";
                backend.service = {
                  name = "maplespike-api";
                  namespace = cfg.prodNamespace;
                };
                backend.port.number = 8082;
              }
              {
                path = "/sse";
                pathType = "Prefix";
                backend.service = {
                  name = "maplespike-mcp";
                  namespace = cfg.prodNamespace;
                };
                backend.port.number = 3001;
              }
              {
                path = "/messages";
                pathType = "Prefix";
                backend.service = {
                  name = "maplespike-mcp";
                  namespace = cfg.prodNamespace;
                };
                backend.port.number = 3001;
              }
              {
                path = "/health";
                pathType = "Prefix";
                backend.service = {
                  name = "maplespike-mcp";
                  namespace = cfg.prodNamespace;
                };
                backend.port.number = 3001;
              }
              # Portal
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "maplespike-portal";
                  namespace = cfg.prodNamespace;
                };
                backend.port.number = 8080;
              }
            ];
          }
        ];
      };
    };

    # Dev ingress (if dev deployment exists)
    "maplespike-${cfg.ingressClassName}".Ingress.ingressMaplespikeDev = {
      metadata.labels = managed;
      annotations = cfg.ingressAnnotations;
      spec = {
        ingressClassName = cfg.ingressClassName;
        rules = [
          {
            host = "dev." + cfg.domain;
            http.paths = [
              {
                path = "/api/v1";
                pathType = "Prefix";
                backend.service = {
                  name = "maplespike-api";
                  namespace = cfg.devNamespace;
                };
                backend.port.number = 8082;
              }
              {
                path = "/sse";
                pathType = "Prefix";
                backend.service = {
                  name = "maplespike-mcp";
                  namespace = cfg.devNamespace;
                };
                backend.port.number = 3001;
              }
              {
                path = "/messages";
                pathType = "Prefix";
                backend.service = {
                  name = "maplespike-mcp";
                  namespace = cfg.devNamespace;
                };
                backend.port.number = 3001;
              }
              {
                path = "/health";
                pathType = "Prefix";
                backend.service = {
                  name = "maplespike-mcp";
                  namespace = cfg.devNamespace;
                };
                backend.port.number = 3001;
              }
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "maplespike-portal";
                  namespace = cfg.devNamespace;
                };
                backend.port.number = 8080;
              }
            ];
          }
        ];
      };
    };
  };
}