# lib/build-machines.nix — Single source of truth for the cluster's remote
# builder topology.
#
# Both consumers read this:
#   1. modules/system/distributed-builds.nix — generates /etc/nix/machines
#      (the nix-level `builders` file used by nix build / nixos-rebuild).
#   2. colmena.nix — generates meta.machinesFile (the builders colmena passes
#      to nix via `--builders @<file>` when building the hive on nexus).
#
# This eliminates the drift that left colmena's machines file empty while
# /etc/nix/machines carried the real builder topology (2026-08-20).
#
# Machine spec format (nix src/libstore/machines.cc):
#   URL systemTypes sshKey maxJobs speedFactor supportedFeatures
#       mandatoryFeatures sshPublicHostKey
# Column 7 is the base64-encoded public host key. Each entry must be a valid
# SSH public key line base64'd (base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub).
{
  lib,
  userHome ? "/home/j_kro",
}: let
  # Host keys are pinned per-builder so nix doesn't rely on
  # StrictHostKeyChecking=accept-new in the ssh config (nix.dev best practice:
  # "Set the nix.buildMachines.*.publicHostKey field to each remote builder's
  # public host key to secure build distribution against man-in-the-middle").
  hostKeys = {
    zephyr = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUEwL3BUWGEvSDdtdnkzK1lQSnE5VTJtRktPNCtZckxTT1lkOHNQVTQ0K3Egcm9vdEB6ZXBoeXIK";
    nexus = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU50dHZHbjRldFFYNkFieVQySHBYcm15R2FURkwzZ3VyLzJJbUhUTHpCT2wgcm9vdEBuZXh1cwo=";
    sentry = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU1wdmhXZkhxM0tWa3doZGxXOEdva1RMdzVQMFFtVUVaTUdhdWFqOG1hSlUgcm9vdEBzZW50cnkK";
  };

  # The full builder topology. nexus + zephyr tied at speedFactor 10 (highest
  # priority — builders first); sentry at 9 (lower — k3s/inference host stays
  # responsive under load). forge is deliberately NOT a builder:
  # its CPU is a GPU miner (2x 4060, 95C under load) — builds heat it up and
  # mining is revenue-critical. forge consumes remote builders but never
  # hosts them (matching its max-jobs=0 / cores=0 in distributed-builds.nix).
  allMachines = [
    {
      hostName = "zephyr";
      systems = ["x86_64-linux"];
      sshUser = "j_kro";
      sshKey = userHome + "/.ssh/id_ed25519";
      maxJobs = 3;
      speedFactor = 10;
      supportedFeatures = ["big-parallel" "kvm"];
      mandatoryFeatures = [];
      publicHostKey = hostKeys.zephyr;
    }
    {
      hostName = "nexus";
      # Nexus is the exclusive builder and also serves Steam/VR multilib
      # closures (e.g. volk.i686-linux). An x86_64 kernel can build the i686
      # target, so advertise both systems explicitly.
      systems = ["x86_64-linux" "i686-linux"];
      sshUser = "j_kro";
      sshKey = userHome + "/.ssh/id_ed25519";
      maxJobs = 5;
      speedFactor = 10;
      supportedFeatures = ["big-parallel" "kvm"];
      mandatoryFeatures = [];
      publicHostKey = hostKeys.nexus;
    }
    {
      hostName = "sentry";
      systems = ["x86_64-linux"];
      sshUser = "j_kro";
      sshKey = userHome + "/.ssh/id_ed25519";
      maxJobs = 2;
      speedFactor = 9;
      supportedFeatures = ["big-parallel" "kvm"];
      mandatoryFeatures = [];
      publicHostKey = hostKeys.sentry;
    }
  ];

  formatMachine = m:
    with builtins; let
      allSystems = lib.concatStringsSep "," m.systems;
      optFeatures = lib.concatStringsSep "," m.supportedFeatures;
      mandFeatures =
        if m.mandatoryFeatures == []
        then "-"
        else lib.concatStringsSep "," m.mandatoryFeatures;
    in
      lib.concatStringsSep " " [
        ("${m.protocol or "ssh-ng"}://" + "${m.sshUser}@${m.hostName}")
        allSystems
        m.sshKey
        (toString m.maxJobs)
        (toString m.speedFactor)
        optFeatures
        mandFeatures
        m.publicHostKey
      ];

  # Build the machines text for a given host: all OTHER hosts (never self —
  # a self-entry makes nix-daemon dispatch derivations back to itself over
  # SSH and deadlock on store locks; observed 2026-08-08).
  # `exclude` removes specific hosts (e.g. a builder that isn't ready to
  # accept remote builds yet — zephyr had max-jobs=0 until its deploy lands).
  machinesTextFor = currentHost: exclude: let
    notSelf = m: m.hostName != currentHost;
    notExcluded = m: !builtins.elem m.hostName exclude;
  in
    lib.concatStringsSep "\n" (
      map formatMachine (builtins.filter (m: notSelf m && notExcluded m) allMachines)
    ) + "\n";
in {
  inherit allMachines formatMachine machinesTextFor;
}
