# UKI (Unified Kernel Image) boot support for NixOS 26.11pre
#
# The boot.uki module (shipped with nixpkgs 0954f7ee) builds a UKI at
# system.build.uki containing kernel + initrd + cmdline + os-release in a
# single PE32+ EFI binary. systemd-stub boots the UKI via the EFI stub.
#
# Our nixpkgs version predates boot.loader.systemd-boot.uki.enable [0],
# so the systemd-boot builder only emits separate linux+initrd entries.
# This module adds a UKI boot entry via extraEntries + a systemd service
# that copies the UKI to the ESP at boot.
#
# The UKI is built as part of the system generation (via boot.uki module).
# The copy service runs at boot and locates the UKI via the bootspec JSON
# stored in the current system generation (/run/current-system/boot.json).
# This avoids referencing config.system.build.uki from the boot config
# (which creates an eval-time cycle because the UKI's cmdline embeds
# init=.../toplevel).
#
# [0] https://github.com/NixOS/nixpkgs/pull/506543
#
# Security benefit: with UKI + systemd-stub, PCR 7 (Secure Boot) measures
# the signed UKI binary, providing attestation. Currently Secure Boot is
# DISABLED on all hosts, so PCR 7 reflects "SB off" — enabling UKI is a
# step toward real measured boot.

{ config, lib, pkgs, ... }:
{
  # Add UKI boot entry to systemd-boot via extraEntries.
  # The UKI is self-contained (cmdline, kernel, initrd embedded by ukify),
  # so the entry only needs `linux /nixos-uki.efi` — systemd-stub handles
  # the rest. The .efi file is copied to the ESP by the uki-copy service.
  #
  # Sort key "a-nixos-uki" sorts before "nixos" (the default NixOS entries'
  # sort key), making this the default boot target.
  boot.loader.systemd-boot.extraEntries = {
    "nixos-uki.conf" = ''
      title NixOS (UKI)
      linux /nixos-uki.efi
      sort-key a-nixos-uki
    '';
  };

  # Add the UKI filename to the bootspec extension so the runtime service
  # can find it. This is just a string (the filename "nixos.efi"), not a
  # derivation reference — so no eval-time cycle.
  boot.bootspec.extensions."org.nixos.systemd-boot".ukiFile =
    lib.mkDefault config.system.boot.loader.ukiFile;

  # Systemd service: copies the UKI binary from the Nix store to the ESP.
  # The script is written as a separate file to avoid Nix single-quote
  # conflicts with embedded Python/JavaScript code.
  systemd.services.uki-copy = {
    description = "Copy UKI to ESP for systemd-boot";
    wantedBy = ["multi-user.target"];
    after = ["boot.mount"];
    wants = ["boot.mount"];
    # Inline script: find ESP mount, read bootspec for ukiFile,
    # search /nix/store for the UKI, copy to ESP.
    script = ''
      #!/bin/bash
      set -euo pipefail

      # Find the ESP mount point
      boot_mount=$(findmnt -n -o TARGET /boot 2>/dev/null || echo "")
      if [ -z "$boot_mount" ]; then
        echo "uki-copy: ESP not mounted at /boot, skipping"
        exit 0
      fi

      # Read the bootspec JSON from the current system generation
      bootspec="/run/current-system/boot.json"
      uki_filename=""
      if [ -f "$bootspec" ]; then
        uki_filename=$(${pkgs.jq}/bin/jq -r "..org.nixos.systemd-bootstrap.ukiFile // empty" "$bootspec" 2>/dev/null || echo "")
      fi

      if [ -z "$uki_filename" ]; then
        echo "uki-copy: no ukiFile in bootspec, skipping"
        exit 0
      fi

      # Find the UKI in the Nix store
      uki_file=""
      for dir in /nix/store/*-nixos.efi; do
        if [ -f "$dir/$uki_filename" ]; then
          uki_file="$dir/$uki_filename"
          break
        fi
      done

      if [ -z "$uki_file" ] || [ ! -f "$uki_file" ]; then
        echo "uki-copy: UKI binary not found, skipping"
        exit 0
      fi

      # Copy the UKI to the ESP
      ${pkgs.coreutils}/bin/install -Dp "$uki_file" "$boot_mount/nixos-uki.efi" 2>/dev/null && {
        echo "uki-copy: copied UKI to $boot_mount/nixos-uki.efi"
      } || echo "uki-copy: cannot write to ESP, skipping"
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}
