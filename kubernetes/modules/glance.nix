{
  cluster,
  nexusPreferredAffinity,
  ...
}: let
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
        server:
          proxied: true

        branding:
          hide-footer: true
          app-name: Cluster Dashboard

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
                    style: compact
                    sites:
                      - title: AI Gateway
                        url: https://ai-inference.lan
                        allow-insecure: true
                        alt-status-codes: [301, 302]
                      - title: SearXNG
                        url: https://search.lan
                        allow-insecure: true
                      - title: Grafana
                        url: https://grafana.lan
                        allow-insecure: true
                        alt-status-codes: [301, 302]
                      - title: Auth
                        url: https://auth.lan
                        allow-insecure: true
                      - title: Workspace
                        url: https://workspace.lan
                        allow-insecure: true
                        alt-status-codes: [301, 302]
                      - title: Brain
                        url: https://brain.lan
                        allow-insecure: true
                        alt-status-codes: [301, 302]
                      - title: Open WebUI
                        url: https://openwebui.lan
                        allow-insecure: true
                        alt-status-codes: [301, 302]
                      - title: Vaultwarden
                        url: https://vaultwarden.lan
                        allow-insecure: true
                      - title: n8n
                        url: https://n8n.lan
                        allow-insecure: true
                        alt-status-codes: [301, 302]
                      - title: Mission Control
                        url: https://mission-control.lan
                        allow-insecure: true
                        alt-status-codes: [301, 302]
                      - title: kAgent
                        url: https://kagent.lan
                        allow-insecure: true
                        alt-status-codes: [301, 302]
                      - title: Hermes
                        url: https://hermes.lan
                        allow-insecure: true
                        alt-status-codes: [301, 302]
                      - title: Dashboard
                        url: https://dashboard.lan
                        allow-insecure: true
                      - title: Privacy Filter
                        url: https://privacy-filter.lan
                        allow-insecure: true

          - name: Homelab
            columns:
              - size: small
                widgets:
                  - type: server-stats
                    servers:
                      - type: local
                        name: Nexus

                  - type: search
                    search-engine: duckduckgo
                    bangs:
                      - title: SearXNG
                        shortcut: "!s"
                        url: https://search.lan/search?q={QUERY}
                      - title: Grafana
                        shortcut: "!graf"
                        url: https://grafana.lan
                      - title: NixOS Wiki
                        shortcut: "!nix"
                        url: https://wiki.nixos.org/index.php?search={QUERY}

              - size: full
                widgets:
                  - type: custom-api
                    title: Kubernetes Pods
                    cache: 1m
                    url: http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query
                    parameters:
                      query: count by (phase) (kube_pod_status_phase)
                    template: |
                      <div class="flex justify-between text-center margin-bottom-10">
                      {{ range .JSON.Array "data.result" }}
                        <div>
                          <div class="color-highlight size-h3">{{ .String "value.1" }}</div>
                          <div class="size-h6">{{ .String "metric.phase" }}</div>
                        </div>
                      {{ end }}
                      </div>

                  - type: custom-api
                    title: Node CPU Usage
                    cache: 1m
                    url: http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query
                    parameters:
                      query: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
                    template: |
                      <ul class="list list-gap-10 collapsible-container" data-collapse-after="5">
                      {{ range .JSON.Array "data.result" }}
                        <li>
                          <div class="flex justify-between">
                            <span class="size-h4">{{ .String "metric.instance" }}</span>
                            <span class="color-highlight">{{ printf "%.1f" (.Get "value.1" | toFloat) }}%</span>
                          </div>
                        </li>
                      {{ end }}
                      </ul>

                  - type: custom-api
                    title: GPU Utilization
                    cache: 1m
                    url: http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query
                    parameters:
                      query: DCGM_FI_DEV_GPU_UTIL
                    template: |
                      <ul class="list list-gap-10">
                      {{ range .JSON.Array "data.result" }}
                        <li>
                          <div class="flex justify-between">
                            <span class="size-h4">GPU {{ .String "metric.gpu" }} ({{ .String "metric.nodeName" }})</span>
                            <span class="color-highlight">{{ .String "value.1" }}%</span>
                          </div>
                        </li>
                      {{ end }}
                      </ul>

              - size: small
                widgets:
                  - type: bookmarks
                    groups:
                      - title: Monitoring
                        color: 200 50 50
                        links:
                          - title: Grafana
                            url: https://grafana.lan
                            icon: si:grafana
                          - title: Prometheus
                            url: https://prometheus.lan
                            icon: si:prometheus
                          - title: Alertmanager
                            url: https://alertmanager.lan
                      - title: AI / ML
                        color: 120 50 50
                        links:
                          - title: AI Gateway
                            url: https://ai-inference.lan
                          - title: Open WebUI
                            url: https://openwebui.lan
                          - title: Brain
                            url: https://brain.lan
                      - title: Platform
                        color: 43 50 70
                        links:
                          - title: Casdoor SSO
                            url: https://auth.lan
                          - title: n8n
                            url: https://n8n.lan
                            icon: si:n8n
                          - title: Vaultwarden
                            url: https://vaultwarden.lan
                            icon: si:vaultwarden
                          - title: Hermes
                            url: https://hermes.lan

                  - type: monitor
                    cache: 2m
                    title: Critical
                    show-failing-only: true
                    sites:
                      - title: Prometheus
                        url: http://prometheus.monitoring.svc.cluster.local:9090
                      - title: CoreDNS
                        url: http://kube-dns.kube-system.svc.cluster.local:9153/metrics
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
            to = [{namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";}];
            ports = [
              {
                port = 53;
                protocol = "UDP";
              }
              {
                port = 53;
                protocol = "TCP";
              }
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
            ports = [
              {
                port = 8080;
                protocol = "TCP";
              }
            ];
          }
        ];
      };
    };
  };
}
