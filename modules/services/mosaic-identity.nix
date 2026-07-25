{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.services.mosaic-identity;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.mosaic-identity = {
    enable = mkEnableOption "Mosaic Identity Service (PKI layer for cross-protocol identity)";

    port = mkOption {
      type = types.port;
      default = 8081;
      description = "Port for MIS to listen on";
    };

    databasePath = mkOption {
      type = types.str;
      default = "/data/mosaic-identity.db";
      description = "Path to SQLite database file";
    };

    enableAtprotoBridge = mkOption {
      type = types.bool;
      default = true;
      description = "Enable atproto DID resolution bridge";
    };

    enableBuzzBridge = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Buzz/Nostr relay bridge";
    };

    enableMatrixBridge = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Matrix Application Service bridge";
    };

    enableIrcBridge = mkOption {
      type = types.bool;
      default = false;
      description = "Enable IRC bridge";
    };
  };

  config = mkIf cfg.enable {
    # Kubernetes deployment manifests
    # Applied via: kubectl apply -f /etc/nixos/k8s/mosaic-identity/
    environment.etc = {
      "k8s/mosaic-identity/deployment.yaml".source = ./../../k8s/mosaic-identity/deployment.yaml;
      "k8s/mosaic-bridges/atproto-deployment.yaml".source = ./../../k8s/mosaic-bridges/atproto-deployment.yaml;
    } // lib.optionalAttrs cfg.enableBuzzBridge {
      "k8s/mosaic-bridges/buzz-deployment.yaml".source = ./../../k8s/mosaic-bridges/buzz-deployment.yaml;
    } // lib.optionalAttrs cfg.enableMatrixBridge {
      "k8s/mosaic-bridges/matrix-deployment.yaml".source = ./../../k8s/mosaic-bridges/matrix-deployment.yaml;
    } // lib.optionalAttrs cfg.enableIrcBridge {
      "k8s/mosaic-bridges/irc-deployment.yaml".source = ./../../k8s/mosaic-bridges/irc-deployment.yaml;
    };

    # Sops-nix secrets for bridge credentials
    sops.secrets = mkIf cfg.enableBuzzBridge {
      "k8s/mosaic-bridge-buzz-relay" = {};
      "k8s/mosaic-bridge-buzz-key" = {};
    } // mkIf cfg.enableMatrixBridge {
      "k8s/mosaic-bridge-matrix-as-token" = {};
      "k8s/mosaic-bridge-matrix-hs-token" = {};
      "k8s/mosaic-bridge-matrix-domain" = {};
    } // mkIf cfg.enableIrcBridge {
      "k8s/mosaic-bridge-irc-server" = {};
      "k8s/mosaic-bridge-irc-nick" = {};
    };
  };
}
