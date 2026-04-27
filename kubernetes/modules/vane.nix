{ pkgs, lib, ... }:
let
  copyConfigScript = ''
    if [ ! -f /data/config.json ]; then
      cp /config/config.json /data/config.json
      echo "Config copied from ConfigMap."
    else
      echo "Config already exists, keeping it."
    fi
  '';
  labels = {
    app = "vane";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
  gatewayUrl = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080";
in
{
  config.kubernetes.objects = {

    search.ConfigMap.vane-config = {
      metadata.labels = labels;
      data."config.json" = ''
        {
          "version": 1,
          "setupComplete": true,
          "preferences": {},
          "personalization": {},
          "modelProviders": [
            {
              "id": "local-gateway",
              "name": "Local Gateway",
              "type": "openai",
              "chatModels": [{"key": "Qwen3.5-4B.Q4_K_M.gguf", "name": "Qwen3.5-4B (Local)"}],
              "embeddingModels": [{"key": "BAAI/bge-m3", "name": "BGE-M3 (1024d)"}],
              "config": {"baseURL": "${gatewayUrl}/v1", "apiKey": "sk-placeholder"}
            },
            {
              "id": "zai-cloud",
              "name": "ZAI Cloud",
              "type": "openai",
              "chatModels": [{"key": "glm-5.1", "name": "GLM-5.1 (ZAI)"}],
              "embeddingModels": [],
              "config": {"baseURL": "${gatewayUrl}/v1", "apiKey": "sk-placeholder"}
            },
            {
              "id": "nvidia-nim",
              "name": "NVIDIA NIM",
              "type": "openai",
              "chatModels": [{"key": "nvidia/llama-3.3-nemotron-super-49b-v1", "name": "Nemotron-Super-49B (NIM)"}],
              "embeddingModels": [],
              "config": {"baseURL": "${gatewayUrl}/v1", "apiKey": "sk-placeholder"}
            }
          ],
          "search": {"searxngURL": "http://searxng.search.svc.cluster.local:8080"},
          "chatModel": {"providerId": "nvidia-nim", "key": "nvidia/llama-3.3-nemotron-super-49b-v1"},
          "embeddingModel": {"providerId": "local-gateway", "key": "BAAI/bge-m3"}
        }
      '';
    };

    search.Deployment.vane = {
      metadata.labels = labels;
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels = labels;
        strategy = { type = "Recreate"; rollingUpdate = null; };
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
                command = [ "/bin/sh" "-c" copyConfigScript ];
                volumeMounts = {
                  _namedlist = true;
                  data = { mountPath = "/data"; };
                  config = { mountPath = "/config"; readOnly = true; };
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
                  { name = "http"; containerPort = 30900; protocol = "TCP"; }
                ];
                resources = {
                  requests = { memory = "512Mi"; cpu = "250m"; };
                  limits = { memory = "2Gi"; cpu = "2"; };
                };
                readinessProbe = {
                  httpGet = { path = "/"; port = "http"; };
                  initialDelaySeconds = 15;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 6;
                };
                livenessProbe = {
                  httpGet = { path = "/"; port = "http"; };
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
              data.emptyDir = { };
              config.configMap.name = "vane-config";
            };
          };
        };
      };
    };

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
            ports = [ { protocol = "TCP"; port = 30900; } ];
          }
        ];
      };
    };

    search.NetworkPolicy.allow-vane-egress = {
      metadata.labels = labels // { policy = "allow-egress"; };
      spec = {
        podSelector.matchLabels.app = "vane";
        policyTypes = [ "Egress" ];
        egress = [
          {
            to = [
              { namespaceSelector.matchLabels.name = "kube-system"; }
            ];
            ports = [
              { protocol = "UDP"; port = 53; }
              { protocol = "TCP"; port = 53; }
            ];
          }
          {
            to = [ { ipBlock.cidr = "0.0.0.0/0"; } ];
          }
        ];
      };
    };
  };
}
