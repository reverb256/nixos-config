{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.kubernetes-mcp;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.kubernetes-mcp = {
    enable = mkEnableOption "Kubernetes MCP Server";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../packages/kubernetes-mcp-server.nix {};
    };

    toolsets = mkOption {
      type = types.listOf types.str;
      default = ["core"];
      description = "Toolsets to enable (core, helm, kiali, kubevirt)";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
    };

    transport = mkOption {
      type = types.enum ["stdio" "sse"];
      default = "stdio";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    systemd.services.kubernetes-mcp = mkIf (cfg.transport == "sse") {
      description = "Kubernetes MCP Server (SSE transport)";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "k3s.service"];
      serviceConfig = {
        ExecStart =
          "${lib.getExe cfg.package}"
          + " --transport sse"
          + " --port ${toString cfg.port}"
          + " --toolsets ${lib.concatStringsSep "," cfg.toolsets}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
