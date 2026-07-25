# mosaic-bridges.nix — Secretspec-wrapped Mosaic protocol bridge daemons.
#
# Each bridge runs as a systemd service with credentials resolved through
# secretspec → sops-nix before the Node.js process starts.
#
# Enable individual bridges:
#   services.mosaic-bridges.buzz.enable = true;
#   services.mosaic-bridges.matrix.enable = true;
#   services.mosaic-bridges.irc.enable = true;

{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkOption types mkIf;

  cfg = config.services.mosaic-bridges;

  # Path to the Mosaic bridges directory
  bridgeDir = "/home/j_kro/Projects/astral-key/identity/mosaic/bridges";

  # Secretspec binary (from the secretspec flake input or system package)
  secretspecBin = "/home/j_kro/.local/bin/secretspec"; # TODO: switch to pkgs.secretspec when overlay builds correctly

  # Generate a secretspec-wrapped bridge service
  mkBridgeService = name: description: scriptPath: envOverrides: {
    description = "Mosaic ${description} bridge";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [ nodejs secretspec ];
    script = ''
      # Resolve bridge secrets via secretspec, then launch
      cd ${bridgeDir}
      export MIS_URL=http://mosaic-identity:8081
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") envOverrides)}
      exec ${secretspecBin} run --profile production -- \
        ${pkgs.nodejs}/bin/node '${scriptPath}'
    '';

    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "10s";
      User = "j_kro";
      Group = "users";
    };
  };

in {
  options.services.mosaic-bridges = {
    enable = mkEnableOption "Mosaic protocol bridge daemons";

    buzz = {
      enable = mkEnableOption "Buzz/Nostr relay bridge";
      relayUrl = mkOption {
        type = types.str;
        default = "wss://relay.damus.io";
        description = "Buzz Nostr relay WebSocket URL";
      };
    };

    matrix = {
      enable = mkEnableOption "Matrix Application Service bridge";
      asPort = mkOption {
        type = types.port;
        default = 8082;
        description = "Matrix AS HTTP server port";
      };
      domain = mkOption {
        type = types.str;
        default = "matrix.local";
        description = "Matrix homeserver domain";
      };
    };

    irc = {
      enable = mkEnableOption "IRC channel bridge";
      server = mkOption {
        type = types.str;
        default = "irc.libera.chat";
        description = "IRC server hostname";
      };
      port = mkOption {
        type = types.port;
        default = 6697;
        description = "IRC TLS port";
      };
      nick = mkOption {
        type = types.str;
        default = "MosaicBridge";
        description = "IRC bot nickname";
      };
      channels = mkOption {
        type = types.str;
        default = "";
        description = "Comma-separated IRC channels to join";
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services = {
      mosaic-bridge-buzz = mkIf cfg.buzz.enable (mkBridgeService "buzz" "Buzz/Nostr"
        "${bridgeDir}/buzz/index.js" {
          BUZZ_RELAY_URL = cfg.buzz.relayUrl;
        });

      mosaic-bridge-matrix = mkIf cfg.matrix.enable (mkBridgeService "matrix" "Matrix"
        "${bridgeDir}/matrix/index.js" {
          MATRIX_AS_PORT = toString cfg.matrix.asPort;
          MATRIX_DOMAIN = cfg.matrix.domain;
        });

      mosaic-bridge-irc = mkIf cfg.irc.enable (mkBridgeService "irc" "IRC"
        "${bridgeDir}/irc/index.js" {
          IRC_SERVER = cfg.irc.server;
          IRC_PORT = toString cfg.irc.port;
          IRC_NICK = cfg.irc.nick;
          IRC_CHANNELS = cfg.irc.channels;
        });
    };

    # Declare the secrets these bridges need (if not already declared)
    sops.secrets = lib.mkMerge [
      (lib.mkIf cfg.buzz.enable {
        "mosaic/buzz-private-key" = {
          sopsFile = "${builtins.toString ../secrets}/mosaic/buzz-private-key.yaml";
          path = "/run/secrets/mosaic-buzz-private-key";
          format = "binary";
          mode = "0444";
        };
      })
      (lib.mkIf cfg.matrix.enable {
        "mosaic/matrix-as-token" = {
          sopsFile = "${builtins.toString ../secrets}/mosaic/matrix-as-token.yaml";
          path = "/run/secrets/mosaic-matrix-as-token";
          format = "binary";
          mode = "0444";
        };
        "mosaic/matrix-hs-token" = {
          sopsFile = "${builtins.toString ../secrets}/mosaic/matrix-hs-token.yaml";
          path = "/run/secrets/mosaic-matrix-hs-token";
          format = "binary";
          mode = "0444";
        };
      })
    ];
  };
}
