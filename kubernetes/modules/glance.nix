{cluster,
 nexusPreferredAffinity, ...}: let
  labels = {
    app = "glance";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects = {
    # ── Namespace ─────────────────────────────────────────────────
    none.Namespace.dashboard = {
      metadata.labels = {
        name = "dashboard";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── ConfigMap: glance.yml ─────────────────────────────────────
    dashboard.ConfigMap.glance-config = {
      metadata.labels = labels;
      data."glance.yml" = ''
        pages:
          - name: Home
            columns:
              - size: small
                widgets:
                  - type: calendar
                    first-day-of-week: monday

                  - type: weather
                    location: Winnipeg, Canada
                    units: metric
                    hour-format: 12h

                  - type: markets
                    markets:
                      - symbol: BTC-USD
                        name: Bitcoin
                      - symbol: XMR-USD
                        name: Monero
                      - symbol: NVDA
                        name: NVIDIA
                      - symbol: AAPL
                        name: Apple

                  - type: releases
                    cache: 4h
                    repositories:
                      - glanceapp/glance
                      - go-gitea/gitea
                      - immich-app/immich
                      - syncthing/syncthing
                      - searxng/searxng
                      - reverb256/portfolio

              - size: full
                widgets:
                  - type: group
                    widgets:
                      - type: hacker-news
                      - type: lobsters

                  - type: rss
                    limit: 10
                    collapse-after: 3
                    cache: 6h
                    feeds:
                      - url: https://selfh.st/rss/
                        title: selfh.st
                        limit: 4
                      - url: https://ciechanow.ski/atom.xml
                      - url: https://www.joshwcomeau.com/rss.xml
                        title: Josh Comeau
                      - url: https://samwho.dev/rss.xml
                      - url: https://ishadeed.com/feed.xml
                        title: Ahmad Shadeed

                  - type: group
                    widgets:
                      - type: reddit
                        subreddit: selfhosted
                        show-thumbnails: true
                      - type: reddit
                        subreddit: NixOS
                        show-thumbnails: true

              - size: small
                widgets:
                  - type: monitor
                    cache: 2m
                    title: Cluster Services
                    sites:
                      - title: AI Gateway
                        url: https://ai-inference.lan
                      - title: SearXNG
                        url: https://search.lan
                      - title: Grafana
                        url: https://grafana.lan
                      - title: Auth (Casdoor)
                        url: https://auth.lan
                      - title: Workspace
                        url: https://workspace.lan
                      - title: Brain
                        url: https://brain.lan
                      - title: Open WebUI
                        url: https://openwebui.lan
                      - title: Vaultwarden
                        url: https://vaultwarden.lan
                      - title: n8n
                        url: https://n8n.lan
      '';
    };

    # ── Deployment: Glance ───────────────────────────────────────
    dashboard.Deployment.glance = {
      metadata.labels = labels;
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "glance";
        strategy = {
          type = "Recreate";
          rollingUpdate = null;
        };
        template = {
          metadata.labels = labels;
          spec = {
            affinity = nexusPreferredAffinity;
            enableServiceLinks = false;
            automountServiceAccountToken = false;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1001;
              runAsGroup = 1001;
              fsGroup = 1001;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = {
              _namedlist = true;
              glance = {
                image = "glanceapp/glance:v0.8.4";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = ["ALL"];
                };
                ports = [
                  {
                    name = "http";
                    containerPort = 8080;
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    memory = "64Mi";
                    cpu = "100m";
                  };
                  limits = {
                    memory = "256Mi";
                    cpu = "500m";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = "http";
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/";
                    port = "http";
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  config = {
                    mountPath = "/app/config/glance.yml";
                    subPath = "glance.yml";
                    readOnly = true;
                  };
                  tmp = {
                    mountPath = "/tmp";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "glance-config";
              tmp.emptyDir = {};
            };
          };
        };
      };
    };

    # ── Service ───────────────────────────────────────────────────
    dashboard.Service.glance = {
      metadata.labels = labels;
      spec = {
        type = "NodePort";
        selector.app = "glance";
        ports = [
          {
            name = "http";
            port = 8080;
            nodePort = 32200;
            targetPort = 8080;
            protocol = "TCP";
          }
        ];
      };
    };

    # ── NetworkPolicies ───────────────────────────────────────────
    dashboard.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };

    dashboard.NetworkPolicy.allow-egress = {
      spec = {
        podSelector = {
          matchLabels.app = "glance";
        };
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{ipBlock.cidr = "0.0.0.0/0";}];
          }
          {
            to = [{namespaceSelector.matchLabels.name = "kube-system";}];
            ports = [
              {port = 53; protocol = "UDP";}
              {port = 53; protocol = "TCP";}
            ];
          }
        ];
      };
    };

    dashboard.NetworkPolicy.allow-ingress = {
      spec = {
        podSelector = {
          matchLabels.app = "glance";
        };
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{ipBlock.cidr = cluster.subnet;}];
            ports = [{port = 8080; protocol = "TCP";}];
          }
        ];
      };
    };
  };
}
