{ inputs, self }: [
  # krash3: headless KVM hypervisor (no desktop).
  # Module set mirrors what the other cluster hosts get via commonModules
  # auto-discovery (collect-modules), but explicitly curated so we DON'T
  # drag in the desktop compositor tree (which would require the niri
  # flake module and break the headless build with `programs.noctalia`).
  #
  # Every module below is something the other 4 hosts receive automatically
  # and that krash3 legitimately needs as a cluster node + hypervisor.
  # The desktop/* modules are intentionally omitted (hypervisor role).

  # ── SOPS (infra consistency; registry stays disabled — see below) ──
  inputs.sops-nix.nixosModules.default
  ./modules/system/sops-secrets-registry.nix

  # ── SSH (was previously OMITTED → openssh=false → no sshd on deploy) ──
  ./modules/system/ssh.nix
  ./modules/system/ssh-ca.nix

  # ── Cluster networking / DNS (was previously OMITTED) ──
  ./modules/network-constants.nix
  ./modules/network/cluster-networking.nix
  ./modules/network/cluster-hosts.nix
  ./modules/network/cluster-dns.nix

  # ── Inter-node mesh SSH (was previously OMITTED) ──
  ./modules/security/cluster-mesh.nix

  # ── Distributed builds (was previously OMITTED) ──
  ./modules/system/distributed-builds.nix

  # ── OOM protection for sshd (was previously OMITTED) ──
  ./modules/system/oom-protection.nix

  # ── Hardware: GPU passthrough to VM ──
  ./modules/hardware/nvidia-common.nix

  # ── K3s cluster agent + mining ──
  ./modules/services/k3s-cluster.nix
  ./modules/services/k3s-pod-affinity.nix
  ./modules/services/peakminer.nix

  # ── MCP registry + Hermes agent ──
  inputs.mcp-registry.nixosModules.default
  inputs.hermes-agent.nixosModules.default

  # ── Overlays ──
  {
    nixpkgs.overlays = [ self.overlays.default ];
  }
]
