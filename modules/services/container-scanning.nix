{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.container-scanning;
  inherit
    (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    mkDefault
    ;
in {
  options.services.container-scanning = {
    enable = mkOption {
      type = types.bool;
      default = config.virtualisation.podman.enable or false;
      defaultText = "config.virtualisation.podman.enable";
      description = "Container vulnerability scanning with Trivy. Auto-enabled when Podman is present.";
    };

    severity = mkOption {
      type = types.str;
      default = "HIGH,CRITICAL";
      description = "Severity levels to report (comma-separated: LOW,MEDIUM,HIGH,CRITICAL)";
    };

    schedule = mkOption {
      type = types.str;
      default = "weekly";
      description = "Systemd calendar expression for scan schedule";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [trivy];

    systemd.services.trivy-scan = {
      description = "Scan all container images for vulnerabilities";
      after = [
        "network-online.target"
        "podman.service"
      ];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "trivy-scan" ''
          set -euo pipefail
          echo "Trivy Vulnerability Scan - $(date)"
          IMAGES=$(${pkgs.podman}/bin/podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)
          if [ -z "$IMAGES" ]; then
            echo "No container images found"
            exit 0
          fi
          FAILED=0
          for image in $IMAGES; do
            if echo "$image" | grep -q "<none>"; then
              continue
            fi
            echo "Scanning: $image"
            if ! ${pkgs.trivy}/bin/trivy image --severity ${cfg.severity} --no-progress "$image"; then
              echo "VULNERABILITIES FOUND in $image"
              FAILED=$((FAILED + 1))
            else
              echo "OK: No high/critical vulnerabilities in $image"
            fi
          done
          if [ "$FAILED" -gt 0 ]; then
            echo "SCAN COMPLETE: $FAILED image(s) have vulnerabilities"
          else
            echo "SCAN COMPLETE: All images clean"
          fi
        '';
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
        ];
        ReadWritePaths = ["/tmp"];
      };
    };

    systemd.timers.trivy-scan = {
      description = "Weekly container vulnerability scan timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
      };
    };
  };
}
