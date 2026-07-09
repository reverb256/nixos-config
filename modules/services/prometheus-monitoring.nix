# Stub: prometheus-monitoring
#
# Intended purpose: standalone NixOS `services.prometheus` exporter stack
# (node + nvidia + amd exporters via systemd, not K8s) for hosts without a
# K3s worker role. The cluster currently uses the K8s-native monitoring stack
# in kubernetes-manifests/monitoring/, so this NixOS path is dead. Drop it
# next refactor pass or actually wire it for the Workstation profile.
{ ... }: { }
