{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.nexus-exec;
  daemonScript = ./../../scripts/nexus-exec-daemon.py;
  clientScript = ./../../scripts/nexus-exec.sh;

  daemon = pkgs.runCommand "nexus-exec-daemon" {buildInputs = [pkgs.python3];} ''
    mkdir -p $out/bin
    cp ${daemonScript} $out/bin/nexus-exec-daemon
    chmod +x $out/bin/nexus-exec-daemon
    substituteInPlace $out/bin/nexus-exec-daemon \
      --replace-fail "/usr/bin/env python3" "${pkgs.python3}/bin/python3"
  '';

  client = pkgs.runCommand "nexus-exec" {} ''
    mkdir -p $out/bin
    cp ${clientScript} $out/bin/nexus-exec
    chmod +x $out/bin/nexus-exec
  '';

  tunnel = pkgs.writeShellScript "nexus-exec-tunnel" ''
    set -euo pipefail
    mkdir -p $(dirname ${cfg.clientSocketPath})
    exec ${pkgs.openssh}/bin/ssh -i /run/secrets/cns-ssh-key -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -NL ${cfg.clientSocketPath}:${cfg.listenSocket} cluster-mesh@nexus
  '';
in {
  options.services.nexus-exec = {
    enable = lib.mkEnableOption "Nexus remote command execution daemon (server)";

    listenSocket = lib.mkOption {
      type = lib.types.str;
      default = "/run/nexus-exec/exec.sock";
      description = "Unix socket path for the daemon on Nexus";
    };

    clientSocketPath = lib.mkOption {
      type = lib.types.str;
      default = "/tmp/nexus-exec.sock";
      description = "Local socket path for SSH-tunnelled client";
    };

    enableTunnel = lib.mkEnableOption "SSH tunnel for nexus-exec socket forwarding (Zephyr only)";
  };

  config = lib.mkIf cfg.enable {
    # Daemon service (server-side — Nexus)
    systemd.services.nexus-exec = lib.mkIf (!cfg.enableTunnel) {
      description = "Nexus remote command execution daemon";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = "${daemon}/bin/nexus-exec-daemon";
        User = "j_kro";
        RuntimeDirectory = "nexus-exec";
        RuntimeDirectoryMode = "0700";
        Restart = "always";
        RestartSec = "3";
        TimeoutStopSec = "10";
      };
      environment.NEXUS_EXEC_SOCKET = cfg.listenSocket;
    };

    # SSH tunnel service (client-side — Zephyr)
    systemd.services.nexus-exec-tunnel = lib.mkIf cfg.enableTunnel {
      description = "SSH tunnel for nexus-exec socket forwarding";
      after = ["network.target"];
      wants = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = "${tunnel}";
        User = "cluster-mesh";
        Restart = "always";
        RestartSec = "5";
        StandardOutput = "journal";
      };
    };

    # Client package (installed everywhere nexus-exec is enabled)
    environment.systemPackages = [client];

    # Ensure socket dir exists
    systemd.tmpfiles.rules = [
      "d ${builtins.dirOf cfg.listenSocket} 0700 j_kro users -"
    ];
  };
}
