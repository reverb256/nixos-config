{
  schemaVersion = 1;

  # This is intentionally an evidence record, not a role declaration or a
  # NixOS module. It must not authorize a K3s restart, datastore migration, or
  # secret rotation. The validator proves that the blocked state is explicit.
  decision = "blocked";
  operationalizationAllowed = false;

  researchSources = [
    "https://docs.k3s.io/architecture#high-availability"
    "https://docs.k3s.io/installation/ha"
    "https://docs.k3s.io/installation/datastore#embedded-etcd-server-arguments"
    "https://docs.k3s.io/storage/etcd#restoring-backups-on-a-new-cluster"
    "https://docs.k3s.io/installation/private-registry"
    "https://docs.k3s.io/installation/requirements#networking"
  ];

  # Candidate only: this is the four-host shape being evaluated, not an
  # instruction to apply it. Zephyr is currently declared disabled, so the
  # candidate deliberately exposes that conflict instead of hiding it.
  candidate = {
    serverHosts = [ "nexus" "forge" "sentry" ];
    agentHosts = [ "zephyr" ];
    fixedRegistrationEndpoint = "https://10.1.1.100:6443";
    apiVip = "10.1.1.100";
    serverCount = 3;
    oddServerQuorum = true;
  };

  # Repository observations captured on 2026-08-01. These are evidence to be
  # reconciled; they are not a second source of truth for host configuration.
  observedNix = {
    nexus = {
      enabled = true;
      role = "server";
      clusterInit = true;
      serverAddr = "";
      nodeIP = "10.1.1.120";
      nodeName = "nexus";
      source = "hosts/nexus/configuration.nix";
    };
    forge = {
      enabled = true;
      role = "server";
      clusterInit = false;
      serverAddr = "https://10.1.1.120:6443";
      nodeIP = "10.1.1.130";
      nodeName = "forge";
      source = "hosts/forge/configuration.nix";
    };
    sentry = {
      enabled = true;
      role = "server";
      clusterInit = false;
      serverAddr = "https://10.1.1.120:6443";
      nodeIP = "10.1.1.140";
      nodeName = "sentry";
      source = "hosts/sentry/configuration.nix";
    };
    zephyr = {
      enabled = false;
      role = "disabled";
      clusterInit = false;
      serverAddr = "";
      nodeIP = "10.1.1.110";
      nodeName = "zephyr";
      source = "hosts/zephyr/configuration.nix";
    };
  };

  observedMetadata = {
    nexus = { enabled = true; role = "server"; nodeName = "nexus"; source = "hosts/metadata/nexus.json"; };
    forge = { enabled = true; role = "server"; nodeName = "forge"; source = "hosts/metadata/forge.json"; };
    sentry = { enabled = true; role = "agent"; nodeName = "sentry"; source = "hosts/metadata/sentry.json"; };
    zephyr = { enabled = false; role = "disabled"; nodeName = "zephyr"; source = "hosts/metadata/zephyr.json"; };
  };

  evidence = {
    # The module emits registries.yaml whenever k3s-cluster is enabled. This
    # still requires checking every actual image-pulling node at runtime.
    registry = {
      status = "declared";
      source = "modules/services/k3s-cluster.nix";
      path = "/etc/rancher/k3s/registries.yaml";
      requiredOn = "every-image-pulling-node";
    };

    encryption = {
      status = "declared-for-enabled-servers";
      source = "modules/services/k3s-cluster.nix";
      keyPath = "/run/secrets/k3s-encryption-key";
      requiredOn = "every-server-with-embedded-etcd";
    };

    snapshots = {
      status = "missing-proof";
      required = [
        "scheduled embedded-etcd snapshots"
        "off-node replication"
        "retention and pruning policy"
        "restore rehearsal"
      ];
    };

    tokenCustody = {
      status = "missing-proof";
      required = [
        "original server token escrow"
        "restricted access control"
        "restore procedure pairing token with snapshot"
      ];
    };

    readiness = {
      status = "missing-proof";
      required = [
        "all declared hosts reachable"
        "server critical-flag parity"
        "fixed endpoint and TLS SAN verification"
        "etcd member and quorum health"
        "registry pull verification"
        "documented rollback path"
      ];
    };
  };

  blockers = [
    "candidate-agent-is-currently-disabled"
    "observed-join-endpoint-is-not-candidate-vip"
    "metadata-join-endpoint-drift"
    "snapshot-replication-proof-missing"
    "server-token-custody-proof-missing"
    "runtime-readiness-proof-missing"
  ];
}
