{
  pkgs,
  ...
}: {
  # 2026-08-02: NixOS-side `services.ai-inference` config REMOVED — the gateway
  # runs in Kubernetes (kubernetes/modules/ai-inference.nix) from a prebuilt
  # image. The old NixOS module pulled the torch/sentence-transformers stack
  # into every host closure (ROCm source builds; blocked the sentry deploy).
  #
  # OpenCode/pi/crush/hermes reach the gateway via the K8s NodePort
  # (config.networking.cluster.kubernetes.nodePorts.ai-inference-gateway).

  # Push gateway image to local container registry after k3s loads it.
  # Needed for HA: sentry gateway pod pulls from nexus:5000 instead of needing pre-loaded image.
  systemd.services.push-gateway-to-registry = {
    description = "Push gateway image to local container registry";
    after = ["k3s.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.bash pkgs.podman pkgs.curl pkgs.coreutils];
    serviceConfig.ExecStart = pkgs.writeShellScript "push-gateway-to-registry-start" ''
      set -euo pipefail

      gwImage="nexus:5000/ai-inference-gateway:2.4.9"
      srcImage="docker.io/library/ai-inference-gateway:2.4.9"
      registry="http://127.0.0.1:5000/v2"
      tmpfile="/tmp/gw-push.tar"

      # Wait for local registry to be ready (with timeout in script)
      elapsed=0
      until curl -sf "$registry/" > /dev/null 2>&1; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $elapsed -ge 300 ]; then
          echo "Registry not ready after 300s, skipping push"
          exit 0
        fi
      done

      # Check if image already exists in registry
      if curl -sf "$registry/$gwImage/manifests/latest" > /dev/null 2>&1; then
        echo "Gateway image already exists in registry, skipping push"
        exit 0
      fi

      # Export from containerd, load into podman, tag and push
      if ! sudo ctr -n k8s.io images export "$tmpfile" "$srcImage" 2>/dev/null; then
        echo "Gateway image not found in containerd, skipping push"
        exit 0
      fi

      sudo podman load -i "$tmpfile"
      sudo podman tag "$srcImage" "$gwImage"
      if sudo podman push --tls-verify=false "$gwImage"; then
        echo "Gateway image pushed to local registry"
      else
        echo "Podman push failed (registry or network issue)"
      fi

      sudo rm -f "$tmpfile"
    '';
  };
}
