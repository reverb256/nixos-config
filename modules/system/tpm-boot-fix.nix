{
  config,
  lib,
  pkgs,
  ...
}: {
  # Cluster-wide TPM and serial port boot speed fix.
  # Blacklists unused kernel modules that cause ~10-12s device timeout during boot.
  # TPM 2.0 not used on any cluster node (no measured boot, no disk encryption via TPM).
  # Physical serial ports not present on any node.
  #
  # If a node genuinely needs TPM, override with:
  #   boot.blacklistedKernelModules = lib.mkForce [];
  #
  # If DefaultDeviceTimeoutSec is available, also set it to 5s as backup fallback.
  # This covers any remaining device timeouts from other kernel modules.

  boot.blacklistedKernelModules = [
    "serial8250"     # No physical serial ports — saves ~10s timeout
    "tpm_crb"        # TPM 2.0 not used — saves ~10s timeout
    "tpm_tis"
    "tpm_tis_core"
  ];

  # systemd.extraConfig is a string option. If the NixOS version supports
  # DefaultDeviceTimeoutSec, uncomment the line below:
  # systemd.extraConfig = ''
  #   DefaultDeviceTimeoutSec=5s
  # '';
}
