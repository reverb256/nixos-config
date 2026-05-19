{pkgs, ...}: {
  # Ensure nixos-cluster-mcp is built on every node during NixOS rebuild.
  # The K8s DaemonSet mounts /nix via hostPath and runs the binary directly
  # from the Nix store. Without this, the store path only exists on the node
  # that evaluated the flake (Zephyr), and pods on remote nodes fail with
  # "executable not found" until manual nix copy is performed.
  environment.systemPackages = [
    (pkgs.callPackage ../packages/nixos-cluster-mcp {})
  ];
}
