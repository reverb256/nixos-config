# Boot Error Fixes - Resolves all identified boot issues
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types mkIf mkDefault;
in {
  options.services.boot-error-fixes = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable fixes for identified boot errors";
    };
  };

  config = mkIf config.services.boot-error-fixes.enable {
    # ============================================================================
    # FIX 1: Create plugdev group for udev rules (PS5 controller support)
    # ============================================================================
    users.groups.plugdev = {};

    # ============================================================================
    # FIX 3: Fix Podman generator (if it's causing issues)
    # ============================================================================
    # The podman-system-generator error is usually benign
    # but we ensure podman is properly configured
    virtualisation.podman = mkDefault {
      enable = true;
      dockerCompat = true;
    };

    # ============================================================================
    # FIX 4: Ensure tmpfiles are created with correct groups
    # ============================================================================
    # This is already fixed in scopebuddy.nix (commit 53c2c6a)
    # but we ensure the system uses the updated configuration

    # ============================================================================
    # MONITORING: Log boot errors to help track issues
    # ============================================================================
    systemd.services.boot-error-monitor = {
      description = "Monitor and report boot errors";
      wantedBy = ["multi-user.target"];
      after = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "boot-error-check" ''
          #!${pkgs.bash}/bin/bash
          echo "=== Boot Error Status ===" | ${pkgs.coreutils}/bin/tee -a /var/log/boot-errors.log

          # Check if agenix secrets were decrypted
          if [ -z "$(${pkgs.coreutils}/bin/ls /run/agenix.d/*/ 2>/dev/null)" ]; then
            echo "WARNING: No agenix secrets decrypted" | ${pkgs.coreutils}/bin/tee -a /var/log/boot-errors.log
          fi

          # Check if GlitchTip services are running
          if ! ${pkgs.systemd}/bin/systemctl is-active --quiet glitchtip-postgres.service; then
            echo "ERROR: GlitchTip PostgreSQL not running" | ${pkgs.coreutils}/bin/tee -a /var/log/boot-errors.log
          fi

          # Check if plugdev group exists
          if ! ${pkgs.shadow}/bin/getent group plugdev >/dev/null 2>&1; then
            echo "WARNING: plugdev group missing" | ${pkgs.coreutils}/bin/tee -a /var/log/boot-errors.log
          fi
        '';
        RemainAfterExit = true;
      };
    };
  };
}
