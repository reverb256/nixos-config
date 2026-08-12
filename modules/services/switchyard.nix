{ config, lib, pkgs, ... }:
with lib; let
  cfg = config.services.switchyard;

  # Assemble KEY=VALUE lines from the per-secret files into a runtime env
  # file (tmpfs — never in the Nix store). Mirrors the opencode.nix pattern
  # of reading secrets from /run/secrets at runtime.
  envFileScript = pkgs.writeShellScript "switchyard-envfile" ''
    set -euo pipefail
    env_file="/run/switchyard/switchyard.env"
    : > "$env_file"
    chmod 600 "$env_file"
    ${concatStringsSep "\n" (mapAttrsToList (name: path: ''
      if [ -r ${escapeShellArg path} ]; then
        printf '%s=%s\n' ${escapeShellArg name} "$(cat ${escapeShellArg path})" >> "$env_file"
      else
        echo "WARN: switchyard secret ${escapeShellArg path} missing" >&2
      fi
    '') cfg.envFiles)}
  '';
in {
  options.services.switchyard = {
    enable = mkEnableOption "Switchyard LLM routing proxy";

    package = mkOption {
      type = types.package;
      default = pkgs.switchyard-server;
      description = "switchyard-server package (mainProgram: switchyard-server).";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address the proxy binds to. Keep 127.0.0.1 unless the mesh needs it.";
    };

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "TCP port the proxy listens on.";
    };

    configFile = mkOption {
      type = types.path;
      description = "routes.toml defining llm_clients/targets/routes (schema_version=1).";
    };

    # API keys referenced by api_key_env in routes.toml. Values are read
    # from secret files at runtime (opencode.nix /run/secrets pattern) —
    # never committed plaintext, never stored in /nix/store.
    envFiles = mkOption {
      type = types.attrsOf types.path;
      default = {};
      description = "Map of env-var name -> secret file path (e.g. NVIDIA_API_KEY -> /run/secrets/nvidia-api-key).";
    };
  };

  config = mkIf cfg.enable {
    # Refresh /run/secrets before the proxy starts. secretspec-creds runs at
    # boot only (RemainAfterExit) and colmena activation recreates /run/secrets
    # empty — every deploy starves switchyard of API keys. This oneshot
    # restarts the unit (root) so the envFileScript sees fresh files.
    systemd.services.switchyard-secrets = {
      description = "Refresh SecretSpec credentials for switchyard";
      wantedBy = [ "multi-user.target" ];
      after = [ "secretspec-creds.service" ];
      wants = [ "secretspec-creds.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/systemctl restart secretspec-creds.service";
      };
    };

    systemd.services.switchyard = {
      description = "Switchyard LLM routing proxy";
      after = [ "network-online.target" "switchyard-secrets.service" ];
      wants = [ "network-online.target" ];
      requires = [ "switchyard-secrets.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "switchyard";
        Group = "switchyard";
        # /run/secrets is drwxr-x--x root:keys — switchyard must traverse it
        # to read api keys at runtime.
        SupplementaryGroups = [ "keys" ];
        RuntimeDirectory = "switchyard";
        RuntimeDirectoryMode = "0700";
        ExecStartPre = envFileScript;
        ExecStart = "${lib.getExe cfg.package} --config ${cfg.configFile} --host ${cfg.host} --port ${toString cfg.port}";
        EnvironmentFile = "-/run/switchyard/switchyard.env";
        Restart = "on-failure";
        RestartSec = "5";
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = [ cfg.configFile "/run/secrets" ];
      };
    };

    users.users.switchyard = {
      isSystemUser = true;
      group = "switchyard";
    };
    users.groups.switchyard = {};

    # Localhost-only by default; cluster-firewall.nix handles cross-host access.
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];
  };
}
