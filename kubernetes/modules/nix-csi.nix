# nix-csi module placeholder
# The nix-csi module import causes issues with inputs/eval context
# We disable it for now - CSI volumes use hostPath/nix mounts directly
{
  config,
  lib,
  pkgs,
  ...
}: {
  # The nix-csi import requires specialArgs.inputs which isn't available
  # properly in this context. For now, we skip the CSI import.
  # CSI functionality is provided via hostPath volumes in deployment specs
  # instead of CSI driver
}
