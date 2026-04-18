{ config, lib, pkgs, ... }:
let
  cfg = config.services.vane;
  inherit (lib) mkEnableOption mkOption types mkIf;
in
{
  options.services.vane = {
    enable = mkEnableOption "Vane AI search engine";
    port = mkOption { type = types.port; default = 30900; };
    image = mkOption { type = types.str; default = "docker.io/itzcrazykns1337/vane:slim-latest"; };
    searxngUrl = mkOption { type = types.str; default = "http://10.1.1.120:30888"; };
    dataDir = mkOption { type = types.str; default = "/var/lib/vane"; };
    openFirewall = mkOption { type = types.bool; default = false; };
  };
  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0755 root root -" ];
    systemd.services.vane = {
      description = "Vane AI Search Engine";
      after = [ "network-online.target" "podman.service" ];
      wants = [ "network-online.target" ];
      requires = [ "podman.service" ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        ${pkgs.podman}/bin/podman rm -f vane 2>/dev/null || true
      '';
      serviceConfig = {
        Type = "exec";
        ExecStart = "${pkgs.podman}/bin/podman run --name vane -p ${toString cfg.port}:3000 -e SEARXNG_API_URL=${cfg.searxngUrl} -v ${cfg.dataDir}:/home/vane/data --restart=no ${cfg.image}";
        ExecStop = "${pkgs.podman}/bin/podman stop -t 10 vane";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = "120";
      };
    };
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall (lib.mkOptionDefault [ cfg.port ]);
  };
}
