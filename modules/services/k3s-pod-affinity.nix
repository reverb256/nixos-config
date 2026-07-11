{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.k3s-pod-affinity;
in {
  options.services.k3s-pod-affinity = {
    enable = lib.mkEnableOption "Kubernetes pod affinity rules for cluster";

    nodeAffinity = lib.mkOption {
      type = lib.types.attrs;
      default = {
        # Orchestrator pods avoid nexus (GPU mining node)
        "ai-inference" = {
          "fusion" = "avoid nexus";
          "vane" = "avoid nexus";
        };
        # Backend services prefer sentry
        "monitoring" = {
          "prometheus" = "prefer sentry";
          "grafana" = "prefer sentry";
        };
        "glitchtip" = {
          "glitchtip" = "prefer sentry";
        };
        "search" = {
          "searxng" = "prefer sentry";
        };
        "maplespike" = {
          "maplespike-api" = "prefer sentry";
        };
      };
      description = "Pod affinity rules (namespace -> app -> preference)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Pod affinity manifests to apply via kubectl
    environment.etc."kubernetes/manifests/pod-affinity.yaml".text = lib.generators.toYAML {} {
      apiVersion = "v1";
      kind = "Namespace";
      metadata = {
        name = "ai-inference";
        labels = {
          "pod-security.kubernetes.io/enforce" = "privileged";
        };
      };
    };

    # Systemd service to apply pod affinity rules after k3s starts
    systemd.services.k3s-pod-affinity = {
      description = "Apply pod affinity rules to Kubernetes cluster";
      wantedBy = ["multi-user.target"];
      after = ["k3s.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "apply-pod-affinity" ''
          set -e

          # Wait for k3s to be ready
          until ${pkgs.kubernetes}/bin/kubectl cluster-info &>/dev/null; do
            echo "[k3s-pod-affinity] Waiting for k3s to be ready..."
            sleep 5
          done

          echo "[k3s-pod-affinity] Applying pod affinity rules..."

          # Create affinity patches for deployments
          # Use kubectl patch to add nodeAffinity to existing deployments

          # Fusion - avoid nexus
          ${pkgs.kubernetes}/bin/kubectl patch deployment fusion -n ai-inference \
            --patch='{
              "spec": {
                "template": {
                  "spec": {
                    "affinity": {
                      "nodeAffinity": {
                        "preferredDuringSchedulingIgnoredDuringExecution": [{
                          "weight": 100,
                          "preference": {
                            "matchExpressions": [{
                              "key": "kubernetes.io/hostname",
                              "operator": "NotIn",
                              "values": ["nexus"]
                            }]
                          }
                        }]
                      }
                    }
                  }
                }
              }
            }' 2>/dev/null || echo "[k3s-pod-affinity] Fusion not found or already patched"

          # Vane - avoid nexus
          ${pkgs.kubernetes}/bin/kubectl patch deployment vane -n ai-inference \
            --patch='{
              "spec": {
                "template": {
                  "spec": {
                    "affinity": {
                      "nodeAffinity": {
                        "preferredDuringSchedulingIgnoredDuringExecution": [{
                          "weight": 100,
                          "preference": {
                            "matchExpressions": [{
                              "key": "kubernetes.io/hostname",
                              "operator": "NotIn",
                              "values": ["nexus"]
                            }]
                          }
                        }]
                      }
                    }
                  }
                }
              }
            }' 2>/dev/null || echo "[k3s-pod-affinity] Vane not found or already patched"

          # Prometheus - prefer sentry
          ${pkgs.kubernetes}/bin/kubectl patch deployment prometheus -n monitoring \
            --patch='{
              "spec": {
                "template": {
                  "spec": {
                    "affinity": {
                      "nodeAffinity": {
                        "preferredDuringSchedulingIgnoredDuringExecution": [{
                          "weight": 100,
                          "preference": {
                            "matchExpressions": [{
                              "key": "kubernetes.io/hostname",
                              "operator": "In",
                              "values": ["sentry"]
                            }]
                          }
                        }]
                      }
                    }
                  }
                }
              }
            }' 2>/dev/null || echo "[k3s-pod-affinity] Prometheus not found or already patched"

          # Grafana - prefer sentry
          ${pkgs.kubernetes}/bin/kubectl patch deployment grafana -n monitoring \
            --patch='{
              "spec": {
                "template": {
                  "spec": {
                    "affinity": {
                      "nodeAffinity": {
                        "preferredDuringSchedulingIgnoredDuringExecution": [{
                          "weight": 100,
                          "preference": {
                            "matchExpressions": [{
                              "key": "kubernetes.io/hostname",
                              "operator": "In",
                              "values": ["sentry"]
                            }]
                          }
                        }]
                      }
                    }
                  }
                }
              }
            }' 2>/dev/null || echo "[k3s-pod-affinity] Grafana not found or already patched"

          # SearXNG - prefer sentry
          ${pkgs.kubernetes}/bin/kubectl patch deployment searxng -n search \
            --patch='{
              "spec": {
                "template": {
                  "spec": {
                    "affinity": {
                      "nodeAffinity": {
                        "preferredDuringSchedulingIgnoredDuringExecution": [{
                          "weight": 100,
                          "preference": {
                            "matchExpressions": [{
                              "key": "kubernetes.io/hostname",
                              "operator": "In",
                              "values": ["sentry"]
                            }]
                          }
                        }]
                      }
                    }
                  }
                }
              }
            }' 2>/dev/null || echo "[k3s-pod-affinity] SearXNG not found or already patched"

          # Maplespike API - prefer sentry
          ${pkgs.kubernetes}/bin/kubectl patch deployment maplespike-api -n maplespike \
            --patch='{
              "spec": {
                "template": {
                  "spec": {
                    "affinity": {
                      "nodeAffinity": {
                        "preferredDuringSchedulingIgnoredDuringExecution": [{
                          "weight": 100,
                          "preference": {
                            "matchExpressions": [{
                              "key": "kubernetes.io/hostname",
                              "operator": "In",
                              "values": ["sentry"]
                            }]
                          }
                        }]
                      }
                    }
                  }
                }
              }
            }' 2>/dev/null || echo "[k3s-pod-affinity] Maplespike API not found or already patched"

          echo "[k3s-pod-affinity] Pod affinity rules applied successfully"
        '';
        RemainAfterExit = true;
      };
    };
  };
}