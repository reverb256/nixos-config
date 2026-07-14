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
          validationActions = [ "Warn" ];
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
                  externalResourceProvider = false;
                }
              ];
              # USB devices on the TV's hub (IOMMU group 15, chipset XHCI).
              # Non-isolated group — pass individual devices, not the controller.
              usb = [
                {
                  resourceName = "usb/kb-tv";
                  selectors = [
                    { vendor = "1a2c"; product = "2124"; }
                  ];
                }
                {
                  resourceName = "usb/mouse-tv";
                  selectors = [
                    { vendor = "1532"; product = "008f"; }
                  ];
                }
              ];
            };
          };
          customizeComponents = { };
          imagePullPolicy = "IfNotPresent";
          workloadUpdateStrategy = { };
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
