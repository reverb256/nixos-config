{
  monitoring,
  ...
}: {
  config.kubernetes.objects = {
    # -- Memory Monitor (CronJob on zephyr) --------------------------------
    # Source: memory-monitor-configmap.yaml, memory-monitor-cronjob.yaml
    monitoring.ConfigMap.memory-monitor-script.data."check-memory.sh" = ''
      #!/bin/bash
      THRESHOLD=75
      CURRENT=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')
      if [ $CURRENT -gt $THRESHOLD ]; then
        echo "WARNING: Zephyr memory usage is ''${CURRENT}%"
        echo "Consider moving workloads or scaling up"
        free -h
        echo "Top memory consumers:"
        ps aux --sort=-%mem | head -10
      fi
    '';

    monitoring.CronJob.memory-monitor = {
      metadata.labels = monitoring.managed // {app = "memory-monitor";};
      spec = {
        schedule = "*/5 * * * *";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 1;
        jobTemplate.spec.template = {
          spec = {
            nodeName = "sentry";
            restartPolicy = "OnFailure";
            containers = {
              _namedlist = true;
              memory-check = {
                image = "docker.io/library/busybox:1.36";
                command = [
                  "/bin/sh"
                  "/scripts/check-memory.sh"
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "200m";
                    memory = "256Mi";
                  };
                };
                volumeMounts = {
                  _namedlist = true;
                  scripts = {
                    mountPath = "/scripts";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              scripts = {
                configMap = {
                  name = "memory-monitor-script";
                  defaultMode = 493;
                };
              };
            };
          };
        };
      };
    };

  };
}
