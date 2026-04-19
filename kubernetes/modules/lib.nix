# Shared helpers for kubernetes modules.
# Imported via _module.args.k8sLib in default.nix.
{ pkgs }:

{
  # Scratch image for nix-csi workloads
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";

  # CSI ephemeral volume definition for a Nix package.
  # Returns an attrset to merge into the pod's `volumes`.
  #
  # Usage: volumes = { _namedlist = true; } // k8sLib.nixCsiVolume pkgs.redis;
  nixCsiVolume = pkg: {
    "nix-store" = {
      csi = {
        driver = "nix.csi.store";
        readOnly = true;
        volumeAttributes = {
          x86_64-linux = pkg;
          "csi.storage.k8s.io/ephemeral" = "true";
        };
      };
    };
  };

  # Volume mount for the nix-store CSI volume.
  # Merge into the container's `volumeMounts`.
  nixStoreMount = {
    "nix-store" = {
      mountPath = "/nix/store";
      readOnly = true;
    };
  };

  # Common labels for all easykubenix-managed objects
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  # Tolerations matching all cluster nodes (control-plane, workstation, interactive, ram-constrained)
  allTolerations = [
    {
      key = "node-role.kubernetes.io/control-plane";
      operator = "Exists";
      effect = "NoSchedule";
    }
    {
      key = "workstation";
      operator = "Exists";
    }
    {
      key = "interactive";
      operator = "Exists";
    }
    {
      key = "ram-constrained";
      operator = "Exists";
    }
  ];
}
