{
  cluster,
  config,
  lib,
  nexusPreferredAffinity,
  ...
}: let
  # Pin versions for supply chain security
  lokiImage = "docker.io/grafana/loki:3.7.1";
  mimirImage = "docker.io/grafana/mimir:3.0.6";
  tempoImage = "docker.io/grafana/tempo:2.10.5";
  grafanaImage = "docker.io/grafana/grafana:13.0.1";
  alloyImage = "docker.io/grafana/alloy:v1.16.1";
  prometheusImage = "docker.io/prom/prometheus:v3.11.3";

  storageClass = "slow-hdd";

  # Cluster host IPs — single source of truth from cluster.nix
  hostIPs = cluster.hosts;

  # Cluster DNS service IP (CoreDNS)
  clusterDNS = cluster.kubernetes.clusterDnsIP;

  # Loki config (monolithic mode, filesystem storage)
  # Reference: https://grafana.com/docs/loki/latest/configure/examples/
  lokiConfig = ''
    auth_enabled: false
    server:
      http_listen_port: 3100
      grpc_listen_port: 9096
      log_level: warn
    common:
      path_prefix: /loki
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory
    schema_config:
      configs:
        - from: 2024-01-01
          store: tsdb
          object_store: filesystem
          schema: v13
          index:
            prefix: index_
            period: 24h
    storage_config:
      filesystem:
        directory: /loki/storage
      tsdb_shipper:
        active_index_directory: /loki/tsdb-index
        cache_location: /loki/tsdb-cache
    limits_config:
      retention_period: 7d
      allow_structured_metadata: true
      max_query_length: 721h
    compactor:
      working_directory: /loki/compactor
      compaction_interval: 10m
      retention_enabled: true
      delete_request_store: filesystem
    analytics:
      reporting_enabled: false
  '';

  # Mimir config (monolithic mode)
  # Reference: https://github.com/grafana/mimir/blob/main/development/mimir-monolithic-mode/config/mimir.yaml
  mimirConfig = ''
    target: all
    multitenancy_enabled: false
    server:
      http_listen_port: 9009
      grpc_listen_port: 9095
      log_level: warn
    activity_tracker:
      filepath: /mimir/activity/metrics-activity.log
    common:
      storage:
        backend: filesystem
        filesystem:
          dir: /mimir/storage
    blocks_storage:
      backend: filesystem
      filesystem:
        dir: /mimir/data/blocks
      tsdb:
        dir: /mimir/data/tsdb
      bucket_store:
        sync_dir: /mimir/data/sync
    compactor:
      data_dir: /mimir/data/compactor
    alertmanager:
      data_dir: /mimir/data/alertmanager
    ruler:
      rule_path: /mimir/data/rules-eval
    memberlist:
      bind_port: 7946
    distributor:
      ring:
        kvstore:
          store: memberlist
    ingester:
      ring:
        kvstore:
          store: memberlist
        replication_factor: 1
        final_sleep: 0s
    store_gateway:
      sharding_ring:
        replication_factor: 1
        kvstore:
          store: memberlist
  '';

  # Tempo config (monolithic mode)
  # Tempo config (monolithic mode)
  tempoConfig = ''
    server:
      http_listen_port: 3200
      grpc_listen_port: 9095
      log_level: warn
    distributor:
      receivers:
        otlp:
          protocols:
            http:
              endpoint: 0.0.0.0:4318
            grpc:
              endpoint: 0.0.0.0:4317
    ingester:
      max_block_duration: 5m
    compactor:
      compaction:
        block_retention: 720h
    metrics_generator:
      registry:
        external_labels:
          source: tempo
      storage:
        path: /data/generator/wal
    storage:
      trace:
        backend: local
        wal:
          path: /data/wal
        local:
          path: /data/blocks
    overrides:
      metrics_generator_processors:
        - service-graphs
        - span-metrics
  '';

  # Alloy config (collects logs + traces from all nodes)
  alloyConfig = ''
    // Discover Kubernetes pods and collect logs
    discovery.kubernetes "pods" {
      role = "pod"
    }

    // PII stripping pipeline (MLSEC Phase 3.2)
    // Redacts emails, bearer tokens, API keys before Loki write
    loki.process "pii_strip" {
      // Strip email addresses
      stage.match {
        selector = "{job=~\".+\"}"
        stage.regex {
          expression = "(?i)[a-z0-9._%+\\-]+@[a-z0-9.\\-]+\\.[a-z]{2,}"
          source     = "entry"
        }
        stage.replace {
          expression = "(?i)[a-z0-9._%+\\-]+@[a-z0-9.\\-]+\\.[a-z]{2,}"
          replace    = "[REDACTED-EMAIL]"
        }
      }

      // Strip bearer/token patterns
      stage.match {
        selector = "{job=~\".+\"}"
        stage.regex {
          expression = "(?i)bearer\\s+[A-Za-z0-9\\-._~+/]+=*"
          source     = "entry"
        }
        stage.replace {
          expression = "(?i)(bearer)\\s+[A-Za-z0-9\\-._~+/]+=*"
          replace    = "''${1} [REDACTED-TOKEN]"
        }
      }

      // Strip API keys and long hex tokens
      stage.match {
        selector = "{job=~\".+\"}"
        stage.regex {
          expression = "(?i)(api[_\\-]?key|token|secret|password|apikey)[\"']?\\s*[:=]\\s*[\"']?[A-Za-z0-9\\-._~+/]{16,}"
          source     = "entry"
        }
        stage.replace {
          expression = "(?i)(api[_\\-]?key|token|secret|password|apikey)([\"']?\\s*[:=]\\s*[\"']?)[A-Za-z0-9\\-._~+/]{16,}"
          replace    = "''${1}''${2}[REDACTED]"
        }
      }

      forward_to = [loki.write.loki.receiver]
    }

    // Collect container logs → PII stripping → Loki
    loki.source.kubernetes "logs" {
      targets    = discovery.kubernetes.pods.targets
      forward_to = [loki.process.pii_strip.receiver]
    }

    // Collect host journald logs -> PII stripping -> Loki
    loki.source.journal "host_journal" {
      path       = "/var/log/journal"
      forward_to = [loki.process.pii_strip.receiver]
      labels     = {
        job = "systemd-journal",
      }
    }

    // Write logs to Loki
    loki.write "loki" {
      endpoint {
        url = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
      }
    }

    // Scrape kubelet metrics
    discovery.kubernetes "nodes" {
      role = "node"
    }

    // Scrape cadvisor metrics
    prometheus.scrape "cadvisor" {
      targets = [
        {__address__ = "127.0.0.1:10250"},
      ]
      scheme               = "https"
      tls_config {
        insecure_skip_verify = true
      }
      bearer_token_file    = "/var/run/secrets/kubernetes.io/serviceaccount/token"
      scrape_interval      = "15s"
      forward_to           = [prometheus.remote_write.mimir.receiver]
    }

    // Remote write to Mimir
    prometheus.remote_write "mimir" {
      endpoint {
        url = "http://mimir.monitoring.svc.cluster.local:9009/api/v1/push"
      }
    }

    // Collect traces via OTLP
    otelcol.receiver.otlp "default" {
      grpc {
        endpoint = "0.0.0.0:4317"
      }
      http {
        endpoint = "0.0.0.0:4318"
      }
      output {
        traces = [otelcol.exporter.otlp.tempo.input]
      }
    }

    otelcol.exporter.otlp "tempo" {
      client {
        endpoint = "tempo.monitoring.svc.cluster.local:4317"
        tls {
          insecure = true
          insecure_skip_verify = true
        }
      }
    }

    // Collect Kubernetes events → PII stripping → Loki
    loki.source.kubernetes_events "events" {
      job_name   = "integrations/kubernetes/eventhandler"
      log_format = "logfmt"
      forward_to = [loki.process.pii_strip.receiver]
    }

    // Self-monitoring: scrape Alloy metrics → Mimir
    prometheus.scrape "alloy_self" {
      targets = [
        {__address__ = "127.0.0.1:12345"},
      ]
      scrape_interval = "15s"
      forward_to      = [prometheus.remote_write.mimir.receiver]
    }
  '';

  # Prometheus config (scrapes cluster targets, remote_writes to Mimir)
  prometheusConfig = ''
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        cluster: nixos-k8s

    scrape_configs:
      - job_name: 'node-exporter'
        scrape_interval: 15s
        static_configs:
          - targets:
              - '${hostIPs.zephyr.ip}:9100'
              - '${hostIPs.nexus.ip}:9100'
              - '${hostIPs.forge.ip}:9100'
              - '${hostIPs.sentry.ip}:9100'

      - job_name: 'nix-cache'
        scrape_interval: 30s
        static_configs:
          - targets:
              - '${hostIPs.nexus.ip}:50000'

      - job_name: 'nvidia-exporter'
        scrape_interval: 15s
        static_configs:
          - targets:
              - '${hostIPs.zephyr.ip}:9400'
              - '${hostIPs.nexus.ip}:9400'
              - '${hostIPs.forge.ip}:9400'

      # PeakMiner 2.8.0 exposes a localhost-only /summary API, not a
      # remotely scrapeable Prometheus /metrics endpoint. Keep its API ports
      # local to each host for diagnostics; do not advertise false scrape targets.

      - job_name: 'kube-state-metrics'
        kubernetes_sd_configs:
          - role: endpoints
        relabel_configs:
          - source_labels: [__meta_kubernetes_service_name]
            regex: 'kube-state-metrics'
            action: keep

      - job_name: 'kubelet'
        scheme: https
        tls_config:
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
          - role: node
        relabel_configs:
          - source_labels: [__meta_kubernetes_node_address_InternalIP]
            target_label: __address__
            replacement: "$1:10250"

      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            target_label: __address__
            regex: (.+)
            replacement: "$1"

      - job_name: 'etcd'
        scrape_interval: 30s
        static_configs:
          - targets:
              - '${hostIPs.zephyr.ip}:2379'
              - '${hostIPs.nexus.ip}:2379'
              - '${hostIPs.sentry.ip}:2379'
        scheme: https
        tls_config:
          insecure_skip_verify: true

    alerting:
      alertmanagers:
        - static_configs:
            - targets:
                - 'alertmanager.monitoring.svc.cluster.local:9093'

    remote_write:
      - url: 'http://mimir.monitoring.svc.cluster.local:9009/api/v1/push'
  '';

  # Grafana datasources provisioning
  grafanaDatasources = {
    apiVersion = 1;
    datasources = [
      {
        name = "Mimir";
        type = "prometheus";
        url = "http://mimir.monitoring.svc.cluster.local:9009/prometheus";
        isDefault = true;
        editable = false;
        uid = "mimir";
      }
      {
        name = "Loki";
        type = "loki";
        url = "http://loki.monitoring.svc.cluster.local:3100";
        editable = false;
        uid = "loki";
      }
      {
        name = "Tempo";
        type = "tempo";
        url = "http://tempo.monitoring.svc.cluster.local:3200";
        editable = false;
        uid = "tempo";
      }
    ];
  };

  # Common node selector for sentry
  sentrySelector = {
    "kubernetes.io/hostname" = "sentry";
  };

  # Common security context
  securityContext = {
    runAsNonRoot = true;
    runAsUser = 10001;
    runAsGroup = 10001;
    fsGroup = 10001;
    seccompProfile.type = "RuntimeDefault";
  };

  # Common container security
  containerSecurity = {
    allowPrivilegeEscalation = false;
    readOnlyRootFilesystem = true;
    capabilities.drop = ["ALL"];
  };

  # Common probes helper
  httpProbe = port: path: {
    httpGet = {inherit port path;};
    initialDelaySeconds = 30;
    periodSeconds = 10;
    timeoutSeconds = 5;
    failureThreshold = 3;
  };

  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  _module.args.monitoring = {
    inherit
      lokiImage mimirImage tempoImage grafanaImage alloyImage prometheusImage
      storageClass hostIPs clusterDNS
      lokiConfig mimirConfig tempoConfig alloyConfig prometheusConfig
      grafanaDatasources sentrySelector securityContext containerSecurity
      httpProbe managed
      ;
  };

  imports = [
    ./loki.nix
    ./mimir.nix
    ./tempo.nix
    ./grafana.nix
    ./alloy.nix
    ./prometheus.nix
    ./alerting.nix
    ./kube-state-metrics.nix
    ./alert-rules.nix
    ./memory-monitor.nix
    ./custom-metrics.nix
    ./system-tools.nix
  ];

  # NOTE: implicit `kubernetes.objects` (no `config.` prefix) is required here
  # because this module also sets `_module.args.monitoring` — the module system
  # only permits `_module` at the top level in implicit syntax.
  kubernetes.objects = {
    # ── Namespace ──────────────────────────────────────────────
    none.Namespace.monitoring = {
      metadata.labels = {
        name = "monitoring";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── ServiceAccounts ────────────────────────────────────────
    monitoring.ServiceAccount.loki-sa = {};
    monitoring.ServiceAccount.mimir-sa = {};
    monitoring.ServiceAccount.tempo-sa = {};
    monitoring.ServiceAccount.grafana-sa = {};
    monitoring.ServiceAccount.alloy-sa = {};
    monitoring.ServiceAccount.prometheus-sa = {};

    # ── ClusterRole for Alloy (needs wide cluster access) ──────
    none.ClusterRole.alloy-cluster-role = {
      rules = [
        {
          apiGroups = [""];
          resources = [
            "nodes"
            "nodes/metrics"
            "nodes/proxy"
            "pods"
            "pods/log"
            "services"
            "endpoints"
            "namespaces"
          ];
          verbs = [
            "get"
            "list"
            "watch"
          ];
        }
        {
          apiGroups = [""];
          resources = ["events"];
          verbs = ["get" "list" "watch"];
        }
        {
          apiGroups = [
            "networking.k8s.io"
          ];
          resources = ["ingresses"];
          verbs = [
            "get"
            "list"
            "watch"
          ];
        }
        {
          nonResourceURLs = [
            "/metrics"
            "/metrics/cadvisor"
          ];
          verbs = ["get"];
        }
      ];
    };
    none.ClusterRoleBinding.alloy-cluster-rolebinding = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "alloy-cluster-role";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "alloy-sa";
          namespace = "monitoring";
        }
      ];
    };

    # ── ClusterRole for Prometheus ─────────────────────────────
    none.ClusterRole.prometheus-cluster-role = {
      rules = [
        {
          apiGroups = [""];
          resources = [
            "nodes"
            "nodes/metrics"
            "nodes/proxy"
            "pods"
            "services"
            "endpoints"
            "namespaces"
          ];
          verbs = [
            "get"
            "list"
            "watch"
          ];
        }
        {
          nonResourceURLs = ["/metrics"];
          verbs = ["get"];
        }
      ];
    };
    none.ClusterRoleBinding.prometheus-cluster-rolebinding = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "prometheus-cluster-role";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "prometheus-sa";
          namespace = "monitoring";
        }
      ];
    };

    # ── NetworkPolicies ────────────────────────────────────────
    monitoring.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };
    monitoring.NetworkPolicy.allow-internal = {
      spec = {
        podSelector = {};
        policyTypes = [
          "Ingress"
          "Egress"
        ];
        ingress = [{from = [{namespaceSelector.matchLabels.name = "monitoring";}];}];
        egress = [
          {to = [{namespaceSelector.matchLabels.name = "monitoring";}];}
          {
            to = [
              {
                namespaceSelector = {};
                podSelector.matchLabels."k8s-app" = "kube-dns";
              }
            ];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
              {
                protocol = "TCP";
                port = 53;
              }
            ];
          }
        ];
      };
    };
    monitoring.NetworkPolicy.allow-caddy-to-grafana = {
      spec = {
        podSelector.matchLabels.app = "grafana";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{namespaceSelector.matchLabels.name = "ingress-system";}];
            ports = [
              {
                protocol = "TCP";
                port = 3000;
              }
            ];
          }
        ];
      };
    };

    monitoring.NetworkPolicy.allow-dashboard-to-prometheus = {
      spec = {
        podSelector.matchLabels.app = "prometheus";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{namespaceSelector.matchLabels.name = "dashboard";}];
            ports = [
              {
                protocol = "TCP";
                port = 9090;
              }
            ];
          }
        ];
      };
    };
    monitoring.NetworkPolicy.allow-alloy-kubelet = {
      spec = {
        podSelector.matchLabels.app = "alloy";
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{ipBlock.cidr = cluster.subnet;}];
            ports = [
              {
                protocol = "TCP";
                port = 10250;
              }
            ];
          }
        ];
      };
    };

  };
}
