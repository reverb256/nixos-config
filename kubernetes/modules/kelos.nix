# Kelos task orchestration module.
# Controller self-manages Workspaces, TaskSpawners, AgentConfigs.
# This module bootstraps the initial config and provides fallback definitions.
# See: https://github.com/reverb256/kelos-controller
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kubernetes.kelos;
  inherit (cfg) repo;

  # Shared opencode.json config with NIM models via AI Inference Gateway
  opencodeConfig = lib.generators.toJSON {} {
    "$schema" = "https://opencode.ai/config.json";
    model = "nvidia/nemotron-3-super-120b-a12b";
    enabled_providers = ["openai"];
    provider.openai = {
      options = {
        baseURL = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1";
        apiKey = "\$OPENCODE_API_KEY";
      };
      models = {
         "nvidia/nemotron-3-super-120b-a12b" = {
          context_length = 131072;
          max_tokens = 16384;
           id = "nvidia/nemotron-3-super-120b-a12b";
           name = "nvidia/nemotron-3-super-120b-a12b";
        };
         "nvidia/nemotron-3-super-120b-a12b:free" = {
          context_length = 131072;
          max_tokens = 16384;
           id = "nvidia/nemotron-3-super-120b-a12b:free";
           name = "nvidia/nemotron-3-super-120b-a12b:free";
        };
        "nvidia/llama-3.3-nemotron-super-49b-v1" = {
          context_length = 131072;
          max_tokens = 16384;
          id = "nvidia/llama-3.3-nemotron-super-49b-v1";
          name = "nvidia/llama-3.3-nemotron-super-49b-v1";
        };
      };
    };
  };

  # Shared setup command for all Workspaces
  setupCommand = ["/bin/sh" "-c" ''
    chmod -R g+rw /workspace/repo && cat > /workspace/repo/opencode.json << 'EOFOP'
    ${opencodeConfig}
    EOFOP
    cat > /workspace/repo/AGENTS.md << 'EOFAG'
# Agent Instructions

## Caveman Communication
- Terse. Drop articles, filler, hedging, preamble.
- Start with answer. One fact per line.
- GitHub issues: terse title, bullet evidence, no fluff.
- Never narrate before doing.

## Cavecrew Work Pattern
- Decompose complex work into sub-tasks.
- Scout first (investigate), then build, then verify.
- Verification required after every change.
- Report findings as path:line tables.
- If task too big, break into smaller issues.

EOFAG
  ''];

  # Repos that get Kelos task automation
  repos = [
    "frostbite-gazette"
    "ai-inference-gateway"
    "caddy-ingress"
    "compute-market"
    "gpu-proxy"
    "knowledge-fabric"
    "llama-cpp-turboquant"
    "maplespike"
    "mcp-registry"
    "nixos-config"
    "searxng-cluster"
    "vane"
    "vllm-turboquant"
  ];

  # Create a workspace for each repo
  workspaces = map (r: {
    apiVersion = "kelos.dev/v1alpha1";
    kind = "Workspace";
    metadata = {
      name = r;
      namespace = "kelos-system";
      labels = {
        "app.kubernetes.io/managed-by" = "easykubenix";
        "app.kubernetes.io/part-of" = "kelos";
      };
    };
    spec = {
      repo = "https://github.com/reverb256/${r}.git";
      ref = "main";
      secretRef.name = "github-token";
      files = [];
      inherit setupCommand;
    };
  }) repos;

  # Pipeline maintenance CronJob - runs every 15min on nexus
  pipelineMaintenance = {
    apiVersion = "batch/v1";
    kind = "CronJob";
    metadata = {
      name = "pipeline-maintenance";
      namespace = "kelos-system";
      labels = {
        "app.kubernetes.io/managed-by" = "easykubenix";
        "app.kubernetes.io/part-of" = "kelos";
      };
    };
    spec = {
      schedule = "*/15 * * * *";
      concurrencyPolicy = "Forbid";
      jobTemplate = {
        spec = {
          template = {
            metadata.labels = { "app.kubernetes.io/part-of" = "kelos"; };
            spec = {
              nodeName = "nexus";
              serviceAccountName = "pipeline-operator";
              restartPolicy = "OnFailure";
              containers.operator = {
                image = "nexus:5000/python:3.13-alpine";
                imagePullPolicy = "IfNotPresent";
                command = ["python3" "-c"];
                args = [
                  ''
                  import json, os, urllib.request, datetime

                  # K8s API access via service account token
                  ns = "kelos-system"
                  token = open("/var/run/secrets/kubernetes.io/serviceaccount/token").read()
                  host = os.environ.get("KUBERNETES_SERVICE_HOST", "kubernetes.default.svc")
                  port = os.environ.get("KUBERNETES_SERVICE_PORT", "443")
                  base = f"https://{host}:{port}"
                  headers = {
                      "Authorization": f"Bearer {token}",
                      "Accept": "application/json",
                  }
                  ctx = urllib.request if not hasattr(urllib.request, 'HTTPSHandler') else urllib.request

                  def k8s_get(path):
                      req = urllib.request.Request(f"{base}{path}", headers=headers)
                      return json.loads(urllib.request.urlopen(req, context=ssl_context).read())

                  try:
                      import ssl
                      ssl_context = ssl.create_default_context()
                      ssl_context.check_hostname = False
                      ssl_context.verify_mode = ssl.CERT_NONE
                  except:
                      ssl_context = None

                  now = datetime.datetime.now(datetime.timezone.utc)
                  print(f"=== Pipeline Maintenance: {now} ===")

                  # Get tasks
                  try:
                      tasks = k8s_get(f"/apis/kelos.dev/v1alpha1/namespaces/{ns}/tasks")
                      items = tasks.get("items", [])
                      deleted = 0
                      for t in items:
                          name = t["metadata"]["name"]
                          phase = t.get("status", {}).get("phase", "")
                          created = t["metadata"]["creationTimestamp"]
                          ct = datetime.datetime.fromisoformat(created.replace("Z", "+00:00"))
                          age = now - ct
                          if phase == "Failed" and age.total_seconds() > 900:  # 15 min
                              print(f"  DELETE {name} (failed, age={age})")
                              req = urllib.request.Request(
                                  f"{base}/apis/kelos.dev/v1alpha1/namespaces/{ns}/tasks/{name}",
                                  method="DELETE", headers=headers)
                              try:
                                  urllib.request.urlopen(req, context=ssl_context)
                                  deleted += 1
                              except Exception as e:
                                  print(f"  FAILED to delete {name}: {e}")
                      print(f"  Deleted {deleted} stale tasks")
                  except Exception as e:
                      print(f"  Error fetching tasks: {e}")

                  # Pods on Zephyr
                  try:
                      pods = k8s_get(f"/api/v1/namespaces/{ns}/pods")
                      zephyr = [p for p in pods.get("items", [])
                               if p.get("spec", {}).get("nodeName") == "zephyr"]
                      if zephyr:
                          print(f"  WARNING: {len(zephyr)} pods on Zephyr!")
                          for p in zephyr:
                              print(f"    {p['metadata']['name']}")
                      else:
                          print(f"  No pods on Zephyr ✅")
                  except Exception as e:
                      print(f"  Error checking nodes: {e}")

                  # Summary
                  running = len([t for t in items if t.get("status", {}).get("phase") == "Running"])
                  failed = len([t for t in items if t.get("status", {}).get("phase") == "Failed"])
                  print(f"  Running: {running}, Failed: {failed}")
                  print("=== Done ===")
                  ''
                ];
                resources = {
                  requests = { cpu = "50m"; memory = "64Mi"; };
                  limits = { cpu = "200m"; memory = "128Mi"; };
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  capabilities.drop = ["ALL"];
                  runAsNonRoot = true;
                  runAsUser = 1001;
                  seccompProfile.type = "RuntimeDefault";
                };
              };
              env = [
                { name = "K8S_NODE_NAME"; valueFrom.fieldRef.fieldPath = "spec.nodeName"; }
              ];
            };
          };
        };
      };
    };

    apiVersion = "kelos.dev/v1alpha1";
    kind = "TaskSpawner";
    metadata = {
      name = "github-issues-${r}";
      namespace = "kelos-system";
      labels = {
        "app.kubernetes.io/managed-by" = "easykubenix";
        "app.kubernetes.io/part-of" = "kelos";
      };
    };
    spec = {
      maxConcurrency = 2;
      taskTemplate = {
        type = "opencode";
        workspaceRef.name = r;
        agentConfigRef.name = "cluster-coder";
        branch = "kelos-task-\{\{.Number\}\}";
        credentials = {
          type = "api-key";
          secretRef.name = "opencode-credentials";
        };
        promptTemplate = ''
          GitHub issue #{{.Number}}: {{.Title}}

          Description:
          {{.Body}}

          CRITICAL: Read the issue body above carefully. Implement the changes, push the branch, and open a PR against main.
          DO NOT stop until the PR is created. The task is not complete until a PR exists.

          You have up to 100 tool-calling steps available. Use them. Do not stop early.

          If you hit errors, retry with a different approach.

          IMPORTANT: Every bash tool call MUST include a "description" parameter describing what the command does.
          Correct: bash(command: "find .", description: "Search for files")
          Wrong:   bash(command: "find .") — this will FAIL with SchemaError

          Branch: kelos-task-{{.Number}}
          Every commit message must include #{{.Number}}.
          The workspace at /workspace/repo is writable — work directly there.
        '';
        podOverrides = {
          env = [
            {
              name = "OPENAI_API_KEY";
              valueFrom.secretKeyRef = {
                name = "opencode-credentials";
                key = "OPENAI_API_KEY";
              };
            }
            {
              name = "NVIDIA_API_KEY";
              valueFrom.secretKeyRef = {
                name = "opencode-credentials";
                key = "NVIDIA_API_KEY";
              };
            }
          ];
          resources = {
            limits = {
              cpu = "1";
              memory = "1Gi";
            };
            requests = {
              cpu = "250m";
              memory = "512Mi";
            };
          };
          podSecurityContext = {
            fsGroup = 1000;
            runAsGroup = 1000;
            runAsNonRoot = true;
            runAsUser = 1000;
          };
          containerSecurityContext = {
            allowPrivilegeEscalation = false;
            capabilities.drop = ["ALL"];
            runAsNonRoot = true;
            seccompProfile.type = "RuntimeDefault";
          };
          affinity.nodeAffinity = {
            preferredDuringSchedulingIgnoredDuringExecution = [
              {
                weight = 100;
                preference.matchExpressions = [
                  {
                    key = "kubernetes.io/hostname";
                    operator = "In";
                    values = ["nexus"];
                  }
                ];
              }
              {
                weight = 50;
                preference.matchExpressions = [
                  {
                    key = "kubernetes.io/hostname";
                    operator = "In";
                    values = ["sentry"];
                  }
                ];
              }
            ];
          };
        };
        ttlSecondsAfterFinished = 900;
      };
      when.githubIssues = {
        repo = "reverb256/${r}";
        state = "open";
        labels = ["agent-ready"];
        pollInterval = "5m";
      };
    };
  };

  taskSpawners = map taskSpawnerTemplate repos;

  # AgentConfig for task execution
  agentConfig = {
    apiVersion = "kelos.dev/v1alpha1";
    kind = "AgentConfig";
    metadata = {
      name = "cluster-coder";
      namespace = "kelos-system";
      labels = {
        "app.kubernetes.io/managed-by" = "easykubenix";
        "app.kubernetes.io/part-of" = "kelos";
      };
    };
    spec = {
      agentsMD = ''
        # Kelos Agent — Task Instructions

        You were spawned by Kelos because this issue has the "agent-ready" label.

        ## Your Job
        Implement the GitHub issue that spawned you. Read the issue body, make the changes, push the branch, and open a PR against main.
        DO NOT stop until you have created a pull request. If you hit an error, try a different approach.
        The task is not complete until a PR exists at github.com/reverb256/maplespike.

        ## Before implementing
        1. Read the issue body thoroughly — it contains the exact requirements and acceptance criteria
        2. Check for ## Previous Attempt Feedback in the body — if present, fix those problems first

        ## Gateway verification
        The AI Inference Gateway is at http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1.
        The model in opencode.json is configured and valid. Use webfetch (not bash/curl) if you need to check the gateway.

        ## Critical: bash tool requires description
        Every bash call MUST include a description parameter (e.g., bash(command: "find .", description: "Find files")).
        Without it, bash calls fail with SchemaError. Retry with description if you forget.

        ## Workflow
        - The workspace at /workspace/repo is writable
        - Branch: kelos-task-NNN
        - Every commit references #NNN
        - PR body: "Closes #NNN"
      '';
      mcpServers = [
        { name = "searxng"; type = "sse"; url = "http://mcp-searxng-proxy.mcp.svc.cluster.local:8080/mcp"; }
        { name = "kb-mcp"; type = "sse"; url = "http://mcp-kb-mcp-proxy.mcp.svc.cluster.local:8080/mcp"; }
        { name = "memory"; type = "sse"; url = "http://mcp-memory-proxy.mcp.svc.cluster.local:8080/mcp"; }
        { name = "selfhosted-tools"; type = "sse"; url = "http://mcp-selfhosted-tools-proxy.mcp.svc.cluster.local:8080/mcp"; }
        { name = "sequential-thinking"; type = "sse"; url = "http://mcp-sequential-thinking-proxy.mcp.svc.cluster.local:8080/mcp"; }
        { name = "skills-mcp"; type = "sse"; url = "http://mcp-skills-mcp-proxy.mcp.svc.cluster.local:8080/mcp"; }
      ];
    };
  };

in {
  options.kubernetes.kelos = {
    enable = mkEnableOption "Kelos task orchestration";

    repo = mkOption {
      type = types.str;
      default = "maplespike";
      description = "Default repository for Kelos tasks";
    };
  };

  config = mkIf cfg.enable {
    
  # ---- Pipeline Maintenance (applied imperatively, not via Nix) ----
  # pipeline-maintenance CronJob runs every 15min on nexus.
  # It deletes failed tasks older than 15min and checks for Zephyr pods.
  # Created imperatively via kubectl apply -f /tmp/pipeline-maintenance-cronjob.yaml
  # Resources: SA/ClusterRole/CRB pipeline-operator + CronJob in kelos-system
  # NOTE: maplespike-prod ImagePullBackOff and coredns-ha-enforcer are
  # pre-existing egress issues, not pipeline-related.

  kubernetes.rawResources = workspaces ++ taskSpawners ++ [agentConfig pipelineMaintenance];
  };
}
