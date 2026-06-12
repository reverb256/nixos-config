{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.maplespike-ingress;
in {
  options.services.maplespike-ingress = {
    enable = mkEnableOption "MapleSpike ingress via Tailscale Serve";
  };

  config = mkIf cfg.enable {
    systemd.services.tailscale-serve-maplespike = {
      description = "Tailscale Serve — MapleSpike proxy";
      after = [ "tailscaled.service" "network.target" ];
      wants = [ "tailscaled.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --https=443 --set-path / http://127.0.0.1:8082";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve off";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
