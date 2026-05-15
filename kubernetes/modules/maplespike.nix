{ config, lib, pkgs, ... }:
with lib; let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  cfg = config.services.maplespike;

  # Common deployment builder
  mkDeployment = { name, namespace, cmd, port, replicaCount, image, resources, envExtra ? [], nodeName ? "nexus" }:
    let
      labels = {
        app = "maplespike-${name}";
        component = name;
        tier = "backend";
      };
    in
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        inherit name namespace labels;
      };
      spec = {
        replicas = replicaCount;
        revisionHistoryLimit = 2;
        selector = {
          matchLabels = {
            app = labels.app;
          };
        };
        strategy = {
          rollingUpdate = {
            maxSurge = 1;
            maxUnavailable = 0;
          };
        };
        template = {
          metadata.labels = labels;
          spec = {
            nodeName = nodeName;
            securityContext = {};
            terminationGracePeriodSeconds = 30;
            containers = [{
              inherit name image;
              imagePullPolicy = "Always";
              ports = lib.mkIf (port > 0) [{
                containerPort = port;
              }];
              env = [
                { name = "PORT"; value = toString port; }
                { name = "NODE_ENV"; value = "production"; }
              ] ++ envExtra;
              resources = resources;
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities = {
                  drop = ["ALL"];
                };
                runAsNonRoot = true;
                seccompProfile = {
                  type = "RuntimeDefault";
                };
              };
            }];
          };
        };
      };
    };
in
{
  options.services.maplespike = {
    enable = mkEnableOption "MapleSpike deployments";
    
    images = {
      api = mkOption {
        type = types.str;
        default = "ghcr.io/reverb256/maplespike-api:latest";
        description = "Maplespike API container image";
      };
      mcp = mkOption {
        type = types.str;
        default = "ghcr.io/reverb256/maplespike-mcp:latest";
        description = "Maplespike MCP server container image";
      };
      portal = mkOption {
        type = types.str;
        default = "ghcr.io/reverb256/maplespike-portal:latest";
        description = "Maplespike portal container image";
      };
    };

    replicas = {
      api = mkOption { type = types.int; default = 2; };
      mcp = mkOption { type = types.int; default = 1; };
      portal = mkOption { type = types.int; default = 1; };
    };
  };

  config.kubernetes.objects = mkIf cfg.enable {
    # ── Namespaces ──────────────────────────────────────────
    none.Namespace.maplespike = {
      metadata.labels = managed // {
        name = "maplespike";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };
    none.Namespace.maplespike-dev = {
      metadata.labels = managed // {
        name = "maplespike-dev";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── API Server ──────────────────────────────────────────
    apps.Deployment.maplespike-api = mkDeployment {
      name = "maplespike-api";
      namespace = "maplespike";
      cmd = "node packages/api-server/dist/dev-server.js";
      port = 8082;
      replicaCount = cfg.replicas.api;
      image = cfg.images.api;
      resources = {
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
        limits = {
          cpu = "500m";
          memory = "512Mi";
        };
      };
    };

    # ── MCP Server ──────────────────────────────────────────
    apps.Deployment.maplespike-mcp = mkDeployment {
      name = "maplespike-mcp";
      namespace = "maplespike";
      cmd = "node packages/mcp-server/dist/index.js";
      port = 3001;
      replicaCount = cfg.replicas.mcp;
      image = cfg.images.mcp;
      resources = {
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
        limits = {
          cpu = "300m";
          memory = "256Mi";
        };
      };
    };

    # ── Portal ──────────────────────────────────────────────
    apps.Deployment.maplespike-portal = mkDeployment {
      name = "maplespike-portal";
      namespace = "maplespike";
      cmd = "python3 server.py";
      port = 8080;
      replicaCount = cfg.replicas.portal;
      image = cfg.images.portal;
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "100m";
          memory = "128Mi";
        };
      };
    };
  };
}
