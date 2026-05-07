{pkgs, ...}: {
  config.kubernetes.objects = {
    none = {
      Namespace.ai-inference = {
        metadata.labels = {
          name = "ai-inference";
        };
      };
      Namespace.nixkube = {
        metadata.labels = {
          name = "nixkube";
        };
      };
    };

    nixkube.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };
  };

  config.importyaml.nixkube = {
    src = pkgs.runCommand "nixkube.yaml" {} ''
      cp ${../../kubernetes-manifests/nixkube/nixkube-clean.yaml} $out
    '';
  };

  config.kubernetes.objects.nixkube = {
    # ── Default deny all ────────────────────────────────────────
    nixkube.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };
  };
}
