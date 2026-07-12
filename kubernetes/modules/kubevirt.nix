{ pkgs, lib, ... }:
let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  # GPU PCI IDs on nexus (verified via lspci 2026-07-11)
  #   0000:0a:00.0  GA104 [RTX 3060 Ti]            10de:2486
  #   0000:0a:00.1  GA104 High Definition Audio    10de:228b
  # These are bound to vfio-pci at boot on nexus (see hosts/nexus/configuration.nix)
  # so the VM owns the physical GPU and drives the connected 4K TV.
  gpuResourceName = "nvidia.com/ga104";
in
{
  config = {
    # ── Static operator/CRD YAML (committed, like tailscale) ───────────────
    importyaml.kubevirt-operator = {
      src = pkgs.runCommand "kubevirt-operator.yaml" { } ''
        cp ${../../kubernetes-manifests/kubevirt/operator.yaml} $out
      '';
    };
    importyaml.cdi-operator = {
      src = pkgs.runCommand "cdi-operator.yaml" { } ''
        cp ${../../kubernetes-manifests/kubevirt/cdi-operator.yaml} $out
      '';
    };
    importyaml.cdi-cr = {
      src = pkgs.runCommand "cdi-cr.yaml" { } ''
        cp ${../../kubernetes-manifests/kubevirt/cdi-cr.yaml} $out
      '';
    };
    importyaml.nexus-de-vm = {
      src = pkgs.runCommand "nexus-de-vm.yaml" { } ''
        cp ${../../kubernetes-manifests/kubevirt/nexus-de-vm.yaml} $out
      '';
    };

    kubernetes.objects = {
      # ── Namespaces (privileged PSA — KubeVirt runs virt-launcher as root) ──
      none.Namespace.kubevirt = {
        metadata.labels = managed // {
          "pod-security.kubernetes.io/enforce" = "privileged";
          "pod-security.kubernetes.io/audit" = "privileged";
          "pod-security.kubernetes.io/warn" = "privileged";
        };
      };
      none.Namespace.cdi = {
        metadata.labels = managed // {
          "pod-security.kubernetes.io/enforce" = "privileged";
          "pod-security.kubernetes.io/audit" = "privileged";
          "pod-security.kubernetes.io/warn" = "privileged";
        };
      };
      none.Namespace."nexus-de" = {
        metadata.labels = managed // {
          "pod-security.kubernetes.io/enforce" = "privileged";
          "pod-security.kubernetes.io/audit" = "privileged";
          "pod-security.kubernetes.io/warn" = "privileged";
        };
      };

      # ── Exempt KubeVirt/CDI namespaces from the cluster-wide runAsNonRoot policy
      #    (infrastructure.nix ValidatingAdmissionPolicy.require-resources-and-security).
      #    KubeVirt's virt-handler/virt-launcher/pods run privileged as root; the
      #    policy would otherwise reject every KubeVirt pod at admission.
      none.ValidatingAdmissionPolicyBinding.exempt-kubevirt = {
        metadata.labels = managed;
        spec = {
          policyName = "require-resources-and-security";
          action = "Exempt";
          matchResources = {
            namespaceSelector = {
              matchExpressions = [
                {
                  key = "kubernetes.io/metadata.name";
                  operator = "In";
                  values = [ "kubevirt" "cdi" "nexus-de" ];
                }
              ];
            };
          };
        };
      };

      # ── KubeVirt CR: full spec (do NOT also import the static kubevirt-cr.yaml —
      #    only one KubeVirt CR may exist). Registers the VFIO-passed GPU as a
      #    permitted host device so a VirtualMachine can reference deviceName
      #    nvidia.com/ga104. (CDI CR is imported separately via importyaml.cdi-cr.)
      none.KubeVirt.kubevirt = {
        metadata.labels = managed;
        spec = {
          certificateRotateStrategy = { };
          configuration = {
            developerConfiguration.featureGates = [ ];
            imagePullPolicy = "IfNotPresent";
            permittedHostDevices = {
              pciHostDevices = [
                {
                  pciVendorSelector = "10DE:2486";
                  resourceName = gpuResourceName;
                  externalResourceProvider = true;
                }
              ];
              # USB devices on the TV's hub (IOMMU group 15, chipset XHCI).
              # Non-isolated group — pass individual devices, not the controller.
              usb = [
                {
                  vendor = "1a2c";
                  product = "2124";
                  resourceName = "usb/kb-tv";
                }
                {
                  vendor = "1532";
                  product = "008f";
                  resourceName = "usb/mouse-tv";
                }
              ];
            };
          };
          customizeComponents = { };
          imagePullPolicy = "IfNotPresent";
          workloadUpdateStrategy = { };
        };
      };

      # ── VFIO GPU device-plugin DaemonSet ──────────────────────────────────
      #    Discovers the vfio-pci bound 3060 Ti on nexus and advertises it as the
      #    extended resource nvidia.com/ga104 so the scheduler can place the VM.
      kubevirt.DaemonSet.vfio-ga104-device-plugin = {
        metadata.labels = managed // { app = "vfio-ga104-device-plugin"; };
        spec = {
          selector.matchLabels.app = "vfio-ga104-device-plugin";
          template = {
            metadata.labels.app = "vfio-ga104-device-plugin";
            spec = {
              nodeSelector."kubernetes.io/hostname" = "nexus";
              containers = {
                _namedlist = true;
                device-plugin = {
                  image = "ghcr.io/nvidia/k8s-device-plugin:latest";
                  name = "device-plugin";
                  args = [ "--device=10de:2486" "--resource-name=nvidia.com/ga104" ];
                  securityContext.privileged = true;
                  volumeMounts = {
                    _namedlist = true;
                    "device-plugin" = { mountPath = "/var/lib/kubelet/device-plugins"; };
                    "vfio" = { mountPath = "/dev/vfio"; };
                  };
                  resources = {
                    limits.cpu = "100m";
                    limits.memory = "64Mi";
                    requests.cpu = "50m";
                    requests.memory = "32Mi";
                  };
                };
              };
              volumes = {
                _namedlist = true;
                "device-plugin" = {
                  hostPath.path = "/var/lib/kubelet/device-plugins";
                };
                "vfio" = { hostPath.path = "/dev/vfio"; };
              };
            };
          };
        };
      };

      # ── DataVolume + VirtualMachine ──────────────────────────────────────
      #    These live in kubernetes-manifests/kubevirt/nexus-de-vm.yaml and are
      #    imported via importyaml.nexus-de-vm above. They are CDI/KubeVirt
      #    custom kinds that easykubenix has no apiMapping for (DataVolume), so
      #    static YAML avoids the mapping error. The DV sources the guest image
      #    built by images/nexus-de-guest.nix (nix build .#nexusDeGuest) and
      #    pushed to nexus:5000; until then it stays Pending (declarative).
    };
  };
}
