# GPU Miners via nix-csi CSI volumes
#
# AMD (5700 XT) and NVIDIA miner deployments using nix-csi CSI ephemeral
# volumes for /nix/store access instead of hostPath. Keeps hostPath only
# for hardware devices (/dev, /run/opengl-driver/lib, /etc/static).
#
# Requires nix-csi CSI driver deployed (nix-csi.nix).
#
# Phase 0: hostPath /nix/store (works immediately)
# Phase 1: CSI ephemeral volumes (after nix-csi driver is verified)
{
  pkgs,
  lib,
  config,
  ...
}: let
  # Toggle: false = hostPath /nix/store, true = CSI ephemeral volume
  useNixCsi = false;

  scratchImage = "nexus:5000/nix-csi/scratch:1.0.1";
  amdBaseImage = "docker.io/library/ubuntu:24.04";

  # lolMiner URL (pre-built binary, not from Nix store when using ubuntu image)
  lolminerUrl = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/lolminer-1-98a/lolMiner_v1.98a_Lin64.tar.gz";

  # AMD OpenCL environment (ocl-icd FIRST, then host driver)
  amdEnv = {
    _namedlist = true;
    LD_LIBRARY_PATH = {
      name = "LD_LIBRARY_PATH";
      value = "${pkgs.ocl-icd}/lib:/run/opengl-driver/lib";
    };
    OCL_ICD_VENDORS = {
      name = "OCL_ICD_VENDORS";
      value = "/etc/OpenCL/vendors/";
    };
    CUDA_VISIBLE_DEVICES = {
      name = "CUDA_VISIBLE_DEVICES";
      value = "";
    };
  };

  # Shared volume mounts for AMD miners
  amdVolumeMounts = {
    _namedlist = true;
    tmp = {mountPath = "/tmp";};
    opengl-driver = {mountPath = "/run/opengl-driver/lib";};
    dev = {mountPath = "/dev";};
    opencl-icd = {mountPath = "/etc/OpenCL/vendors";};
    etc-static = {
      mountPath = "/etc/static";
      readOnly = true;
    };
  };

  # Shared volumes for AMD miners
  amdVolumes = {
    _namedlist = true;
    tmp = {emptyDir = {};};
    opengl-driver = {hostPath.path = "/run/opengl-driver/lib";};
    dev = {
      hostPath = {
        path = "/dev";
        type = "Directory";
      };
    };
    opencl-icd = {
      hostPath = {
        path = "/etc/OpenCL/vendors";
        type = "Directory";
      };
    };
    etc-static = {
      hostPath = {
        path = "/etc/static";
        type = "Directory";
      };
    };
  };

  # Add nix-store to volumes/mounts based on mode
  amdVolumeMountsFinal =
    if useNixCsi
    then
      amdVolumeMounts
      // {
        nix-store = {
          mountPath = "/nix/store";
          readOnly = true;
        };
      }
    else
      amdVolumeMounts
      // {
        nix-store = {
          mountPath = "/nix/store";
          readOnly = true;
        };
      };

  amdVolumesFinal =
    if useNixCsi
    then
      amdVolumes
      // {
        nix-store = {
          csi = {
            driver = "nix.csi.store";
            readOnly = true;
            volumeAttributes = {
              storePath = "/nix/store";
            };
          };
        };
      }
    else
      amdVolumes
      // {
        nix-store = {
          hostPath = {
            path = "/nix/store";
            type = "Directory";
          };
        };
      };

  # Script to download and run lolMiner (for ubuntu base image)
  mkAmdScript = user: device: apiport: ''
    apt-get update && apt-get install -y curl ca-certificates \
      && mkdir -p /opt/lolminer \
      && curl -sL ${lolminerUrl} -o /tmp/lol.tar.gz \
      && tar xzf /tmp/lol.tar.gz -C /opt/lolminer \
      && chmod +x /opt/lolminer/lolMiner \
      && exec /opt/lolminer/lolMiner \
        --algo CR29 \
        --pool stratum+ssl://xtm-c29.kryptex.network:8040 \
        --user krxXVNVMM7.${user} \
        --pass x --tls on \
        --devices ${toString device} \
        --apiport ${toString apiport}
  '';

  # Template for an AMD miner deployment
  mkAmdDeployment = {
    name,
    user,
    device,
    apiport,
  }: {
    metadata.labels = {
      app = name;
      "mining-coin" = "xtm";
      "mining-group" = "amd";
      "gpu-vendor" = "amd";
      host = "forge";
      workload = "crypto-mining";
    };
    spec = {
      replicas = 1;
      revisionHistoryLimit = 1;
      selector.matchLabels.app = name;
      strategy.type = "Recreate";
      template = {
        metadata.labels = {app = name;};
        spec = {
          nodeName = "forge";
          hostNetwork = true;
          automountServiceAccountToken = false;
          priorityClassName = "mining-low";
          terminationGracePeriodSeconds = 30;
          containers = {
            _namedlist = true;
            miner = {
              image = amdBaseImage;
              imagePullPolicy = "IfNotPresent";
              command = ["/bin/sh" "-c"];
              args = [(mkAmdScript user device apiport)];
              env = amdEnv;
              livenessProbe = {
                tcpSocket.port = apiport;
                initialDelaySeconds = 60;
                periodSeconds = 30;
                failureThreshold = 5;
              };
              readinessProbe = {
                tcpSocket.port = apiport;
                initialDelaySeconds = 30;
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
              volumeMounts = amdVolumeMountsFinal;
            };
          };
          volumes = amdVolumesFinal;
        };
      };
    };
  };

  nixCsiDrv = useNixCsi;

  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects.mining = {
    Deployment.gpu-miner-forge-amd-0 = mkAmdDeployment {
      name = "gpu-miner-forge-amd-0";
      user = "forge-a0";
      device = 0;
      apiport = 4070;
    };

    Deployment.gpu-miner-forge-amd-1 = mkAmdDeployment {
      name = "gpu-miner-forge-amd-1";
      user = "forge-a1";
      device = 1;
      apiport = 4071;
    };
  };
}
