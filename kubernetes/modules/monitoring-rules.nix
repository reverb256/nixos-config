_: let
in {
  config.kubernetes.objects = {
    # ── Alerting rules for CronJob and Pod failures ──────────────────
    # A7: PrometheusRule for maplespike CronJob + PodCrashLooping alerts
    monitoring.PrometheusRule.maplespike-alerts = {
      metadata = {
        namespace = "monitoring";
        labels = {
          app = "prometheus-rule";
          release = "prometheus";
        };
      };
      spec = {
        groups = [
          {
            name = "maplespike-ingestion";
            interval = "30s";
            rules = [
              {
                alert = "IngestionCronJobFailing";
                expr = ''kube_cronjob_status_failure{namespace="maplespike"} > 0'';
                for = "2h";
                labels = {
                  severity = "warning";
                  namespace = "maplespike";
                };
                annotations = {
                  summary = "Ingestion CronJob failing in maplespike namespace";
                  description = "CronJob {{ $labels.cronjob }} in namespace maplespike has recorded {{ $value }} failures over the past 2 hours. Check the job logs and ensure the pipeline is healthy.";
                  runbook = "https://homelab.lan/runbooks/ingestion-cronjob-failure";
                };
              }
              {
                alert = "PodCrashLooping";
                expr = ''kube_pod_status_phase{phase="Failed"} > 0'';
                for = "5m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Pod in {{ $labels.namespace }}/{{ $labels.pod }} is in Failed phase";
                  description = "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has been in Failed phase for more than 5 minutes. Investigate the pod logs and events.";
                  runbook = "https://homelab.lan/runbooks/pod-crash-looping";
                };
              }
            ];
          }
        ];
      };
    };
  };
}
