{
  schemaVersion = 1;
  status = "contract-first";

  researchSources = [
    "https://nixos.org/manual/nixos/stable/index.html#sec-option-types"
    "https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html#flake-outputs"
    "https://kubernetes.io/docs/concepts/overview/kubernetes-api/"
    "https://kubernetes.io/docs/tasks/manage-objects/declarative-config/"
    "https://fluxcd.io/flux/concepts/reconciliation/"
    "https://argo-cd.readthedocs.io/"
  ];

  # Existing canonical sources described by this contract. The contract does
  # not replace or duplicate their runtime configuration.
  canonicalSources = [
    ../flake.nix
    ../colmena.nix
    ../kubernetes/service-ports.nix
    ../kubernetes/default.nix
    ../common-modules-list.nix
  ];

  # Transitional field vocabulary. `nixType` names the Nix option/type shape
  # expected at the boundary; concrete values must be supplied by the
  # producing layer. This file is not itself executable option validation: the
  # consuming NixOS/Kubernetes module remains the runtime type authority.
  # Future migration work should attach these schemas to typed consumer
  # options before any application workload is moved across the boundary.
  fieldSchemas = {
    host-capabilities = {
      nixType = "types.attrsOf(types.submodule)";
      required = ["system" "memoryMiB" "capabilities"];
    };
    deployment-targets = {
      nixType = "types.attrsOf(types.submodule)";
      required = ["targetHost" "targetUser" "buildOnTarget"];
    };
    builder-capabilities = {
      nixType = "types.attrsOf(types.submodule)";
      required = ["system" "maxJobs" "supportedFeatures"];
    };
    cluster-endpoint = {
      nixType = "types.submodule";
      required = ["apiServer" "apiPort"];
    };
    registry = {
      nixType = "types.submodule";
      required = ["host" "repositoryPrefix" "pullPolicy"];
    };
    storage = {
      nixType = "types.submodule";
      required = ["classes" "accessModes"];
    };
    secret-interface = {
      nixType = "types.submodule";
      required = ["provider" "referenceFormat"];
    };
    scheduling = {
      nixType = "types.submodule";
      required = ["defaultNode" "allowedSelectors"];
    };
    workload-contract = {
      nixType = "types.submodule";
      required = ["apiVersion" "resourceKinds" "ownership" "reconciliation"];
    };
    application-release = {
      nixType = "types.submodule";
      required = ["name" "version" "image" "digest"];
    };
    workload-intent = {
      nixType = "types.submodule";
      required = ["apiVersion" "resources" "releaseRef"];
    };
  };

  layers = {
    infrastructure = {
      owns = [
        "host-inventory"
        "hardware-and-disk-facts"
        "base-networking"
        "ssh-and-recovery"
        "builders"
        "nixos-delivery"
      ];
      exports = [
        "host-capabilities.v1"
        "deployment-targets.v1"
        "builder-capabilities.v1"
      ];
      consumes = [ ];
    };

    platform = {
      owns = [
        "k3s-lifecycle"
        "kubernetes-api-and-datastore"
        "ingress"
        "registry-and-image-distribution"
        "cluster-storage"
        "runtime-secret-delivery"
        "observability"
        "workload-scheduling"
      ];
      exports = [
        "cluster-endpoint.v1"
        "registry.v1"
        "storage.v1"
        "secret-interface.v1"
        "scheduling.v1"
        "workload-contract.v1"
      ];
      consumes = [
        "host-capabilities.v1"
        "deployment-targets.v1"
        "builder-capabilities.v1"
        "application-release.v1"
        "workload-intent.v1"
      ];
    };

    applicationsDevelopment = {
      owns = [
        "application-source"
        "project-flakes"
        "devShells"
        "project-packages-and-checks"
        "container-image-derivations"
        "release-metadata"
        "issue-worktrees"
      ];
      exports = [
        "application-release.v1"
        "workload-intent.v1"
      ];
      consumes = [
        "cluster-endpoint.v1"
        "registry.v1"
        "storage.v1"
        "secret-interface.v1"
        "scheduling.v1"
        "workload-contract.v1"
      ];
    };
  };

  interfaces = {
    infrastructureToPlatform = {
      version = "1.0";
      producer = "infrastructure";
      consumer = "platform";
      fields = [
        "host-capabilities"
        "deployment-targets"
        "builder-capabilities"
      ];
      sourceOfTruthKind = "canonical-repository";
      sourceOfTruth = "flake.nix:hosts";
    };

    platformToApplicationsDevelopment = {
      version = "1.0";
      producer = "platform";
      consumer = "applicationsDevelopment";
      fields = [
        "cluster-endpoint"
        "registry"
        "storage"
        "secret-interface"
        "scheduling"
        "workload-contract"
      ];
      sourceOfTruthKind = "canonical-repository-set";
      sourceOfTruth = [
        "kubernetes/service-ports.nix"
        "kubernetes/default.nix"
        "common-modules-list.nix"
      ];
    };

    applicationsDevelopmentToPlatform = {
      version = "1.0";
      producer = "applicationsDevelopment";
      consumer = "platform";
      fields = [
        "application-release"
        "workload-intent"
      ];
      sourceOfTruthKind = "external-project-flake";
      sourceOfTruth = "standalone project flake outputs and versioned release references";
    };
  };

  # Source dependencies are acyclic. Data exchange is intentionally
  # bidirectional through versioned interfaces, not through module imports.
  sourceDependencyDirection = [
    "infrastructure -> platform"
    "applicationsDevelopment -> platform"
  ];

  dataExchange = [
    "infrastructure exports host capabilities to platform"
    "platform exports runtime contracts to applicationsDevelopment"
    "applicationsDevelopment exports release intent to platform"
  ];

  compatibility = {
    versionFormat = "major.minor";
    additiveChanges = "increase-minor-version";
    breakingChanges = "increase-major-version-and-migrate-consumers";
    unknownVersions = "fail-closed-before-deployment";
    liveResourceOwnership = "exactly-one-layer";
  };

  forbidden = [
    "platform-imports-application-source"
    "applications-development-imports-host-configuration"
    "duplicate-host-facts-in-platform-or-application-files"
    "untyped-cross-layer-parameter-bags"
    "developer-shell-mutates-live-cluster-state"
    "two-reconcilers-own-the-same-live-resource"
  ];
}
