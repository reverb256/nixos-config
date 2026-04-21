{ pkgs, lib, ... }:
let
  labels = {
    app = "vane";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in
{
  config.kubernetes.objects = {

    # ── PVC for config persistence ────────────────────────────────
    search.PersistentVolumeClaim.vane-data = {
      metadata.labels = labels;
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "local-path";
        resources.requests.storage = "1Gi";
      };
    };

    # ── Deployment ────────────────────────────────────────────────
    search.Deployment.vane = {
      metadata.labels = labels;
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels = labels;
        strategy = {
          type = "Recreate";
          rollingUpdate = null;
        };
        template = {
          metadata.labels = labels;
          spec = {
            nodeName = "nexus";
            enableServiceLinks = false;
            automountServiceAccountToken = false;
            securityContext = {
              runAsNonRoot = false;
              seccompProfile.type = "RuntimeDefault";
            };

            # Init: copy existing config from /var/lib/vane if PVC is empty
            initContainers = {
              _namedlist = true;
              copy-config = {
                name = "copy-config";
                image = "localhost/vane-custom:latest";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  allowPrivilegeEscalation = false;
                  capabilities.drop = [ "ALL" ];
                };
                command = [ "/bin/sh" "-c" ''
                  if [ ! -f /data/config.json ]; then
                    echo "No config.json found in PVC, creating default..."
                    echo '{"version":1,"setupComplete":true}' > /data/config.json
                  else
                    echo "Config already exists in PVC."
                  fi
                ''];
                volumeMounts = {
                  _namedlist = true;
                  data = { mountPath = "/data"; };
                };
              };
            };

            containers = {
              _namedlist = true;
              vane = {
                image = "localhost/vane-custom:latest";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  allowPrivilegeEscalation = false;
                  capabilities.drop = [ "ALL" ];
                };
                env = [
                  { name = "PORT"; value = "30900"; }
                  { name = "HOSTNAME"; value = "0.0.0.0"; }
                  { name = "SEARXNG_API_URL"; value = "http://searxng.search.svc.cluster.local:8080"; }
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 30900;
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    memory = "512Mi";
                    cpu = "250m";
                  };
                  limits = {
                    memory = "2Gi";
                    cpu = "2";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/";
                    port = "http";
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 6;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = "http";
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  timeoutSeconds = 10;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  data = { mountPath = "/home/vane/data"; };
                };
              };
            };

            volumes = {
              _namedlist = true;
              data.persistentVolumeClaim.claimName = "vane-data";
            };
          };
        };
      };
    };

    # ── Service (NodePort for Caddy access) ───────────────────────
    # NodePort because Caddy is systemd on zephyr, not a K8s pod.
    # ClusterIP isn't routable from non-pod hosts.
    search.Service.vane = {
      metadata.labels = labels;
      spec = {
        type = "NodePort";
        selector.app = "vane";
        ports = [
          {
            name = "http";
            port = 30900;
            targetPort = 30900;
            nodePort = 30900;
            protocol = "TCP";
          }
        ];
      };
    };

    # ── NetworkPolicy: allow ingress from hosts + K8s pods ────────
    search.NetworkPolicy.allow-vane-ingress = {
      metadata.labels = labels // { policy = "allow-ingress"; };
      spec = {
        podSelector.matchLabels.app = "vane";
        policyTypes = [ "Ingress" ];
        ingress = [
          {
            from = [
              { ipBlock.cidr = "10.1.1.0/24"; }
              { ipBlock.cidr = "10.244.0.0/16"; }
            ];
            ports = [
              { protocol = "TCP"; port = 30900; }
            ];
          }
        ];
      };
    };

    # ── NetworkPolicy: allow egress (SearXNG, gateway, internet) ──
    search.NetworkPolicy.allow-vane-egress = {
      metadata.labels = labels // { policy = "allow-egress"; };
      spec = {
        podSelector.matchLabels.app = "vane";
        policyTypes = [ "Egress" ];
        egress = [
          # DNS
          {
            to = [
              { namespaceSelector.matchLabels.name = "kube-system"; }
            ];
            ports = [
              { protocol = "UDP"; port = 53; }
              { protocol = "TCP"; port = 53; }
            ];
          }
          # Everything else (SearXNG, gateway, ZAI, internet)
          {
            to = [
              { ipBlock.cidr = "0.0.0.0/0"; }
            ];
          }
        ];
      };
    };
  };
}
