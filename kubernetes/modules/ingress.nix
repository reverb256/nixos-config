# Caddy Ingress Controller - Native easykubenix
# Converted from importyaml caddy-ingress-controller.yaml
{ pkgs, ... }:
let
  labels = {
    "app.kubernetes.io/name" = "caddy-ingress-controller";
    "app.kubernetes.io/component" = "controller";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in
{
  config.kubernetes.objects.ingress-system = {
    ServiceAccount.caddy-ingress-controller.metadata.labels = labels;
    ConfigMap.caddy-ingress-controller-configmap = {
      metadata.labels = labels;
      data = { acmeCA = ""; email = ""; debug = "false"; metrics = "true"; onDemandTLS = "false"; proxyProtocol = "false"; experimentalSmartSort = "false"; };
    };
    Deployment.caddy-ingress-controller = {
      metadata.labels = labels;
      spec = {
        replicas = 2; revisionHistoryLimit = 1; selector.matchLabels = labels; strategy.type = "RollingUpdate";
        template = {
          metadata.labels = labels;
          spec = {
            serviceAccountName = "caddy-ingress-controller";
            nodeSelector."kubernetes.io/hostname" = "nexus";
            tolerations = [{ key = "node-role.kubernetes.io/control-plane"; operator = "Exists"; effect = "NoSchedule"; }];
            containers = {
              _namedlist = true;
              caddy-ingress-controller = {
                image = "caddy/ingress:v0.2.1"; imagePullPolicy = "IfNotPresent";
                args = ["-config-map=caddy-ingress-controller-configmap" "-class-name=caddy"];
                env = { _namedlist = true; POD_NAME = { name = "POD_NAME"; valueFrom.fieldRef.fieldPath = "metadata.name"; }; POD_NAMESPACE = { name = "POD_NAMESPACE"; valueFrom.fieldRef.fieldPath = "metadata.namespace"; }; };
                ports = [{ containerPort = 80; name = "http"; protocol = "TCP"; } { containerPort = 443; name = "https"; protocol = "TCP"; } { containerPort = 9765; name = "metrics"; protocol = "TCP"; }];
                readinessProbe = { initialDelaySeconds = 3; periodSeconds = 10; httpGet = { port = 9765; path = "/healthz"; }; };
                volumeMounts = { _namedlist = true; tmp = { mountPath = "/tmp"; }; };
                resources = { requests = { cpu = "100m"; memory = "128Mi"; }; limits = { cpu = "500m"; memory = "256Mi"; }; };
              };
            };
            volumes = { _namedlist = true; tmp = { emptyDir = {}; }; };
          };
        };
      };
    };
    Service.caddy-ingress-controller = {
      metadata.labels = labels;
      spec = { type = "NodePort"; internalTrafficPolicy = "Cluster"; externalTrafficPolicy = "Cluster";
        ports = [{ name = "http"; port = 80; protocol = "TCP"; targetPort = "http"; nodePort = 30080; } { name = "https"; port = 443; protocol = "TCP"; targetPort = "https"; nodePort = 30443; }];
        selector = labels;
      };
    };
  };
  config.kubernetes.objects.none = {
    ClusterRole.caddy-ingress-controller = {
      metadata.labels = labels;
      rules = [
        { apiGroups = ["networking.k8s.io"]; resources = ["ingresses"]; verbs = ["get" "list" "watch"]; }
        { apiGroups = ["networking.k8s.io"]; resources = ["ingresses/status"]; verbs = ["update"]; }
        { apiGroups = ["networking.k8s.io"]; resources = ["ingressclasses"]; verbs = ["get" "list" "watch"]; }
        { apiGroups = [""]; resources = ["configmaps" "secrets" "services" "endpoints" "pods"]; verbs = ["get" "list" "watch"]; }
        { apiGroups = ["coordination.k8s.io"]; resources = ["leases"]; verbs = ["get" "create" "update"]; }
      ];
    };
    ClusterRoleBinding.caddy-ingress-controller = {
      metadata.labels = labels;
      roleRef = { apiGroup = "rbac.authorization.k8s.io"; kind = "ClusterRole"; name = "caddy-ingress-controller"; };
      subjects = [{ kind = "ServiceAccount"; name = "caddy-ingress-controller"; namespace = "ingress-system"; }];
    };
  };
}
