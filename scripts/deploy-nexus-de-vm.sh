#!/usr/bin/env bash
# Deploy the KubeVirt "nexus-de" VM (DE on the 4K TV) with MINIMAL DOWNTIME.
#
# Downtime model (mining on GPU0 pauses only during the nexus switch + VM boot):
#   1. colmena apply --on nexus  -> nexus reboots WITH vfio-pci bind on the 3060 Ti.
#                                 Host mining on GPU0 STOPS here (GPU now owned by VM).
#   2. kubevirt manifest applied  -> operator + CDI + KubeVirt CR + VM created.
#   3. virtctl image-upload       -> creates+populates the nexus-de-root DataVolume from
#                                 the qcow2 that is ALREADY on nexus's /nix/store (built
#                                 there via remote builder) -> NO 6GB LAN transfer.
#   4. VM auto-starts (runStrategy: Always) -> niri on the TV + peakminer mining resumes
#                                 INSIDE the guest.
#
# TOTAL mining pause ≈ nexus reboot (~30-60s) + kubevirt/CDI ready (~60-90s) +
#                     local DV populate (~30-60s) + guest boot (~30s)  ≈ 3-4 min.
#
# PREREQS (already satisfied by preparation):
#   - nix build .#nexusDeGuest succeeded (qcow2 in nexus /nix/store).
#   - nix build .#kubernetes.kubevirt.manifestYAMLFile succeeded.
#   - nexus toplevel builds (gradio/starlette overlay fix applied).
#
# THIS SCRIPT IS DISRUPTIVE (reboots nexus). Run only on explicit approval.
set -euo pipefail

FLAKE="${FLAKE:-/etc/nixos}"
GUEST_STORE="/nix/store/zxfkbk0cwzngl542gr9nx5sdg8lfa3xs-nixos-disk-image/nixos.qcow2"
VIRTCTL_VER="v1.8.4"

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { log "ERROR: $*"; exit 1; }

# ── Phase 1: switch nexus (VFIO bind takes effect on reboot) ────────────────
log "=== Phase 1/5: colmena apply --on nexus (REBOOTS nexus, GPU rebinds) ==="
cd "$FLAKE"
nix run .#apps.x86_64-linux.colmena -- apply --on nexus --verbose

# ── Phase 2: apply kubevirt manifest (operator, CDI, CR, VM) ────────────────
log "=== Phase 2/5: deploy kubevirt manifest ==="
# Build + apply the dedicated kubevirt manifest via the standard pipeline.
# deploy.sh applies self.kubernetes.<host>.manifestYAMLFile; nexus's is now
# the kubevirt manifest. Use it directly to avoid re-applying everything.
nix build .#kubernetes.kubevirt.manifestYAMLFile --no-link -o /tmp/kubevirt-manifest 2>/dev/null \
  || nix build "$FLAKE#kubernetes.kubevirt.manifestYAMLFile" --no-link -o /tmp/kubevirt-manifest
kubectl apply -f /tmp/kubevirt-manifest/ --recursive

# ── Phase 3: wait for kubevirt + CDI to be Ready ───────────────────────────
log "=== Phase 3/5: waiting for KubeVirt + CDI Ready ==="
kubectl -n kubevirt wait --for=condition=Available --timeout=300s kubevirt kubevirt
kubectl -n cdi wait --for=condition=Available --timeout=300s cdi cdi
# CDI upload proxy must be up for virtctl image-upload.
kubectl -n cdi rollout status deploy cdi-uploadproxy --timeout=300s

# ── Phase 4: populate the DataVolume from the LOCAL qcow2 on nexus ──────────
# Run virtctl ON nexus so it reads the qcow2 from nexus's own /nix/store
# (no network transfer). Pass nexus's kubeconfig.
log "=== Phase 4/5: virtctl image-upload (local qcow2 -> CDI) ==="
scp "/tmp/virtctl" "nexus:/usr/local/bin/virtctl" 2>/dev/null || \
  curl -skL "https://github.com/kubevirt/kubevirt/releases/download/${VIRTCTL_VER}/virtctl-${VIRTCTL_VER}-linux-amd64" \
    | ssh nexus "tee /usr/local/bin/virtctl && chmod +x /usr/local/bin/virtctl"
ssh nexus "bash -s" <<EOF
set -euo pipefail
if [ ! -f "$GUEST_STORE" ]; then
  echo "GUEST qcow2 not found at $GUEST_STORE on nexus; rebuilding..."
  nix build /etc/nixos#nexusDeGuest --no-link -o /tmp/nexus-de-guest 2>/dev/null || \
    nix build /etc/nixos#nexusDeGuest --no-link -o /tmp/nexus-de-guest
  GUEST_STORE=\$(readlink -f /tmp/nexus-de-guest/nixos.qcow2)
fi
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
virtctl image-upload dv nexus-de-root -n nexus-de --size=60Gi --image-path "$GUEST_STORE" --wait-secs=600
EOF

# ── Phase 5: wait for the VM to be Running + mining resumed ─────────────────
log "=== Phase 5/5: waiting for VM Running ==="
kubectl -n nexus-de wait --for=condition=Ready --timeout=300s virtualmachine nexus-de
log "VM nexus-de is running. niri should be on the TV; peakminer mining GPU0 inside guest."
log "Verify: kubectl -n nexus-de get vmi; ssh nexus 'nvidia-smi' (should show VM's process)."
