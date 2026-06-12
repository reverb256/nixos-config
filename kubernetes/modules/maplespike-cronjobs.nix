{config, lib, ...}:
with lib; let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
  cfg = config.services.maplespike;
  imageTag = "2026-05-16";
  ingestionImage = "ghcr.io/reverb256/maplespike-ingest:${imageTag}";
in {
  config.kubernetes.objects = mkIf cfg.enable {
    "maplespike-prod".CronJob.maplespike-ingest-committees = {
      metadata.labels = managed;
      spec = {
        schedule = "0 */6 * * *";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 3;
        jobTemplate.spec.template.spec = {
          restartPolicy = "Never";
          containers = [{
            name = "ingest";
            image = ingestionImage;
            imagePullPolicy = "IfNotPresent";
            env = [
              {name = "MAPLESPIKE_PIPELINE"; value = "committees";}
              {name = "NODE_ENV"; value = "production";}
            ];
            resources = {
              requests = {cpu = "50m"; memory = "64Mi";};
              limits = {cpu = "200m"; memory = "256Mi";};
            };
          }];
        };
      };
    };
    "maplespike-prod".CronJob.maplespike-ingest-realtime = {
      metadata.labels = managed;
      spec = {
        schedule = "*/30 * * * *";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 3;
        jobTemplate.spec.template.spec = {
          restartPolicy = "Never";
          containers = [{
            name = "ingest";
            image = ingestionImage;
            imagePullPolicy = "IfNotPresent";
            env = [
              {name = "MAPLESPIKE_PIPELINE"; value = "realtime";}
              {name = "NODE_ENV"; value = "production";}
            ];
            resources = {
              requests = {cpu = "50m"; memory = "64Mi";};
              limits = {cpu = "200m"; memory = "256Mi";};
            };
          }];
        };
      };
    };
  };
}
