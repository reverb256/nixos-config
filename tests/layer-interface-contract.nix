{pkgs, ...}: let
  inherit (pkgs) lib;
  contract = import ../contracts/layer-interface.nix;
  required = expected: actual:
    builtins.all (item: builtins.elem item actual) expected;
  hasInfix = needle: haystack: lib.strings.hasInfix needle haystack;
  sourceHasAll = source: needles:
    builtins.all (needle: hasInfix needle source) needles;
  flakeSource = builtins.readFile ../flake.nix;
  colmenaSource = builtins.readFile ../colmena.nix;
  servicePortsSource = builtins.readFile ../kubernetes/service-ports.nix;
  kubernetesSource = builtins.readFile ../kubernetes/default.nix;
  commonModulesSource = builtins.readFile ../common-modules-list.nix;
  interfaceVersions = lib.mapAttrsToList (_: interface: interface.version) contract.interfaces;
  interfaceChecks = lib.mapAttrsToList (_name: interface: let
    producer = contract.layers.${interface.producer};
    consumer = contract.layers.${interface.consumer};
    fieldsAreDeclared = builtins.all
      (field: builtins.hasAttr field contract.fieldSchemas)
      interface.fields;
    producerExportsFields = builtins.all
      (field: builtins.elem "${field}.v1" producer.exports)
      interface.fields;
    consumerConsumesFields = builtins.all
      (field: builtins.elem "${field}.v1" consumer.consumes)
      interface.fields;
  in
    fieldsAreDeclared && producerExportsFields && consumerConsumesFields)
    contract.interfaces;
  ownedResources = lib.concatLists (lib.mapAttrsToList (_: layer: layer.owns) contract.layers);

  checks = {
    schema_is_supported = contract.schemaVersion == 1;
    research_sources_are_present = required
      [
        "https://nixos.org/manual/nixos/stable/index.html#sec-option-types"
        "https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html#flake-outputs"
        "https://kubernetes.io/docs/concepts/overview/kubernetes-api/"
        "https://kubernetes.io/docs/tasks/manage-objects/declarative-config/"
        "https://fluxcd.io/flux/concepts/reconciliation/"
        "https://argo-cd.readthedocs.io/"
      ]
      contract.researchSources;
    canonical_sources_exist = builtins.all builtins.pathExists contract.canonicalSources;
    field_schemas_are_typed =
      contract.fieldSchemas.application-release.nixType == "types.submodule"
      && contract.fieldSchemas.workload-intent.nixType == "types.submodule"
      && contract.fieldSchemas.host-capabilities.nixType == "types.attrsOf(types.submodule)";
    field_schemas_have_required_fields = required
      ["name" "version" "image" "digest"]
      contract.fieldSchemas.application-release.required
      && required
        ["apiVersion" "resources" "releaseRef"]
        contract.fieldSchemas.workload-intent.required;
    layer_names_are_complete = required
      ["infrastructure" "platform" "applicationsDevelopment"]
      (builtins.attrNames contract.layers);
    infrastructure_exports_are_declared = required
      [
        "host-capabilities.v1"
        "deployment-targets.v1"
        "builder-capabilities.v1"
      ]
      contract.layers.infrastructure.exports;
    platform_consumes_infrastructure = required
      [
        "host-capabilities.v1"
        "deployment-targets.v1"
        "builder-capabilities.v1"
      ]
      contract.layers.platform.consumes;
    applications_consume_platform = required
      [
        "cluster-endpoint.v1"
        "registry.v1"
        "secret-interface.v1"
        "scheduling.v1"
      ]
      contract.layers.applicationsDevelopment.consumes;
    platform_consumes_application_outputs = required
      ["application-release.v1" "workload-intent.v1"]
      contract.layers.platform.consumes;
    every_interface_matches_field_graph = builtins.all (value: value) interfaceChecks;
    owned_resources_have_one_owner =
      builtins.length ownedResources == builtins.length (lib.unique ownedResources);
    release_interface_is_versioned =
      builtins.match "[0-9]+\\.[0-9]+" contract.interfaces.applicationsDevelopmentToPlatform.version != null
      && contract.interfaces.applicationsDevelopmentToPlatform.version == "1.0"
      && contract.interfaces.applicationsDevelopmentToPlatform.producer == "applicationsDevelopment"
      && contract.interfaces.applicationsDevelopmentToPlatform.consumer == "platform"
      && required
        ["application-release" "workload-intent"]
        contract.interfaces.applicationsDevelopmentToPlatform.fields;
    runtime_interface_has_existing_source =
      contract.interfaces.infrastructureToPlatform.sourceOfTruthKind
      == "canonical-repository"
      && contract.interfaces.infrastructureToPlatform.sourceOfTruth
      == "contracts/host-inventory.nix:hosts"
      && contract.interfaces.platformToApplicationsDevelopment.sourceOfTruthKind
      == "canonical-repository-set"
      && required
        [
          "kubernetes/service-ports.nix"
          "kubernetes/default.nix"
          "common-modules-list.nix"
        ]
        contract.interfaces.platformToApplicationsDevelopment.sourceOfTruth
      && contract.interfaces.platformToApplicationsDevelopment.producer == "platform"
      && contract.interfaces.platformToApplicationsDevelopment.consumer == "applicationsDevelopment"
      && hasInfix "inputs.caddy-ingress.nixosModules.caddy" commonModulesSource;
    external_release_source_is_explicit =
      contract.interfaces.applicationsDevelopmentToPlatform.sourceOfTruthKind
      == "external-project-flake"
      && hasInfix "standalone project flake"
        contract.interfaces.applicationsDevelopmentToPlatform.sourceOfTruth;
    every_interface_version_is_major_minor =
      builtins.all
        (version: builtins.match "[0-9]+\\.[0-9]+" version != null)
        interfaceVersions;
    source_dependency_direction_is_acyclic = required
      [
        "infrastructure -> platform"
        "applicationsDevelopment -> platform"
      ]
      contract.sourceDependencyDirection
      && required
        [
          "infrastructure exports host capabilities to platform"
          "platform exports runtime contracts to applicationsDevelopment"
          "applicationsDevelopment exports release intent to platform"
        ]
        contract.dataExchange;
    compatibility_is_fail_closed =
      contract.compatibility.versionFormat == "major.minor"
      && contract.compatibility.additiveChanges == "increase-minor-version"
      && contract.compatibility.breakingChanges == "increase-major-version-and-migrate-consumers"
      && contract.compatibility.unknownVersions == "fail-closed-before-deployment"
      && contract.compatibility.liveResourceOwnership == "exactly-one-layer";
    forbidden_rules_are_present = required
      [
        "duplicate-host-facts-in-platform-or-application-files"
        "untyped-cross-layer-parameter-bags"
        "developer-shell-mutates-live-cluster-state"
        "two-reconcilers-own-the-same-live-resource"
      ]
      contract.forbidden;
    host_inventory_source_is_canonical =
      builtins.pathExists ../contracts/host-inventory.nix
      && hasInfix "hostInventory = import ./contracts/host-inventory.nix" flakeSource
      && hasInfix "hosts = hostInventory.hosts" flakeSource;
    deployment_source_is_canonical =
      hasInfix "deployment =" colmenaSource
      && hasInfix "targetHost" colmenaSource;
    service_boundary_is_canonical =
      hasInfix "Service Port Registry" servicePortsSource
      && hasInfix "maplespike-api" servicePortsSource;
    workload_renderer_is_present =
      hasInfix "mkManifest" kubernetesSource
      && hasInfix "modules = commonModules ++ modules" kubernetesSource;
    source_boundaries_are_not_live_mutations =
      sourceHasAll flakeSource ["nixosConfigurations" "colmena" "checks"];
  };

  failures = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in {
  inherit checks failures;
  passed = failures == [ ];
}
