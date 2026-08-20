{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;
  contract = import ../contracts/k3s-topology-evidence.nix;

  hostNames = builtins.attrNames contract.observedNix;
  metadataHostNames = builtins.attrNames contract.observedMetadata;
  candidateHosts = contract.candidate.serverHosts ++ contract.candidate.agentHosts;

  roleDrift = builtins.filter (
    host:
      contract.observedNix.${host}.enabled
      != contract.observedMetadata.${host}.enabled
      || contract.observedNix.${host}.role
      != contract.observedMetadata.${host}.role
  ) hostNames;

  sourcePaths = [
    ../contracts/k3s-topology-evidence.nix
    ../modules/services/k3s-cluster.nix
    ../hosts/nexus/configuration.nix
    ../hosts/forge/configuration.nix
    ../hosts/sentry/configuration.nix
    ../hosts/zephyr/configuration.nix
    ../hosts/metadata/nexus.json
    ../hosts/metadata/forge.json
    ../hosts/metadata/sentry.json
    ../hosts/metadata/zephyr.json
  ];

  sourcePathsExist = builtins.all builtins.pathExists sourcePaths;

  metadata = builtins.mapAttrs (
    _host: path: builtins.fromJSON (builtins.readFile path)
  ) {
    nexus = ../hosts/metadata/nexus.json;
    forge = ../hosts/metadata/forge.json;
    sentry = ../hosts/metadata/sentry.json;
    zephyr = ../hosts/metadata/zephyr.json;
  };

  nixSources = {
    nexus = builtins.readFile ../hosts/nexus/configuration.nix;
    forge = builtins.readFile ../hosts/forge/configuration.nix;
    sentry = builtins.readFile ../hosts/sentry/configuration.nix;
    zephyr = builtins.readFile ../hosts/zephyr/configuration.nix;
  };

  observedNixMatchesSources = {
    nexus =
      contract.observedNix.nexus.enabled
      && contract.observedNix.nexus.role == "server"
      && contract.observedNix.nexus.clusterInit
      && contract.observedNix.nexus.serverAddr == ""
      && contract.observedNix.nexus.nodeIP == "10.1.1.120"
      && lib.strings.hasInfix "services = {" nixSources.nexus
      && lib.strings.hasInfix "k3s-cluster = {" nixSources.nexus
      && lib.strings.hasInfix "enable = true;" nixSources.nexus
      && lib.strings.hasInfix "clusterInit = true;" nixSources.nexus
      && lib.strings.hasInfix "role = \"server\";" nixSources.nexus
      && lib.strings.hasInfix "serverAddr = \"\";" nixSources.nexus
      && lib.strings.hasInfix "nodeIP = \"10.1.1.120\";" nixSources.nexus
      && lib.strings.hasInfix "nodeName = \"nexus\";" nixSources.nexus;
    forge =
      contract.observedNix.forge.enabled
      &&      contract.observedNix.forge.role == "server"
      && !contract.observedNix.forge.clusterInit
      && contract.observedNix.forge.serverAddr == "https://10.1.1.120:6443"
      && contract.observedNix.forge.nodeIP == "10.1.1.130"
      && lib.strings.hasInfix "k3s-cluster = {" nixSources.forge
      && lib.strings.hasInfix "enable = true;" nixSources.forge
      && lib.strings.hasInfix "role = \"server\";" nixSources.forge
      && lib.strings.hasInfix "serverAddr = \"https://10.1.1.120:6443\";" nixSources.forge
      && lib.strings.hasInfix "nodeIP = \"10.1.1.130\";" nixSources.forge
      && lib.strings.hasInfix "nodeName = \"forge\";" nixSources.forge;
    sentry =
      contract.observedNix.sentry.enabled
      && contract.observedNix.sentry.role == "server"
      && !contract.observedNix.sentry.clusterInit
      &&      contract.observedNix.sentry.serverAddr == "https://10.1.1.120:6443"
      && contract.observedNix.sentry.nodeIP == "10.1.1.140"
      && lib.strings.hasInfix "k3s-cluster = {" nixSources.sentry
      && lib.strings.hasInfix "enable = true;" nixSources.sentry
      && lib.strings.hasInfix "role = \"server\";" nixSources.sentry
      && lib.strings.hasInfix "serverAddr = \"https://10.1.1.120:6443\";" nixSources.sentry
      && lib.strings.hasInfix "nodeIP = \"10.1.1.140\";" nixSources.sentry;
    zephyr =
      contract.observedNix.zephyr.enabled
      && contract.observedNix.zephyr.role == "agent"
      && !contract.observedNix.zephyr.clusterInit
      && contract.observedNix.zephyr.serverAddr == "https://10.1.1.100:6443"
      && contract.observedNix.zephyr.nodeIP == "10.1.1.110"
      && contract.observedNix.zephyr.nodeName == "zephyr"
      && lib.strings.hasInfix "../../modules/services/k3s-cluster.nix" nixSources.zephyr
      && lib.strings.hasInfix "k3s-cluster = {" nixSources.zephyr
      && lib.strings.hasInfix "role = \"agent\";" nixSources.zephyr
      && lib.strings.hasInfix "serverAddr = \"https://10.1.1.100:6443\";" nixSources.zephyr
      && lib.strings.hasInfix "nodeIP = \"10.1.1.110\";" nixSources.zephyr;
  };

  metadataMatchesContract =
    metadata.nexus.k3s.enable == contract.observedMetadata.nexus.enabled
    && metadata.nexus.k3s.role == contract.observedMetadata.nexus.role
    && metadata.nexus.k3s.nodeName == contract.observedMetadata.nexus.nodeName
    && metadata.forge.k3s.enable == contract.observedMetadata.forge.enabled
    && metadata.forge.k3s.role == contract.observedMetadata.forge.role
    && metadata.forge.k3s.nodeName == contract.observedMetadata.forge.nodeName
    && metadata.sentry.k3s.enable == contract.observedMetadata.sentry.enabled
    && metadata.sentry.k3s.role == contract.observedMetadata.sentry.role
    && metadata.sentry.k3s.nodeName == contract.observedMetadata.sentry.nodeName
    && metadata.zephyr.k3s.enable == contract.observedMetadata.zephyr.enabled
    && metadata.zephyr.k3s.role == contract.observedMetadata.zephyr.role
    && metadata.zephyr.k3s.nodeName == contract.observedMetadata.zephyr.nodeName;

  metadataEndpointDrift = builtins.filter (
    host:
      metadata.${host}.k3s.serverAddr != contract.observedNix.${host}.serverAddr
      || metadata.${host}.k3s.nodeIP != contract.observedNix.${host}.nodeIP
  ) hostNames;

  requiredBlockers = [
    "snapshot-replication-proof-missing"
    "server-token-custody-proof-missing"
    "runtime-readiness-proof-missing"
  ];

  blockersAreComplete = builtins.all (
    blocker: builtins.elem blocker contract.blockers
  ) requiredBlockers;

  checks = {
    schema_is_supported = contract.schemaVersion == 1;
    decision_is_allowed_agent = contract.decision == "allowed-agent";
    operationalization_is_allowed = contract.operationalizationAllowed == true;
    research_sources_are_present = builtins.length contract.researchSources >= 6;

    host_sets_are_complete =
      lib.sort builtins.lessThan hostNames
      == lib.sort builtins.lessThan metadataHostNames
      && lib.sort builtins.lessThan hostNames
      == lib.sort builtins.lessThan candidateHosts;

    candidate_has_odd_ha_server_count =
      contract.candidate.serverCount >= 3
      && lib.mod contract.candidate.serverCount 2 == 1
      && contract.candidate.oddServerQuorum;

    candidate_roles_are_disjoint =
      lib.intersectLists contract.candidate.serverHosts contract.candidate.agentHosts == [];

    fixed_endpoint_is_explicit =
      contract.candidate.fixedRegistrationEndpoint == "https://10.1.1.100:6443"
      && contract.candidate.apiVip == "10.1.1.100";

    observed_sources_are_present = sourcePathsExist;
    observed_nix_matches_sources = builtins.all (value: value) (builtins.attrValues observedNixMatchesSources);
    metadata_matches_contract = metadataMatchesContract;
    metadata_endpoint_drift_is_explicit =
      lib.sort builtins.lessThan metadataEndpointDrift == [ "forge" "sentry" ];

    registry_evidence_is_declared_but_not_runtime_proof =
      contract.evidence.registry.status == "declared"
      && contract.evidence.registry.requiredOn == "every-image-pulling-node";

    encryption_evidence_is_declared_but_not_runtime_proof =
      contract.evidence.encryption.status == "declared-for-enabled-servers"
      && contract.evidence.encryption.requiredOn == "every-server-with-embedded-etcd";

    snapshot_evidence_fails_closed =
      contract.evidence.snapshots.status == "missing-proof"
      && builtins.length contract.evidence.snapshots.required >= 4;

    token_custody_evidence_fails_closed =
      contract.evidence.tokenCustody.status == "missing-proof"
      && builtins.length contract.evidence.tokenCustody.required >= 3;

    readiness_evidence_fails_closed =
      contract.evidence.readiness.status == "missing-proof"
      && builtins.length contract.evidence.readiness.required >= 6;

    blockers_are_complete = blockersAreComplete;
  };

  failures = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in {
  inherit checks failures;
  diagnostics = {
    inherit hostNames metadataHostNames candidateHosts roleDrift metadataEndpointDrift;
    sourceMatchingMode = "heuristic-source-text; evaluated NixOS option merge remains required";
    blockerCount = builtins.length contract.blockers;
    decision = contract.decision;
  };
  passed = failures == [];
}
