{
  config,
  lib,
  ...
}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects = {
    none.Namespace.media = {
      metadata.labels =
        managed
        // {
          name = "media";
        };
    };

    # ============================================================
    # Shared media PV (large-nfs-storage = portable RWX, survives nodes)
    # ============================================================
    none.PersistentVolume.media-data-nexus-pv = {
      spec = {
        capacity.storage = "150Gi";
        accessModes = ["ReadWriteMany"];
        persistentVolumeReclaimPolicy = "Retain";
        storageClassName = "large-nfs-storage";
        nfs = {
          server = "10.1.1.120";
          path = "/srv/nfs/media";
        };
      };
    };

    media.PersistentVolumeClaim.media-data = {
      spec = {
        accessModes = ["ReadWriteMany"];
        storageClassName = "large-nfs-storage";
        resources.requests.storage = "150Gi";
      };
    };

    # ============================================================
    # qBittorrent (torrents -> /media/downloads)
    # ============================================================
    media.Deployment.qbittorrent = {
      metadata.labels = managed // {app = "qbittorrent";};
      spec = {
        replicas = 1;
        selector.matchLabels.app = "qbittorrent";
        template.metadata.labels = managed // {app = "qbittorrent";};
        template.spec = {
          nodeSelector."kubernetes.io/hostname" = "nexus";
          containers.qbittorrent = {
            image = "ghcr.io/linuxserver/qbittorrent:latest";
            imagePullPolicy = "IfNotPresent";
            env = [
              {name = "PUID"; value = "1000";}
              {name = "PGID"; value = "100";}
              {name = "TZ"; value = "America/Winnipeg";}
              {name = "WEBUI_PORT"; value = "8080";}
            ];
            ports = [{containerPort = 8080;}];
            volumeMounts = [
              {name = "config"; mountPath = "/config";}
              {name = "media"; mountPath = "/media";}
            ];
          };
          volumes = [
            {name = "config"; emptyDir = {};}
            {
              name = "media";
              persistentVolumeClaim.claimName = "media-data";
            }
          ];
        };
      };
    };

    media.Service.qbittorrent = {
      metadata.labels = managed // {app = "qbittorrent";};
      spec = {
        selector.app = "qbittorrent";
        ports = [{port = 8080; targetPort = 8080;}];
      };
    };

    # ============================================================
    # Sonarr (TV/anime series)
    # ============================================================
    media.Deployment.sonarr = {
      metadata.labels = managed // {app = "sonarr";};
      spec = {
        replicas = 1;
        selector.matchLabels.app = "sonarr";
        template.metadata.labels = managed // {app = "sonarr";};
        template.spec = {
          nodeSelector."kubernetes.io/hostname" = "nexus";
          containers.sonarr = {
            image = "ghcr.io/linuxserver/sonarr:latest";
            imagePullPolicy = "IfNotPresent";
            env = [
              {name = "PUID"; value = "1000";}
              {name = "PGID"; value = "100";}
              {name = "TZ"; value = "America/Winnipeg";}
            ];
            ports = [{containerPort = 8989;}];
            volumeMounts = [
              {name = "config"; mountPath = "/config";}
              {name = "media"; mountPath = "/media";}
            ];
          };
          volumes = [
            {name = "config"; emptyDir = {};}
            {
              name = "media";
              persistentVolumeClaim.claimName = "media-data";
            }
          ];
        };
      };
    };

    media.Service.sonarr = {
      metadata.labels = managed // {app = "sonarr";};
      spec = {
        selector.app = "sonarr";
        ports = [{port = 8989; targetPort = 8989;}];
      };
    };

    # ============================================================
    # Radarr (movies)
    # ============================================================
    media.Deployment.radarr = {
      metadata.labels = managed // {app = "radarr";};
      spec = {
        replicas = 1;
        selector.matchLabels.app = "radarr";
        template.metadata.labels = managed // {app = "radarr";};
        template.spec = {
          nodeSelector."kubernetes.io/hostname" = "nexus";
          containers.radarr = {
            image = "ghcr.io/linuxserver/radarr:latest";
            imagePullPolicy = "IfNotPresent";
            env = [
              {name = "PUID"; value = "1000";}
              {name = "PGID"; value = "100";}
              {name = "TZ"; value = "America/Winnipeg";}
            ];
            ports = [{containerPort = 7878;}];
            volumeMounts = [
              {name = "config"; mountPath = "/config";}
              {name = "media"; mountPath = "/media";}
            ];
          };
          volumes = [
            {name = "config"; emptyDir = {};}
            {
              name = "media";
              persistentVolumeClaim.claimName = "media-data";
            }
          ];
        };
      };
    };

    media.Service.radarr = {
      metadata.labels = managed // {app = "radarr";};
      spec = {
        selector.app = "radarr";
        ports = [{port = 7878; targetPort = 7878;}];
      };
    };

    # ============================================================
    # Prowlarr (indexers)
    # ============================================================
    media.Deployment.prowlarr = {
      metadata.labels = managed // {app = "prowlarr";};
      spec = {
        replicas = 1;
        selector.matchLabels.app = "prowlarr";
        template.metadata.labels = managed // {app = "prowlarr";};
        template.spec = {
          nodeSelector."kubernetes.io/hostname" = "nexus";
          containers.prowlarr = {
            image = "ghcr.io/linuxserver/prowlarr:latest";
            imagePullPolicy = "IfNotPresent";
            env = [
              {name = "PUID"; value = "1000";}
              {name = "PGID"; value = "100";}
              {name = "TZ"; value = "America/Winnipeg";}
            ];
            ports = [{containerPort = 9696;}];
            volumeMounts = [
              {name = "config"; mountPath = "/config";}
            ];
          };
          volumes = [
            {name = "config"; emptyDir = {};}
          ];
        };
      };
    };

    media.Service.prowlarr = {
      metadata.labels = managed // {app = "prowlarr";};
      spec = {
        selector.app = "prowlarr";
        ports = [{port = 9696; targetPort = 9696;}];
      };
    };

    # ============================================================
    # Bazarr (subtitles)
    # ============================================================
    media.Deployment.bazarr = {
      metadata.labels = managed // {app = "bazarr";};
      spec = {
        replicas = 1;
        selector.matchLabels.app = "bazarr";
        template.metadata.labels = managed // {app = "bazarr";};
        template.spec = {
          nodeSelector."kubernetes.io/hostname" = "nexus";
          containers.bazarr = {
            image = "ghcr.io/linuxserver/bazarr:latest";
            imagePullPolicy = "IfNotPresent";
            env = [
              {name = "PUID"; value = "1000";}
              {name = "PGID"; value = "100";}
              {name = "TZ"; value = "America/Winnipeg";}
            ];
            ports = [{containerPort = 6767;}];
            volumeMounts = [
              {name = "config"; mountPath = "/config";}
              {name = "media"; mountPath = "/media";}
            ];
          };
          volumes = [
            {name = "config"; emptyDir = {};}
            {
              name = "media";
              persistentVolumeClaim.claimName = "media-data";
            }
          ];
        };
      };
    };

    media.Service.bazarr = {
      metadata.labels = managed // {app = "bazarr";};
      spec = {
        selector.app = "bazarr";
        ports = [{port = 6767; targetPort = 6767;}];
      };
    };

    # ============================================================
    # Plex (playback)
    # ============================================================
    media.Deployment.plex = {
      metadata.labels = managed // {app = "plex";};
      spec = {
        replicas = 1;
        selector.matchLabels.app = "plex";
        template.metadata.labels = managed // {app = "plex";};
        template.spec = {
          nodeSelector."kubernetes.io/hostname" = "nexus";
          containers.plex = {
            image = "ghcr.io/linuxserver/plex:latest";
            imagePullPolicy = "IfNotPresent";
            env = [
              {name = "PUID"; value = "1000";}
              {name = "PGID"; value = "100";}
              {name = "TZ"; value = "America/Winnipeg";}
              {name = "VERSION"; value = "docker";}
            ];
            ports = [{containerPort = 32400;}];
            volumeMounts = [
              {name = "config"; mountPath = "/config";}
              {name = "media"; mountPath = "/media";}
            ];
          };
          volumes = [
            {name = "config"; emptyDir = {};}
            {
              name = "media";
              persistentVolumeClaim.claimName = "media-data";
            }
          ];
        };
      };
    };

    media.Service.plex = {
      metadata.labels = managed // {app = "plex";};
      spec = {
        selector.app = "plex";
        ports = [{port = 32400; targetPort = 32400;}];
      };
    };
  };
}
