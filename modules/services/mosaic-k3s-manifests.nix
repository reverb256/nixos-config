# mosaic-k3s-manifests.nix — MIS + bridge deployments as k3s auto-deploy manifests.
#
# Each entry is written to /var/lib/rancher/k3s/server/manifests/ by
# systemd-tmpfiles at activation time. k3s applies them automatically.
#
# Enable on a server node with:
#   services.k3s.manifests = (import ./mosaic-k3s-manifests.nix).services.k3s.manifests;

{ config, lib, ... }:
{
  services.k3s.manifests = {

    mosaic-identity-deployment = {
      enable = true;
      content = {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata = {
          name = "mosaic-identity";
          namespace = "orchestration";
          labels.app = "mosaic-identity";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "mosaic-identity";
          template = {
            metadata.labels.app = "mosaic-identity";
            spec = {
              initContainers = [];
              nodeSelector."kubernetes.io/hostname" = "nexus";
              securityContext.fsGroup = 1000;
              containers = [{
                name = "mosaic-identity";
                image = "localhost:5000/mosaic-identity:v0.1.0";
                imagePullPolicy = "IfNotPresent";
                ports = [{
                  containerPort = 8081; name = "http"; protocol = "TCP";
                }];
                securityContext = {
                  runAsUser = 1000; runAsGroup = 1000; runAsNonRoot = true;
                };
                env = [
                  { name = "MIS_HOST"; value = "0.0.0.0"; }
                  { name = "MIS_PORT"; value = "8081"; }
                  { name = "MIS_DATABASE_URL"; value = "sqlite:///data/mosaic-identity.db?mode=rwc"; }
                  { name = "RUST_LOG"; value = "info"; }
                ];
                volumeMounts = [{ name = "data"; mountPath = "/data"; }];
                resources = {
                  requests = { cpu = "100m"; memory = "64Mi"; };
                  limits = { cpu = "500m"; memory = "256Mi"; };
                };
                livenessProbe = {
                  httpGet = { path = "/health"; port = 8081; };
                  initialDelaySeconds = 10; periodSeconds = 30;
                };
                readinessProbe = {
                  httpGet = { path = "/health"; port = 8081; };
                  initialDelaySeconds = 5; periodSeconds = 10;
                };
              }];
              volumes = [{ name = "data"; emptyDir = {}; }];
            };
          };
        };
      };
    };

    mosaic-identity-service = {
      enable = true;
      content = {
        apiVersion = "v1";
        kind = "Service";
        metadata = {
          name = "mosaic-identity";
          namespace = "orchestration";
          labels.app = "mosaic-identity";
        };
        spec = {
          selector.app = "mosaic-identity";
          ports = [{
            name = "http"; port = 8081; targetPort = 8081; protocol = "TCP";
          }];
          type = "ClusterIP";
        };
      };
    };

    mosaic-bridge-atproto = {
      enable = true;
      content = {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata = {
          name = "mosaic-bridge-atproto";
          namespace = "orchestration";
          labels.app = "mosaic-bridge-atproto";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "mosaic-bridge-atproto";
          template = {
            metadata.labels.app = "mosaic-bridge-atproto";
            spec = {
              initContainers = [];
              containers = [{
                name = "bridge";
                image = "nexus:5000/mosaic-bridges:v0.1.0";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  runAsUser = 100; runAsGroup = 101; runAsNonRoot = true;
                };
                env = [
                  { name = "MIS_URL"; value = "http://mosaic-identity:8081"; }
                  { name = "BRIDGE_TYPE"; value = "atproto"; }
                ];
                resources = {
                  requests = { cpu = "50m"; memory = "32Mi"; };
                  limits = { cpu = "200m"; memory = "128Mi"; };
                };
              }];
            };
          };
        };
      };
    };

    mosaic-bridge-atproto-svc = {
      enable = true;
      content = {
        apiVersion = "v1";
        kind = "Service";
        metadata = {
          name = "mosaic-bridge-atproto";
          namespace = "orchestration";
          labels.app = "mosaic-bridge-atproto";
        };
        spec = {
          selector.app = "mosaic-bridge-atproto";
          ports = [{ name = "http"; port = 8083; targetPort = 8083; protocol = "TCP"; }];
          type = "ClusterIP";
        };
      };
    };

    mosaic-bridge-buzz = {
      enable = true;
      content = {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata = {
          name = "mosaic-bridge-buzz";
          namespace = "orchestration";
          labels.app = "mosaic-bridge-buzz";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "mosaic-bridge-buzz";
          template = {
            metadata.labels.app = "mosaic-bridge-buzz";
            spec = {
              initContainers = [];
              containers = [{
                name = "bridge";
                image = "nexus:5000/mosaic-bridges:v0.1.0";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  runAsUser = 100; runAsGroup = 101; runAsNonRoot = true;
                };
                env = [
                  { name = "MIS_URL"; value = "http://mosaic-identity:8081"; }
                  { name = "BRIDGE_TYPE"; value = "buzz"; }
                  { name = "BUZZ_RELAY_URL"; value = "wss://relay.damus.io"; }
                ];
                resources = {
                  requests = { cpu = "50m"; memory = "32Mi"; };
                  limits = { cpu = "200m"; memory = "128Mi"; };
                };
              }];
            };
          };
        };
      };
    };

    mosaic-bridge-irc = {
      enable = true;
      content = {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata = {
          name = "mosaic-bridge-irc";
          namespace = "orchestration";
          labels.app = "mosaic-bridge-irc";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "mosaic-bridge-irc";
          template = {
            metadata.labels.app = "mosaic-bridge-irc";
            spec = {
              initContainers = [];
              containers = [{
                name = "bridge";
                image = "nexus:5000/mosaic-bridges:v0.1.0";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  runAsUser = 100; runAsGroup = 101; runAsNonRoot = true;
                };
                env = [
                  { name = "MIS_URL"; value = "http://mosaic-identity:8081"; }
                  { name = "BRIDGE_TYPE"; value = "irc"; }
                  { name = "IRC_SERVER"; value = "irc.libera.chat"; }
                  { name = "IRC_PORT"; value = "6697"; }
                  { name = "IRC_NICK"; value = "MosaicBridge"; }
                ];
                resources = {
                  requests = { cpu = "50m"; memory = "32Mi"; };
                  limits = { cpu = "200m"; memory = "128Mi"; };
                };
              }];
            };
          };
        };
      };
    };

    mosaic-bridge-matrix = {
      enable = true;
      content = {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata = {
          name = "mosaic-bridge-matrix";
          namespace = "orchestration";
          labels.app = "mosaic-bridge-matrix";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "mosaic-bridge-matrix";
          template = {
            metadata.labels.app = "mosaic-bridge-matrix";
            spec = {
              initContainers = [];
              containers = [{
                name = "bridge";
                image = "nexus:5000/mosaic-bridges:v0.1.0";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  runAsUser = 100; runAsGroup = 101; runAsNonRoot = true;
                };
                env = [
                  { name = "MIS_URL"; value = "http://mosaic-identity:8081"; }
                  { name = "BRIDGE_TYPE"; value = "matrix"; }
                  { name = "MATRIX_AS_PORT"; value = "8082"; }
                  { name = "MATRIX_DOMAIN"; value = "matrix.local"; }
                ];
                resources = {
                  requests = { cpu = "50m"; memory = "64Mi"; };
                  limits = { cpu = "200m"; memory = "192Mi"; };
                };
              }];
            };
          };
        };
      };
    };

    mosaic-bridge-matrix-svc = {
      enable = true;
      content = {
        apiVersion = "v1";
        kind = "Service";
        metadata = {
          name = "mosaic-bridge-matrix";
          namespace = "orchestration";
          labels.app = "mosaic-bridge-matrix";
        };
        spec = {
          selector.app = "mosaic-bridge-matrix";
          ports = [{ name = "as-http"; port = 8082; targetPort = 8082; protocol = "TCP"; }];
          type = "ClusterIP";
        };
      };
    };

  };
}
