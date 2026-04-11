# GPU miners (lolMiner) — swamp7/lolminer Docker image for all nodes
#
# The Nix-built image (docker.io/library/lolminer:1.98a-nixos) uses symlinks to
# /nix/store paths that don't exist on other nodes (cross-node store mismatch).
# swamp7/lolminer is self-contained with the binary baked in (1.1 GiB).
#
# Converted from: kubernetes-manifests/mining/csi/gpu-miner-forge-*.yaml
#                 kubernetes-manifests/mining/gpu-miner-nexus.yaml
#                 kubernetes-manifests/mining/gpu-miner-zephyr.yaml
{
  pkgs,
  pkgsWithOverlay,
  config,
  lib,
  ...
}:
let
  # Self-contained lolminer image (1.1 GiB) — binary baked in, no Nix store deps
  # Pin to specific tag for reproducibility (swamp7 only publishes :latest)
  # Update by: crictl images | grep lolminer
  lolminerImage = "docker.io/swamp7/lolminer:latest";

  # AMD OpenCL ICD vendors path — uses host CLR (ROCm) installation on forge
  openclIcd = "/nix/store/6yvx83sa6iwhr6xnjjlfjg56jnki5mdn-clr-7.2.0-icd/etc/OpenCL/vendors";

  # NVIDIA volume mounts (GPU driver from host + Nix store for glibc)
  nvidiaVolumeMounts = {
    opengl-driver = {
      mountPath = "/run/opengl-driver/lib";
    };
    dev = {
      mountPath = "/dev";
    };
    nix-store = {
      mountPath = "/nix/store";
    };
  };

  # NVIDIA volumes (host-side)
  nvidiaVolumes = {
    opengl-driver = {
      hostPath.path = "/run/opengl-driver/lib";
    };
    dev = {
      hostPath = {
        path = "/dev";
        type = "Directory";
      };
    };
    nix-store = {
      hostPath.path = "/nix/store";
    };
  };

  # AMD volume mounts (DRI/KFD/OpenCL + Nix store for glibc)
  amdVolumeMounts = {
    opengl-driver = {
      mountPath = "/run/opengl-driver/lib";
    };
    dri = {
      mountPath = "/dev/dri";
    };
    kfd = {
      mountPath = "/dev/kfd";
    };
    opencl-icd = {
      mountPath = "/etc/OpenCL/vendors";
    };
    nix-store = {
      mountPath = "/nix/store";
    };
  };

  # AMD volumes (host-side)
  amdVolumes = {
    opengl-driver = {
      hostPath.path = "/run/opengl-driver/lib";
    };
    dri = {
      hostPath = {
        path = "/dev/dri";
        type = "Directory";
      };
    };
    kfd = {
      hostPath = {
        path = "/dev/kfd";
        type = "CharDevice";
      };
    };
    opencl-icd = {
      hostPath = {
        path = openclIcd;
        type = "Directory";
      };
    };
    nix-store = {
      hostPath.path = "/nix/store";
    };
  };

  # Common env for NVIDIA miners
  nvidiaEnv = {
    _namedlist = true;
    LD_LIBRARY_PATH = {
      name = "LD_LIBRARY_PATH";
      value = "/run/opengl-driver/lib";
    };
  };

  # Common env for AMD miners
  amdEnv = {
    _namedlist = true;
    LD_LIBRARY_PATH = {
      name = "LD_LIBRARY_PATH";
      value = "/run/opengl-driver/lib";
    };
    OCL_ICD_VENDORS = {
      name = "OCL_ICD_VENDORS";
      value = "/etc/OpenCL/vendors/";
    };
  };

  # Common lolMiner args for all miners
  # --algo=CR29, dual pool (US+EU kryptex), TLS
  commonArgs = [
    "--algo=CR29"
    "--pool=xtm-c29-us.kryptex.network:8040"
    "--tls=1"
    "--pool=xtm-c29-eu.kryptex.network:8040"
    "--tls=1"
  ];
in
{
  config.kubernetes.objects = {

    # ── Forge NVIDIA GPU 0 ─────────────────────────────────────
    mining.Deployment.gpu-miner-forge-nvidia-0 = {
      metadata.labels = {
        app = "gpu-miner-forge-nvidia-0";
        "gpu-vendor" = "nvidia";
        host = "forge";
        workload = "crypto-mining";
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "gpu-miner-forge-nvidia-0";
          "gpu-vendor" = "nvidia";
          host = "forge";
        };
        strategy.type = "Recreate";
        template = {
          metadata.labels = {
            app = "gpu-miner-forge-nvidia-0";
            "gpu-vendor" = "nvidia";
            host = "forge";
            workload = "crypto-mining";
          };
          spec = {
            nodeName = "forge";
            hostNetwork = true;
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            terminationGracePeriodSeconds = 30;
            containers = {
              _namedlist = true;
              lolminer = {
                image = lolminerImage;
                args = commonArgs ++ [
                  "--user=krxXVNVMM7.forge-n0"
                  "--pass=x"
                  "--user=krxXVNVMM7.forge-n0"
                  "--pass=x"
                  "--devices=0"
                  "--apiport=4068"
                  "--cclk=2350 --moff=1100 --pl=90"
                ];
                env = nvidiaEnv;
                ports = [
                  {
                    containerPort = 4068;
                    name = "api";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = 4068;
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  tcpSocket.port = 4068;
                  initialDelaySeconds = 60;
                  periodSeconds = 15;
                  failureThreshold = 10;
                };
                resources = {
                  requests = {
                    memory = "4Gi";
                    cpu = "2";
                  };
                  limits = {
                    memory = "8Gi";
                    cpu = "4";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                }
                // nvidiaVolumeMounts;
              };
            };
            volumes = {
              _namedlist = true;
            }
            // nvidiaVolumes;
          };
        };
      };
    };

    # ── Forge NVIDIA GPU 1 ─────────────────────────────────────
    mining.Deployment.gpu-miner-forge-nvidia-1 = {
      metadata.labels = {
        app = "gpu-miner-forge-nvidia-1";
        "gpu-vendor" = "nvidia";
        host = "forge";
        workload = "crypto-mining";
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "gpu-miner-forge-nvidia-1";
          "gpu-vendor" = "nvidia";
          host = "forge";
        };
        strategy.type = "Recreate";
        template = {
          metadata.labels = {
            app = "gpu-miner-forge-nvidia-1";
            "gpu-vendor" = "nvidia";
            host = "forge";
            workload = "crypto-mining";
          };
          spec = {
            nodeName = "forge";
            hostNetwork = true;
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            terminationGracePeriodSeconds = 30;
            containers = {
              _namedlist = true;
              lolminer = {
                image = lolminerImage;
                args = commonArgs ++ [
                  "--user=krxXVNVMM7.forge-n1"
                  "--pass=x"
                  "--user=krxXVNVMM7.forge-n1"
                  "--pass=x"
                  "--devices=1"
                  "--apiport=4069"
                  "--cclk=2350 --moff=1100 --pl=90"
                ];
                env = nvidiaEnv;
                ports = [
                  {
                    containerPort = 4069;
                    name = "api";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = 4069;
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  tcpSocket.port = 4069;
                  initialDelaySeconds = 60;
                  periodSeconds = 15;
                  failureThreshold = 10;
                };
                resources = {
                  requests = {
                    memory = "4Gi";
                    cpu = "2";
                  };
                  limits = {
                    memory = "8Gi";
                    cpu = "4";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                }
                // nvidiaVolumeMounts;
              };
            };
            volumes = {
              _namedlist = true;
            }
            // nvidiaVolumes;
          };
        };
      };
    };

    # ── Forge AMD GPU 0 ────────────────────────────────────────
    mining.Deployment.gpu-miner-forge-amd-0 = {
      metadata.labels.app = "gpu-miner-forge-amd-0";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "gpu-miner-forge-amd-0";
        strategy.type = "Recreate";
        template = {
          metadata.labels.app = "gpu-miner-forge-amd-0";
          spec = {
            nodeName = "forge";
            hostNetwork = true;
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            terminationGracePeriodSeconds = 30;
            containers = {
              _namedlist = true;
              lolminer = {
                image = lolminerImage;
                args = commonArgs ++ [
                  "--user=krxXVNVMM7.forge-a0"
                  "--pass=x"
                  "--user=krxXVNVMM7.forge-a0"
                  "--pass=x"
                  "--devices=0"
                  "--apiport=4070"
                ];
                env = amdEnv;
                ports = [
                  {
                    containerPort = 4070;
                    name = "api";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = 4070;
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  tcpSocket.port = 4070;
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                resources = {
                  requests = {
                    memory = "512Mi";
                    cpu = "500m";
                  };
                  limits = {
                    memory = "2Gi";
                    cpu = "2";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                }
                // amdVolumeMounts;
              };
            };
            volumes = {
              _namedlist = true;
            }
            // amdVolumes;
          };
        };
      };
    };

    # ── Forge AMD GPU 1 ────────────────────────────────────────
    mining.Deployment.gpu-miner-forge-amd-1 = {
      metadata.labels.app = "gpu-miner-forge-amd-1";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "gpu-miner-forge-amd-1";
        strategy.type = "Recreate";
        template = {
          metadata.labels.app = "gpu-miner-forge-amd-1";
          spec = {
            nodeName = "forge";
            hostNetwork = true;
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            terminationGracePeriodSeconds = 30;
            containers = {
              _namedlist = true;
              lolminer = {
                image = lolminerImage;
                args = commonArgs ++ [
                  "--user=krxXVNVMM7.forge-a1"
                  "--pass=x"
                  "--user=krxXVNVMM7.forge-a1"
                  "--pass=x"
                  "--devices=1"
                  "--apiport=4071"
                ];
                env = amdEnv;
                ports = [
                  {
                    containerPort = 4071;
                    name = "api";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = 4071;
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  tcpSocket.port = 4071;
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                resources = {
                  requests = {
                    memory = "512Mi";
                    cpu = "500m";
                  };
                  limits = {
                    memory = "2Gi";
                    cpu = "2";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                }
                // amdVolumeMounts;
              };
            };
            volumes = {
              _namedlist = true;
            }
            // amdVolumes;
          };
        };
      };
    };

    # ── Nexus NVIDIA GPU ───────────────────────────────────────
    mining.Deployment.gpu-miner-nexus = {
      metadata.labels = {
        app = "gpu-miner-nexus";
        host = "nexus";
        workload = "crypto-mining";
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "gpu-miner-nexus";
          host = "nexus";
        };
        strategy.type = "Recreate";
        template = {
          metadata.labels = {
            app = "gpu-miner-nexus";
            host = "nexus";
            workload = "crypto-mining";
          };
          spec = {
            nodeName = "nexus";
            hostNetwork = true;
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            tolerations = [
              {
                key = "node-role.kubernetes.io/control-plane";
                operator = "Exists";
                effect = "NoSchedule";
              }
            ];
            terminationGracePeriodSeconds = 30;
            containers = {
              _namedlist = true;
              lolminer = {
                image = lolminerImage;
                args = commonArgs ++ [
                  "--user=krxXVNVMM7.nexus-gpu"
                  "--pass=x"
                  "--user=krxXVNVMM7.nexus-gpu"
                  "--pass=x"
                  "--devices=0"
                  "--apiport=4068"
                  "--cclk=1605 --moff=1500 --pl=120"
                ];
                env = nvidiaEnv;
                ports = [
                  {
                    containerPort = 4068;
                    name = "api";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = 4068;
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  tcpSocket.port = 4068;
                  initialDelaySeconds = 60;
                  periodSeconds = 15;
                  failureThreshold = 10;
                };
                resources = {
                  requests = {
                    memory = "4Gi";
                    cpu = "2";
                  };
                  limits = {
                    memory = "8Gi";
                    cpu = "4";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                }
                // nvidiaVolumeMounts;
              };
            };
            volumes = {
              _namedlist = true;
            }
            // nvidiaVolumes;
          };
        };
      };
    };

    # ── Zephyr GPU ────────────────────────────────────────────
    # RTX 3090 GPU 1 only — RTX 3060 Ti (GPU 0) reserved for AI/gaming
    # Power limit 250W, mem offset +1300 (3090 mining sweet spot)
    mining.Deployment.gpu-miner-zephyr = {
      metadata = {
        labels = {
          app = "gpu-miner-zephyr";
          host = "zephyr";
          workload = "crypto-mining";
        };
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector = {
          matchLabels = {
            app = "gpu-miner-zephyr";
            host = "zephyr";
          };
        };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels = {
              app = "gpu-miner-zephyr";
              host = "zephyr";
              workload = "crypto-mining";
            };
          };
          spec = {
            nodeName = "zephyr";
            hostNetwork = true;
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            tolerations = [
              {
                key = "workstation";
                operator = "Exists";
              }
              {
                key = "interactive";
                operator = "Exists";
              }
              {
                key = "node-role.kubernetes.io/control-plane";
                operator = "Exists";
                effect = "NoSchedule";
              }
            ];
            containers = {
              _namedlist = true;
              lolminer = {
                image = lolminerImage;
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--algo=CR29"
                  "--pool=xtm-c29-us.kryptex.network:8040"
                  "--user=krxXVNVMM7.zephyr-gpu"
                  "--pass=x"
                  "--tls=1"
                  "--pool=xtm-c29-eu.kryptex.network:8040"
                  "--user=krxXVNVMM7.zephyr-gpu"
                  "--pass=x"
                  "--tls=1"
                  "--devices=1"
                  "--pl=250"
                  "--moff=1300"
                  "--apiport=4068"
                ];
                env = {
                  _namedlist = true;
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib:/usr/local/cuda-12.1/compat";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  dev = {
                    mountPath = "/dev";
                  };
                  nvidia-libs = {
                    mountPath = "/run/opengl-driver/lib";
                    readOnly = true;
                  };
                  nix-store = {
                    mountPath = "/nix/store";
                    readOnly = true;
                  };
                };
                resources = {
                  requests = {
                    memory = "4Gi";
                    cpu = "100m";
                  };
                  limits = {
                    memory = "8Gi";
                    cpu = "1000m";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              dev = {
                hostPath.path = "/dev";
              };
              nvidia-libs = {
                hostPath.path = "/run/opengl-driver/lib";
              };
              nix-store = {
                hostPath.path = "/nix/store";
              };
            };
          };
        };
      };
    };
  };
}
