{
  pkgs,
  pkgsWithOverlay,
  config,
  lib,
  ...
}:
let
  # Base OS images (provide /bin/sh, wget, tar)
  nvidiaBaseImage = "docker.io/swamp7/bzminer:latest";
  amdBaseImage = "docker.io/swamp7/teamredminer:latest";

  # All Kryptex-hosted miner binaries (profit switching compatible)
  minerUrls = {
    rigel = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/rigel-1-23-2/rigel-1.23.2-linux.tar.gz";
    srbminer = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/srbminer-3-2-6/SRBMiner-Multi-3-2-6-Linux.tar.gz";
    bzminer = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/bzminer-24-0-1/bzminer_v24.0.1_linux.tar.gz";
    onezerominer = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/onezerominer-1-7-4/onezerominer-1.7.4.tar.gz";
    lolminer = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/lolminer-1-98a/lolMiner_v1.98a_Lin64.tar.gz";
  };

  # Download all miners to /opt/miners/ for profit switching
  downloadAllMiners = ''
    echo "Downloading all miners for profit switching..."
    mkdir -p /opt/miners
  '' + lib.concatStrings (lib.mapAttrsToList (name: url: ''
    wget -qO /tmp/${name}.tar.gz ${url} \
      && tar xzf /tmp/${name}.tar.gz -C /opt/miners/ \
      && find /opt/miners -name "${name}" -o -name "${name}.*" | head -5 \
      && echo "${name} extracted OK" \
      || echo "WARNING: ${name} download failed"
  '') minerUrls) + ''
    find /opt/miners -type f -executable -exec chmod +x {} \;
    echo "All miners available in /opt/miners/"
  '';

  openclIcd = "${pkgs.rocmPackages.clr}/etc/OpenCL/vendors";

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

  nvidiaEnv = {
    _namedlist = true;
    LD_LIBRARY_PATH = {
      name = "LD_LIBRARY_PATH";
      value = "/run/opengl-driver/lib";
    };
  };

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

  rvnPool = "stratum+tcp://rvn-us.kryptex.network:7031";
  rvnWallet = "krxXVNVMM7";
in
{
  config.kubernetes.objects = {

    mining.Deployment.gpu-miner-forge-nvidia-0 = {
      metadata.labels = {
        app = "gpu-miner-forge-nvidia-0";
        "gpu-vendor" = "nvidia";
        host = "forge";
        workload = "crypto-mining";
        "mining-coin" = "rvn";
        "mining-group" = "nvidia";
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
            runtimeClassName = "nvidia";
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            terminationGracePeriodSeconds = 30;
            containers = {
              _namedlist = true;
              miner = {
                image = nvidiaBaseImage;
                command = ["/bin/sh" "-c"];
                args = [
                  (downloadAllMiners
                  + " && RIGEL=$(find /opt/miners -name rigel -type f | head -1)"
                  + " && exec $RIGEL -a kawpow --coin rvn"
                  + " -o ${rvnPool}"
                  + " -u ${rvnWallet}.forge-n0"
                  + " -p x -w forge-n0 -d 0"
                  + " --api-bind 0.0.0.0:4068")
                ];
                env = {
                  _namedlist = true;
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib";
                  };
                };
                ports = [
                  {
                    containerPort = 4068;
                    name = "api";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = 4068;
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  tcpSocket.port = 4068;
                  initialDelaySeconds = 90;
                  periodSeconds = 15;
                  failureThreshold = 10;
                };
                resources = {
                  requests = {
                    memory = "2Gi";
                    cpu = "500m";
                  };
                  limits = {
                    memory = "4Gi";
                    cpu = "2";
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

    mining.Deployment.gpu-miner-forge-nvidia-1 = {
      metadata.labels = {
        app = "gpu-miner-forge-nvidia-1";
        "gpu-vendor" = "nvidia";
        host = "forge";
        workload = "crypto-mining";
        "mining-coin" = "rvn";
        "mining-group" = "nvidia";
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
            runtimeClassName = "nvidia";
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            terminationGracePeriodSeconds = 30;
            containers = {
              _namedlist = true;
              miner = {
                image = nvidiaBaseImage;
                command = ["/bin/sh" "-c"];
                args = [
                  (downloadAllMiners
                  + " && RIGEL=$(find /opt/miners -name rigel -type f | head -1)"
                  + " && exec $RIGEL -a kawpow --coin rvn"
                  + " -o ${rvnPool}"
                  + " -u ${rvnWallet}.forge-n1"
                  + " -p x -w forge-n1 -d 1"
                  + " --api-bind 0.0.0.0:4069")
                ];
                env = {
                  _namedlist = true;
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib";
                  };
                };
                ports = [
                  {
                    containerPort = 4069;
                    name = "api";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = 4069;
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  tcpSocket.port = 4069;
                  initialDelaySeconds = 90;
                  periodSeconds = 15;
                  failureThreshold = 10;
                };
                resources = {
                  requests = {
                    memory = "2Gi";
                    cpu = "500m";
                  };
                  limits = {
                    memory = "4Gi";
                    cpu = "2";
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

    mining.Deployment.gpu-miner-forge-amd-0 = {
      metadata.labels = {
        app = "gpu-miner-forge-amd-0";
        "mining-coin" = "rvn";
        "mining-group" = "amd";
      };
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
              teamredminer = {
                image = amdBaseImage;
                args = [
                  "-a" "kawpow"
                  "-o" rvnPool
                  "-u" "${rvnWallet}.forge-a0"
                  "-p" "x"
                  "--api_listen=0.0.0.0:4070"
                  "-d" "0"
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

    mining.Deployment.gpu-miner-forge-amd-1 = {
      metadata.labels = {
        app = "gpu-miner-forge-amd-1";
        "mining-coin" = "rvn";
        "mining-group" = "amd";
      };
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
              teamredminer = {
                image = amdBaseImage;
                args = [
                  "-a" "kawpow"
                  "-o" rvnPool
                  "-u" "${rvnWallet}.forge-a1"
                  "-p" "x"
                  "--api_listen=0.0.0.0:4071"
                  "-d" "1"
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

    mining.Deployment.gpu-miner-nexus = {
      metadata.labels = {
        app = "gpu-miner-nexus";
        host = "nexus";
        workload = "crypto-mining";
        "mining-coin" = "rvn";
        "mining-group" = "nvidia";
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
              miner = {
                image = nvidiaBaseImage;
                command = ["/bin/sh" "-c"];
                args = [
                  (downloadAllMiners
                  + " && RIGEL=$(find /opt/miners -name rigel -type f | head -1)"
                  + " && exec $RIGEL -a kawpow --coin rvn"
                  + " -o ${rvnPool}"
                  + " -u ${rvnWallet}.nexus-gpu"
                  + " -p x -w nexus-gpu -d 0"
                  + " --api-bind 0.0.0.0:4068")
                ];
                env = {
                  _namedlist = true;
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib";
                  };
                };
                ports = [
                  {
                    containerPort = 4068;
                    name = "api";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = 4068;
                  initialDelaySeconds = 120;
                  periodSeconds = 60;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  tcpSocket.port = 4068;
                  initialDelaySeconds = 60;
                  periodSeconds = 15;
                  failureThreshold = 10;
                };
                resources = {
                  requests = {
                    memory = "2Gi";
                    cpu = "500m";
                  };
                  limits = {
                    memory = "4Gi";
                    cpu = "2";
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

    mining.Deployment.gpu-miner-zephyr = {
      metadata = {
        labels = {
          app = "gpu-miner-zephyr";
          host = "zephyr";
          workload = "crypto-mining";
          "mining-coin" = "cfx";
          "mining-group" = "nvidia-3090";
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
            runtimeClassName = "nvidia";
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            terminationGracePeriodSeconds = 30;
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
              miner = {
                image = nvidiaBaseImage;
                imagePullPolicy = "IfNotPresent";
                command = ["/bin/sh" "-c"];
                args = [
                  (downloadAllMiners
                  + " && RIGEL=$(find /opt/miners -name rigel -type f | head -1)"
                  + " && exec $RIGEL -a octopus --coin cfx"
                  + " -o stratum+ssl://cfx-us.kryptex.network:8027"
                  + " -u ${rvnWallet}.zephyr-3090"
                  + " -p x -w zephyr-3090 -d 1"
                  + " --api-bind 0.0.0.0:4068")
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
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  tcpSocket.port = 4068;
                  initialDelaySeconds = 90;
                  periodSeconds = 15;
                  failureThreshold = 10;
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                }
                // nvidiaVolumeMounts;
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
            }
            // nvidiaVolumes;
          };
        };
      };
    };

    # --- GPU Miner for Zephyr 3060 Ti (on-demand by coordinator, replicas: 0) ---
    mining.Deployment.gpu-miner-zephyr-3060ti = {
      metadata.labels = {
        app = "gpu-miner-zephyr-3060ti";
        host = "zephyr";
        workload = "crypto-mining";
      };
      spec = {
        replicas = 0;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "gpu-miner-zephyr-3060ti";
          host = "zephyr";
        };
        strategy.type = "Recreate";
        template = {
          metadata.labels = {
            app = "gpu-miner-zephyr-3060ti";
            host = "zephyr";
            workload = "crypto-mining";
          };
          spec = {
            nodeName = "zephyr";
            serviceAccountName = "gpu-miner-sa";
            automountServiceAccountToken = false;
            hostNetwork = true;
            priorityClassName = "mining-low";
            tolerations = [
              { key = "workstation"; operator = "Exists"; }
              { key = "interactive"; operator = "Exists"; }
              {
                key = "node-role.kubernetes.io/control-plane";
                operator = "Exists";
                effect = "NoSchedule";
              }
            ];
            containers = {
              _namedlist = true;
              miner = {
                image = nvidiaBaseImage;
                imagePullPolicy = "IfNotPresent";
                command = ["/bin/sh" "-c"];
                args = [
                  (downloadAllMiners
                  + " && RIGEL=$(find /opt/miners -name rigel -type f | head -1)"
                  + " && exec $RIGEL -a kawpow --coin rvn"
                  + " -o ${rvnPool}"
                  + " -u ${rvnWallet}.zephyr-3060ti"
                  + " -p x -w zephyr-3060ti -d 0"
                  + " --api-bind 0.0.0.0:4069")
                ];
                env = {
                  _namedlist = true;
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value =
                      "/run/opengl-driver/lib:/usr/local/cuda-12.1/compat";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  dev = { mountPath = "/dev"; };
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
                    memory = "2Gi";
                    cpu = "100m";
                  };
                  limits = {
                    memory = "4Gi";
                    cpu = "500m";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              dev = { hostPath.path = "/dev"; };
              nvidia-libs = { hostPath.path = "/run/opengl-driver/lib"; };
              nix-store = { hostPath.path = "/nix/store"; };
            };
          };
        };
      };
    };
  };
}
