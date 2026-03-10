# Container Image Vulnerability Scanning
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.container-scanning = {
    enable = lib.mkEnableOption "Container vulnerability scanning with Trivy";
  };

  config = lib.mkIf config.services.container-scanning.enable {
    # Install Trivy
    environment.systemPackages = with pkgs; [
      trivy
    ];

    # Periodic scanning service (commented out - requires actual images to scan)
    # systemd.services.trivy-scan = {
    #   description = "Scan container images for vulnerabilities";
    #   serviceConfig = {
    #     Type = "oneshot";
    #     ExecStart = "/run/current-system/sw/bin/trivy image --severity HIGH,CRITICAL localhost:5000/myapp:latest";
    #     # Security hardening
    #     NoNewPrivileges = true;
    #     PrivateTmp = true;
    #     ProtectSystem = "strict";
    #     ProtectHome = true;
    #     RestrictRealtime = true;
    #     RestrictAddressFamilies = ["AF_UNIX" "AF_INET"];
    #   };
    # };
    #
    # # Weekly scan timer
    # systemd.timers.trivy-scan = {
    #   description = "Weekly container vulnerability scan";
    #   wantedBy = ["timers.target"];
    #   timerConfig = {
    #     OnCalendar = "weekly";
    #     Persistent = true;
    #   };
    # };
  };
}
