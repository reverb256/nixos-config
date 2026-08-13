{
  monitoring,
  ...
}: {
  config.kubernetes.objects = {
    # =======================================================================
    # -- UNIQUE RESOURCES FROM YAML MANIFESTS (Phase 2 migration) ---------
    # =======================================================================

    # -- Alert Rules: API Server Health (ConfigMap) -----------------------
    # Source: api-server-alerts.yaml
    monitoring.ConfigMap.prometheus-api-server-rules.data."api-server-alerts.yml" = ''
      groups:
      - name: api-server-health
        interval: 30s
        rules:
      - alert: APIServerDown
        expr: up{job="kube-apiserver"} == 0
        for: 1m
        labels:
          severity: critical
          component: control-plane
        annotations:
          summary: "API server is down on {{ $labels.instance }}"
          description: "API server has been down for more than 1 minute"

      - alert: APIServerHighErrorRate
        expr: |
          sum(rate(apiserver_request_total{job="kube-apiserver",code=~"5.."}[5m]))
          /
          sum(rate(apiserver_request_total{job="kube-apiserver"}[5m])) > 0.05
        for: 5m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "API server returning high error rate (5%+)"

      - alert: APIServerHighLatency
        expr: |
          histogram_quantile(0.99,
            sum(rate(apiserver_request_latencies_seconds_bucket{job="kube-apiserver"}[5m])) by (le)
          ) > 1
        for: 10m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "API server p99 latency exceeds 1 second"

      - alert: EtcdHighRequestDuration
        expr: |
          histogram_quantile(0.99,
            sum(rate(etcd_request_duration_seconds_bucket[5m])) by (le)
          ) > 0.5
        for: 10m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "etcd requests experiencing high latency"

      - alert: APIServerRestart
        expr: |
          time() - process_start_time_seconds{job="kube-apiserver"} < 300
        for: 0m
        labels:
          severity: critical
          component: control-plane
        annotations:
          summary: "API server restarted on {{ $labels.instance }}"
          description: "API server restarted less than 5 minutes ago"

      - alert: APIServerPodCountMismatch
        expr: |
          count(up{job="kube-apiserver"}) != 3
        for: 5m
        labels:
          severity: critical
          component: control-plane
        annotations:
          summary: "Expected 3 API server pods, found {{ $value }}"

      - alert: ControlPlaneHighRestartRate
        expr: |
          increase(kube_pod_container_status_restarts_total{namespace="kube-system"}[1h]) > 5
        for: 5m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "Control plane pod restarting frequently"

      - name: api-server-capacity
        interval: 1m
        rules:
      - alert: APIServerHighCPU
        expr: |
          sum(rate(container_cpu_usage_seconds_total{namespace="kube-system",container=~"kube-apiserver|etcd"}[5m]))
          /
          sum(machine_cpu_cores)
          > 0.5
        for: 10m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "Control plane using >50% of cluster CPU"

      - alert: APIServerHighMemory
        expr: |
          sum(container_memory_working_set_bytes{namespace="kube-system",container=~"kube-apiserver|etcd"})
          /
          sum(machine_memory_bytes)
          > 0.2
        for: 10m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "Control plane using >20% of cluster memory"
    '';

    # -- Alert Rules: Kube API Server (ConfigMap version) -----------------
    # Source: prometheus-alert-rules-kube-apiserver.yaml
    monitoring.ConfigMap.prometheus-alert-rules-kube-apiserver.data."kube-apiserver-rules.yml" = ''
      groups:
        - name: kube-apiserver
          interval: 30s
          rules:
          - alert: KubeAPIServerDown
            expr: up{job="kube-apiserver-static"} == 0
            for: 1m
            labels:
              severity: critical
              component: control-plane
            annotations:
              summary: "Kubernetes API server is down"
              description: "Kubernetes API server on {{ $labels.instance }} has been down for more than 1 minute."

          - alert: KubeAPIServerRestarted
            expr: |
              time() - process_start_time_seconds{job="kube-apiserver-static"} < 300
            for: 0m
            labels:
              severity: warning
              component: control-plane
            annotations:
              summary: "Kubernetes API server restarted"

          - alert: KubeAPIServerLatencyHigh
            expr: |
              histogram_quantile(0.99, sum(rate(apiserver_request_duration_seconds_bucket{job="kube-apiserver-static"}[5m])) by (le, verb)) > 1
            for: 10m
            labels:
              severity: warning
              component: control-plane
            annotations:
              summary: "Kubernetes API server 99th percentile latency high"

          - alert: KubeAPIServerErrorsHigh
            expr: |
              sum(rate(apiserver_request_total{job="kube-apiserver-static",code=~"5.."}[5m]))
              /
              sum(rate(apiserver_request_total{job="kube-apiserver-static"}[5m])) > 0.05
            for: 10m
            labels:
              severity: warning
              component: control-plane
            annotations:
              summary: "Kubernetes API server error rate high"

          - alert: KubeAPIServerEtcdLatencyHigh
            expr: |
              histogram_quantile(0.99, sum(rate(apiserver_storage_db_request_duration_seconds_bucket{job="kube-apiserver-static"}[5m])) by (le, operation_name)) > 0.5
            for: 10m
            labels:
              severity: warning
              component: control-plane
            annotations:
              summary: "Kubernetes API server etcd latency high"
    '';

    # -- Alert Rules: Cluster Health (pod count, etcd size, evictions) ------
    monitoring.ConfigMap.prometheus-cluster-health-rules.data."cluster-health.yml" = ''
      groups:
      - name: cluster-pod-health
        interval: 30s
        rules:
        - alert: TooManyPodsInNamespace
          expr: |
            count by (namespace) (kube_pod_info) > 100
          for: 5m
          labels:
            severity: warning
            component: scheduling
          annotations:
            summary: "Namespace {{ $labels.namespace }} has {{ $value }} pods (>100)"
            description: "High pod count may indicate a leak or missing cleanup"

        - alert: EvictedPodsDetected
          expr: |
            sum by (namespace) (kube_pod_status_phase{phase="Failed",reason="Evicted"}) > 5
          for: 5m
          labels:
            severity: warning
            component: scheduling
          annotations:
            summary: "{{ $value }} evicted pods in namespace {{ $labels.namespace }}"
            description: "Pods are being evicted, possible resource pressure"

        - alert: CrashLoopingPods
          expr: |
            sum by (namespace) (kube_pod_container_status_restarts_total - kube_pod_container_status_restarts_total offset 5m) > 5
          for: 5m
          labels:
            severity: warning
            component: workloads
          annotations:
            summary: "Pods restarting frequently in {{ $labels.namespace }}"

      - name: etcd-health
        interval: 30s
        rules:
        - alert: EtcdClusterSizeMismatch
          expr: |
            count(etcd_server_has_leader) != 3
          for: 5m
          labels:
            severity: critical
            component: control-plane
          annotations:
            summary: "etcd cluster size mismatch: {{ $value }} members (expected 3)"

        - alert: EtcdNoLeader
          expr: |
            etcd_server_has_leader == 0
          for: 1m
          labels:
            severity: critical
            component: control-plane
          annotations:
            summary: "etcd member {{ $labels.instance }} has no leader"

        - alert: EtcdHighDBSize
          expr: |
            etcd_mvcc_db_total_size_in_bytes > 2147483648
          for: 10m
          labels:
            severity: warning
            component: control-plane
          annotations:
            summary: "etcd DB size {{ $value | humanize }}B (>2GB) on {{ $labels.instance }}"
            description: "etcd database is growing large. Check compaction and defrag."

        - alert: NodeNotReady
          expr: |
            kube_node_status_condition{condition="Ready",status="true"} == 0
          for: 5m
          labels:
            severity: critical
            component: nodes
          annotations:
            summary: "Node {{ $labels.node }} is NotReady"

        - alert: NodeDiskPressure
          expr: |
            kube_node_status_condition{condition="DiskPressure",status="true"} == 1
          for: 5m
          labels:
            severity: warning
            component: nodes
          annotations:
            summary: "Node {{ $labels.node }} has disk pressure"

        - alert: NodeMemoryPressure
          expr: |
            kube_node_status_condition{condition="MemoryPressure",status="true"} == 1
          for: 5m
          labels:
            severity: warning
            component: nodes
          annotations:
            summary: "Node {{ $labels.node }} has memory pressure"
    '';

  };
}
