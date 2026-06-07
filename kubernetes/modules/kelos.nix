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
    model = "$KELOS_MODEL"; # Dynamic — set by model-routing-controller
    enabled_providers = ["openai"];
    mcpServers = [
      {
        name = "searxng";
        type = "sse";
        url = "http://mcp-searxng-proxy.mcp.svc.cluster.local:8080/mcp";
      }
      {
        name = "kb-mcp";
        type = "sse";
        url = "http://mcp-kb-mcp-proxy.mcp.svc.cluster.local:8080/mcp";
      }
      {
        name = "memory";
        type = "sse";
        url = "http://mcp-memory-proxy.mcp.svc.cluster.local:8080/mcp";
      }
      {
        name = "selfhosted-tools";
        type = "sse";
        url = "http://mcp-selfhosted-tools-proxy.mcp.svc.cluster.local:8080/mcp";
      }
      {
        name = "sequential-thinking";
        type = "sse";
        url = "http://mcp-sequential-thinking-proxy.mcp.svc.cluster.local:8080/mcp";
      }
    ];
    provider.openai = {
      options = {
        baseURL = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1";
      };
      models = {
        "llama-3.1-70b-instruct" = {
          name = "Nemotron 70B";
          id = "nvidia/llama-3.1-nemotron-70b-instruct";
        };
        "nemotron-3-nano-30b-a3b" = {
          name = "Nemotron 3 Nano 30B";
          id = "nvidia/nemotron-3-nano-30b-a3b";
        };
        "nemotron-3-super-120b-a12b" = {
          name = "Nemotron 3 Super 120B";
          id = "nvidia/nemotron-3-super-120b-a12b";
        };
        "nemotron-3-nano-omni-30b-a3b-reasoning" = {
          name = "Nemotron 3 Nano Omni";
          id = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning";
        };
        "llama-3.3-nemotron-super-49b-v1" = {
          name = "Nemotron Super 49B";
          id = "nvidia/llama-3.3-nemotron-super-49b-v1.5";
        };
        "llama-3.1-70b-instruct-direct" = {
          name = "Nemotron 70B Direct";
          id = "nvidia/llama-3.1-nemotron-70b-instruct";
        };
      };
    };
  };

  # Shared setup command for all Workspaces
  setupCommand = [
    "/bin/sh"
    "-c"
    ''
          chmod -R g+rw /workspace/repo && mkdir -p /workspace/repo/.opencode/commands && REPO=''${KELOS_UPSTREAM_REPO:-unknown}

          case "$REPO" in
            *nixos-config*)
              cat > /workspace/repo/.opencode/commands/validate.md << 'CMDEOF'
      # Validate the NixOS configuration
      RUN nix flake check
      RUN just check
      CMDEOF
              cat > /workspace/repo/.opencode/commands/deploy.md << 'CMDEOF'
      # Deploy to a specific host
      ## Usage
      Use this to apply configuration changes to a cluster node.
      Make sure `nix flake check` passes first, then run:
      RUN just deploy
      CMDEOF
              ;;
            *maplespike*)
              cat > /workspace/repo/.opencode/commands/validate.md << 'CMDEOF'
      # Validate the MapleSpike monorepo
      RUN pnpm install --frozen-lockfile
      RUN pnpm -r build
      RUN pnpm test
      CMDEOF
              cat > /workspace/repo/.opencode/commands/build.md << 'CMDEOF'
      # Build all packages
      RUN pnpm build
      CMDEOF
              ;;
            *ai-inference-gateway*)
              cat > /workspace/repo/.opencode/commands/validate.md << 'CMDEOF'
      # Validate the AI Inference Gateway
      RUN pip install -e . -q
      RUN pytest tests/ -x -q
      CMDEOF
              ;;
            *knowledge-fabric*)
              cat > /workspace/repo/.opencode/commands/validate.md << 'CMDEOF'
      # Validate the Knowledge Fabric
      RUN npx tsc --noEmit
      CMDEOF
              ;;
            *)
              # Generic fallback
              cat > /workspace/repo/.opencode/commands/validate.md << 'CMDEOF'
      # Validate the project
      ## Run the appropriate validation for this repo
      RUN echo "No repo-specific validate command defined"
      CMDEOF
              ;;
          esac

          # Generate opencode.json using KELOS_MODEL env var (set by model-routing-controller)
          # Falls back to default model if env var not set (e.g., first-run or manual)
          MODEL="''${KELOS_MODEL:-openai/nvidia/nemotron-3-nano-30b-a3b}"
          FALLBACKS="''${KELOS_MODEL_FALLBACKS:-openai/qwen/qwen3-coder-480b-a35b-instruct}"
          cat > /workspace/repo/opencode.json << EOFOP
      ${opencodeConfig}
      EOFOP
          # Patch the opencode.json with the actual model from env var
          sed -i 's/"\$KELOS_MODEL"/"'"$MODEL"'"/g' /workspace/repo/opencode.json
          # Fallback models: pre-configured in opencodeConfig provider.openai.models above.
          # Add new fallbacks from KELOS_MODEL_FALLBACKS env var if they aren't already configured.
          # Note: sed targeting nested JSON keys doesn't work here — models are pre-configured statically.
          true
    ''
  ];

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
  workspaces =
    map (r: {
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
    })
    repos;

  # TaskSpawner template applied per repo
  taskSpawnerTemplate = r: {
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
      maxConcurrency = 3;
      taskTemplate = {
        type = "opencode";
        workspaceRef.name = r;
        model = "openai/nvidia/nemotron-3-nano-30b-a3b"; # Default — overridden by model-routing-controller
        agentConfigRef.name = "cluster-coder";
        branch = "kelos-task-{{.Number}}";
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

          MODEL ROUTING: The model in opencode.json was selected by the model-routing-controller
          based on the issue labels. Available models per task type:
          - coding: openai/nvidia/nemotron-3-super-120b-a12b (best for code)
          - analysis: openai/nvidia/nemotron-3-nano-30b-a3b (fast, cost-effective)
          - reasoning: openai/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning (optimized reasoning)
          - batch: openai/nvidia/nemotron-3-nano-30b-a3b (cheapest)
          - urgent: openai/nvidia/nemotron-3-super-120b-a12b (best quality)
          - vision: openai/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning
          - documentation: openai/qwen/qwen3-coder-480b-a35b-instruct
          Fallback: if your model is slow/unavailable, the gateway auto-routes.

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
            # Dynamic model routing — injected by model-routing-controller
            # Overrides the default model in opencode.json
            {
              name = "KELOS_MODEL";
              value = "openai/nvidia/nemotron-3-nano-30b-a3b";
            }
            {
              name = "KELOS_MODEL_FALLBACKS";
              value = "openai/qwen/qwen3-coder-480b-a35b-instruct,openai/nvidia/llama-3.1-nemotron-70b-instruct";
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
          # Override alpine/git entrypoint (defaults to "git") which breaks shell commands
          initContainers = [
            {
              name = "git-clone";
              image = "alpine/git:latest";
              entrypoint = [];
            }
            {
              name = "branch-setup";
              image = "alpine/git:latest";
              entrypoint = [];
            }
          ];
          affinity = {
            nodeAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution = {
                nodeSelectorTerms = [
                  {
                    matchExpressions = [
                      {
                        key = "kubernetes.io/hostname";
                        operator = "In";
                        values = ["nexus" "sentry"];
                      }
                    ];
                  }
                ];
              };
              preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 50;
                  preference.matchExpressions = [
                    {
                      key = "kubernetes.io/hostname";
                      operator = "In";
                      values = ["nexus"];
                    }
                  ];
                }
                {
                  weight = 30;
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
            podAntiAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 100;
                  podAffinityTerm = {
                    labelSelector.matchExpressions = [
                      {
                        key = "kelos.dev/taskspawner";
                        operator = "In";
                        values = ["github-issues-${r}"];
                      }
                    ];
                    topologyKey = "kubernetes.io/hostname";
                  };
                }
              ];
            };
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
            metadata.labels = {"app.kubernetes.io/part-of" = "kelos";};
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
                                print(f"    {p["metadata"]["name"]}")
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
                  requests = {
                    cpu = "50m";
                    memory = "64Mi";
                  };
                  limits = {
                    cpu = "200m";
                    memory = "128Mi";
                  };
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
                {
                  name = "K8S_NODE_NAME";
                  valueFrom.fieldRef.fieldPath = "spec.nodeName";
                }
              ];
            };
          };
        };
      };
    };
  };

  # ====================================================================
  # Dynamic Model Routing — per-task-type model selection
  # Updated by: model-routing-controller CronJob + kagent-kelos-model-optimizer skill
  # ====================================================================

  # Routing rules: model per task type with fallback chains
  # Reliability tiers: gold (most reliable) > silver > bronze (experimental)
  modelRoutingConfig = {
    default = {
      model = "openai/nvidia/nemotron-3-nano-30b-a3b";
      fallback = "openai/qwen/qwen3-coder-480b-a35b-instruct";
      reliability = "gold";
      reason = "General purpose — reliable, fast, always available";
    };
    coding = {
      model = "openai/nvidia/nemotron-3-super-120b-a12b";
      fallback = "openai/qwen/qwen3-coder-480b-a35b-instruct";
      reliability = "silver";
      reason = "Best code generation — Nemotron Super 120B";
    };
    analysis = {
      model = "openai/nvidia/nemotron-3-nano-30b-a3b";
      fallback = "openai/nvidia/llama-3.1-nemotron-70b-instruct";
      reliability = "gold";
      reason = "Good balance of speed/cost — Nano 30B";
    };
    reasoning = {
      model = "openai/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning";
      fallback = "openai/nvidia/nemotron-3-super-120b-a12b";
      reliability = "silver";
      reason = "Optimized reasoning — Omni 30B";
    };
    batch = {
      model = "openai/nvidia/nemotron-3-nano-30b-a3b";
      fallback = "openai/qwen/qwen3-coder-480b-a35b-instruct";
      reliability = "gold";
      reason = "Cheapest and most reliable — Nano 30B";
    };
    urgent = {
      model = "openai/nvidia/nemotron-3-super-120b-a12b";
      fallback = "openai/nvidia/nemotron-3-nano-30b-a3b";
      reliability = "silver";
      reason = "Best quality at good speed — Super 120B";
    };
    vision = {
      model = "openai/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning";
      fallback = "openai/nvidia/nemotron-3-super-120b-a12b";
      reliability = "bronze";
      reason = "Only vision-capable NIM model — Omni 30B";
    };
    documentation = {
      model = "openai/qwen/qwen3-coder-480b-a35b-instruct";
      fallback = "openai/nvidia/nemotron-3-nano-30b-a3b";
      reliability = "silver";
      reason = "Fast with good prose — Qwen 3 Coder 480B";
    };
  };

  # Serialized routing JSON for ConfigMap
  modelRoutingJSON = builtins.toJSON modelRoutingConfig;

  # ConfigMap: kelos-model-routing
  modelRoutingConfigMap = {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "kelos-model-routing";
      namespace = "kelos-system";
      labels = {
        "app.kubernetes.io/managed-by" = "easykubenix";
        "app.kubernetes.io/part-of" = "kelos";
      };
    };
    data = {
      "routing.json" = modelRoutingJSON;
      "last_updated" = "2026-05-23T00:00:00Z";
      "updated_by" = "nixos-config";
    };
  };

  # Model routing controller CronJob
  # Watches kelos-model-routing ConfigMap, patches TaskSpawners,
  # detects task types from issue labels, injects optimal models
  modelRoutingController = {
    apiVersion = "batch/v1";
    kind = "CronJob";
    metadata = {
      name = "model-routing-controller";
      namespace = "kelos-system";
      labels = {
        "app.kubernetes.io/managed-by" = "easykubenix";
        "app.kubernetes.io/part-of" = "kelos";
      };
    };
    spec = {
      schedule = "*/15 * * * *";
      concurrencyPolicy = "Forbid";
      jobTemplate.spec.template = {
        metadata.labels = {"app.kubernetes.io/part-of" = "kelos";};
        spec = {
          nodeName = "nexus";
          serviceAccountName = "pipeline-operator";
          restartPolicy = "OnFailure";
          containers = [
            {
              name = "controller";
              image = "nexus:5000/python:3.13-alpine";
              imagePullPolicy = "IfNotPresent";
              command = ["python3" "-c"];
              args = [
                ''
                  import json, os, urllib.request, datetime, ssl, time

                  ns = "kelos-system"
                  token = open("/var/run/secrets/kubernetes.io/serviceaccount/token").read()
                  host = os.environ.get("KUBERNETES_SERVICE_HOST", "kubernetes.default.svc")
                  port = os.environ.get("KUBERNETES_SERVICE_PORT", "443")
                  base = f"https://{host}:{port}"
                  ctx = ssl.create_default_context()
                  ctx.check_hostname = False
                  ctx.verify_mode = ssl.CERT_NONE

                  headers = {
                      "Authorization": f"Bearer {token}",
                      "Accept": "application/json",
                      "Content-Type": "application/json",
                  }

                  def k8s_get(path):
                      req = urllib.request.Request(f"{base}{path}", headers=headers)
                      return json.loads(urllib.request.urlopen(req, context=ctx).read())

                  def k8s_patch(path, body):
                      data = json.dumps(body).encode()
                      req = urllib.request.Request(f"{base}{path}", data=data, headers=headers, method="PATCH")
                      req.add_header("Content-Type", "application/merge-patch+json")
                      return json.loads(urllib.request.urlopen(req, context=ctx).read())

                  now = datetime.datetime.now(datetime.timezone.utc)
                  print(f"=== Model Routing Controller: {now} ===")

                  # 1. Load routing config
                  try:
                      cm = k8s_get(f"/api/v1/namespaces/{ns}/configmaps/kelos-model-routing")
                      routing = json.loads(cm["data"]["routing.json"])
                      print(f"  Loaded routing: {len(routing)} task types")
                      for t, c in routing.items():
                          if isinstance(c, dict):
                              m = c.get("model", "?")
                              r = c.get("reliability", "?")
                              print(f"    {t}: {m} ({r})")
                  except Exception as e:
                      print(f"  WARN: Cannot read ConfigMap: {e}")
                      routing = {}

                  # 2. Patch TaskSpawners
                  try:
                      items = k8s_get(f"/apis/kelos.dev/v1alpha1/namespaces/{ns}/taskspawners").get("items", [])
                      print(f"
                    Found {len(items)} TaskSpawners")

                      for sp in items:
                          name = sp["metadata"]["name"]
                          labels = sp.get("spec", {}).get("when", {}).get("githubIssues", {}).get("labels", [])
                          cur = sp.get("spec", {}).get("taskTemplate", {}).get("model", "")

                          # Detect task type
                          ttype = "default"
                          name_lower = name.lower()
                          if any(x in name_lower for x in ["fix", "bug"]): ttype = "reasoning"
                          elif "doc" in name_lower: ttype = "documentation"
                          elif "data" in name_lower: ttype = "analysis"
                          elif "cron" in name_lower or "batch" in name_lower: ttype = "batch"
                          for lbl in labels:
                              l = lbl.lower()
                              if l in routing: ttype = l; break

                          route = routing.get(ttype, routing.get("default", {}))
                          if isinstance(route, str): route = {"model": route}
                          target = route.get("model", "")
                          fallback = route.get("fallback", "")

                          if target and target != cur:
                              reliability = route.get("reliability", "unknown") if isinstance(route, dict) else "unknown"

                              # Skip re-patching if model was already degraded
                              if cur and reliability == "degraded" and cur == target:
                                  print(f"  {name}: {cur} (degraded, skipping re-patch)")
                                  continue

                              print(f"  {name}: {cur} -> {target} ({ttype}, rel:{reliability})")
                              env = sp.get("spec", {}).get("taskTemplate", {}).get("podOverrides", {}).get("env", [])
                              env = [e for e in env if e.get("name") not in ("KELOS_MODEL", "KELOS_MODEL_FALLBACKS", "KELOS_MODEL_RELIABILITY")]
                              env.append({"name": "KELOS_MODEL", "value": target})
                              if fallback:
                                  env.append({"name": "KELOS_MODEL_FALLBACKS", "value": fallback})
                              env.append({"name": "KELOS_MODEL_RELIABILITY", "value": reliability})

                              patch = {
                                  "metadata": {
                                      "annotations": {
                                          "kelos.dev/model-routing-last-update": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
                                          "kelos.dev/model-routing-reliability": reliability,
                                      }
                                  },
                                  "spec": {"taskTemplate": {"model": target, "podOverrides": {"env": env}}},
                              }
                              time.sleep(2)
                              k8s_patch(f"/apis/kelos.dev/v1alpha1/namespaces/{ns}/taskspawners/{name}", patch)
                          else:
                              print(f"  {name}: {cur} (up-to-date, {ttype})")

                      print(f"
                    Updated: {sum(1 for sp in items if sp["spec"]["taskTemplate"]["model"] != sp["spec"]["taskTemplate"].get("model", ""))}/{len(items)} spawners")

                      # Persist circuit breaker state to ConfigMap
                      if cb_state:
                          try:
                              r = dict(routing)
                              r["__circuit_breaker__"] = cb_state
                              cb_patch = {"data": {"routing.json": json.dumps(r)}}
                              k8s_patch(f"/api/v1/namespaces/{ns}/configmaps/kelos-model-routing", cb_patch)
                              print(f"  CB state saved ({len(cb_state)} entries)")
                          except Exception as e:
                              print(f"  WARN: CB state save failed: {e}")
                  except Exception as e:
                      print(f"  ERROR: {e}")

                  print("=== Model Routing Controller Complete ===")
                ''
              ];
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "200m";
                  memory = "128Mi";
                };
              };
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities.drop = ["ALL"];
                runAsNonRoot = true;
                runAsUser = 1001;
                seccompProfile.type = "RuntimeDefault";
              };
              env = [
                {
                  name = "K8S_NODE_NAME";
                  valueFrom.fieldRef.fieldPath = "spec.nodeName";
                }
              ];
            }
          ];
        };
      };
    };
  };

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

        ## Dynamic Model Routing
        The AI Inference Gateway is at http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1.
        The model in opencode.json is set by the model-routing-controller based on your task type.
        If you need a different model, set KELOS_MODEL env var in the pod.
        The gateway auto-routes to fallback models if primary is slow/unavailable.

        ## Task Type Detection
        Your task type was detected from issue labels. This determines which model was selected:
        - Labels containing "bug" or "fix" → reasoning model
        - Labels containing "documentation" or "doc" → documentation model
        - Labels containing "enhancement" or "feature" → coding model
        - No specific label → default (analysis) model

        ## Gateway verification
        Check gateway: http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1

        ## Critical: bash tool requires description
        Every bash call MUST include a description parameter (e.g., bash(command: "find .", description: "Search for files")).
        Without it, bash calls fail with SchemaError. Retry with description if you forget.

        ## Workflow
        - The workspace at /workspace/repo is writable
        - Branch: kelos-task-NNN
        - Every commit references #NNN
        - PR body: "Closes #NNN"
      '';
      mcpServers = [
        {
          name = "searxng";
          type = "sse";
          url = "http://mcp-searxng-proxy.mcp.svc.cluster.local:8080/mcp";
        }
        {
          name = "kb-mcp";
          type = "sse";
          url = "http://mcp-kb-mcp-proxy.mcp.svc.cluster.local:8080/mcp";
        }
        {
          name = "memory";
          type = "sse";
          url = "http://mcp-memory-proxy.mcp.svc.cluster.local:8080/mcp";
        }
        {
          name = "selfhosted-tools";
          type = "sse";
          url = "http://mcp-selfhosted-tools-proxy.mcp.svc.cluster.local:8080/mcp";
        }
        {
          name = "sequential-thinking";
          type = "sse";
          url = "http://mcp-sequential-thinking-proxy.mcp.svc.cluster.local:8080/mcp";
        }
        {
          name = "skills-mcp";
          type = "sse";
          url = "http://mcp-skills-mcp-proxy.mcp.svc.cluster.local:8080/mcp";
        }
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
    # Register apiMappings for kelos.dev CRDs
    kubernetes.apiMappings = {
      Workspace = "kelos.dev/v1alpha1";
      TaskSpawner = "kelos.dev/v1alpha1";
      AgentConfig = "kelos.dev/v1alpha1";
    };

    # Define resources via the objects system (replaces old rawResources)
    kubernetes.objects.kelos-system = {
      # Workspaces: one per repo, generated from the `repos` list
      Workspace = listToAttrs (map (r: {
          name = r;
          value = {
            metadata.labels = {
              "app.kubernetes.io/managed-by" = "easykubenix";
              "app.kubernetes.io/part-of" = "kelos";
            };
            spec = {
              repo = "https://github.com/reverb256/${r}.git";
              ref = "main";
              secretRef.name = "github-token";
              files = [];
              inherit setupCommand;
            };
          };
        })
        repos);

      # TaskSpawners: one per repo, uses taskSpawnerTemplate
      TaskSpawner = listToAttrs (map (r: let
          tpl = taskSpawnerTemplate r;
        in {
          name = tpl.metadata.name;
          value = {
            metadata.labels = tpl.metadata.labels or {};
            inherit (tpl) spec;
          };
        })
        repos);

      # AgentConfig: cluster-coder profile
      AgentConfig."cluster-coder" = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "easykubenix";
          "app.kubernetes.io/part-of" = "kelos";
        };
        inherit (agentConfig) spec;
      };

      # Model routing ConfigMap — per-task-type model routing rules
      ConfigMap."kelos-model-routing" = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "easykubenix";
          "app.kubernetes.io/part-of" = "kelos";
        };
        inherit (modelRoutingConfigMap) data;
      };

      # Model routing controller — keeps TaskSpawner models in sync
      CronJob."model-routing-controller" = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "easykubenix";
          "app.kubernetes.io/part-of" = "kelos";
        };
        inherit (modelRoutingController) spec;
      };

      # Model benchmark & quality evaluator — measures tok/s, evaluates PRs, optimizes routing
      CronJob."model-benchmark-eval" = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "easykubenix";
          "app.kubernetes.io/part-of" = "kelos";
        };
        spec = {
          schedule = "0 */6 * * *";
          concurrencyPolicy = "Forbid";
          jobTemplate.spec.template = {
            metadata.labels = {"app.kubernetes.io/part-of" = "kelos";};
            spec = {
              nodeName = "nexus";
              serviceAccountName = "pipeline-operator";
              restartPolicy = "OnFailure";
              containers = [
                {
                  name = "benchmarker";
                  image = "nexus:5000/python:3.13-alpine";
                  imagePullPolicy = "IfNotPresent";
                  command = ["python3" "/scripts/benchmark.py"];
                  volumeMounts = [
                    {
                      name = "script";
                      mountPath = "/scripts";
                    }
                  ];
                  resources = {
                    requests = {
                      cpu = "100m";
                      memory = "128Mi";
                    };
                    limits = {
                      cpu = "500m";
                      memory = "256Mi";
                    };
                  };
                  securityContext = {
                    allowPrivilegeEscalation = false;
                    capabilities.drop = ["ALL"];
                    runAsNonRoot = true;
                    runAsUser = 1001;
                    seccompProfile.type = "RuntimeDefault";
                  };
                }
              ];
              volumes = [
                {
                  name = "script";
                  configMap.name = "model-benchmark-script";
                }
              ];
            };
          };
        };
      };

      # Pipeline maintenance CronJob
      CronJob."pipeline-maintenance" = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "easykubenix";
          "app.kubernetes.io/part-of" = "kelos";
        };
        inherit (pipelineMaintenance) spec;
      };
    };
  };
}
