{
  cluster,
  nexusPreferredAffinity,
  ...
}: let
  labels = {
    app = "hermes-workspace";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects = {
    none.Namespace.workspace = {
      metadata.labels = {
        name = "workspace";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    workspace.Deployment.hermes-workspace = {
      metadata = {inherit labels;};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        strategy.rollingUpdate.maxSurge = 0;
        selector.matchLabels = labels;
        template = {
          metadata.labels = labels;
          spec = {
            nodeName = "zephyr";
            containers = [
              {
                name = "hermes-workspace";
                image = "nexus:5000/hermes-workspace:latest"; # Local build (own image)
                imagePullPolicy = "IfNotPresent";
                ports = [{containerPort = 3000; name = "http"; protocol = "TCP";}];
                env = [
                  {name = "HERMES_API_URL"; value = "http://10.1.1.110:8642";}
                  {name = "HERMES_DASHBOARD_URL"; value = "http://10.1.1.110:9119";}
                  {name = "HOST"; value = "0.0.0.0";}
                  {name = "PORT"; value = "3000";}
                  {name = "VITE_HERMESWORLD_ENABLED"; value = "0";}
                ];
                livenessProbe = {
                  httpGet.path = "/"; port = 3000;
                  initialDelaySeconds = 15; periodSeconds = 30;
                };
                readinessProbe = {
                  httpGet.path = "/api/ping"; port = 3000;
                  initialDelaySeconds = 10; periodSeconds = 15;
                };
              }
            ];
          };
        };
      };
    };

    workspace.Service.hermes-workspace = {
      metadata = {inherit labels;};
      spec = {
        selector = labels;
        ports = [{port = 3000; targetPort = 3000; name = "http"; protocol = "TCP";}];
      };
    };
  };
}
