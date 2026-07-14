{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) types mkEnableOption mkOption mkIf mkForce;
  cfg = config.services.nix-cache;
in {
  options.services.nix-cache = {
    enable = mkEnableOption "Nix binary cache with pull-through proxy";

    port = mkOption {
      type = types.port;
      default = 50000;
      description = "Public port for the cache proxy to listen on";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "10.1.1.120";
      description = "Address to bind the cache proxy to";
    };

    backendPort = mkOption {
      type = types.port;
      default = 50001;
      description = "Internal port for nix-serve-ng (behind the proxy)";
    };

    signingKeyName = mkOption {
      type = types.str;
      default = "zephyr-cache-1";
      description = "Key name for cache signing";
    };

    nixStore = mkOption {
      type = types.str;
      default = "/nix/store";
      description = "Path to the Nix store";
    };

    pullThrough = mkOption {
      type = types.bool;
      default = true;
      description = "Enable pull-through cache warming on cache miss";
    };

    metrics = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Prometheus metrics endpoint at /metrics";
    };
  };

  config = mkIf cfg.enable {
    # ── nix-cache-proxy package ────────────────────────────────
    nixpkgs.overlays = [
      (final: prev: {
        nix-cache-proxy = prev.callPackage ../../pkgs/nix-cache-proxy {};
      })
    ];

    # ── Cache signing key generation ──────────────────────────
    systemd.services.generate-nix-cache-keys = {
      description = "Generate Nix cache signing keys";
      wantedBy = ["multi-user.target"];
      before = ["nix-cache-proxy.service"];
      serviceConfig.Type = "oneshot";
      script = ''
        if [ ! -f /etc/nix/cache-priv.key ]; then
          ${pkgs.nix}/bin/nix key generate-secret \
            --key-name ${cfg.signingKeyName} > /etc/nix/cache-priv.key.tmp
          mv /etc/nix/cache-priv.key.tmp /etc/nix/cache-priv.key
          chmod 640 /etc/nix/cache-priv.key

          ${pkgs.nix}/bin/nix key convert-secret-to-public \
            < /etc/nix/cache-priv.key > /etc/nix/cache-pub.key
          chmod 444 /etc/nix/cache-pub.key

          echo "Binary cache keys generated"
          echo "Public key: $(cat /etc/nix/cache-pub.key)"
        fi
      '';
    };

    # ── nix-serve-ng (internal, behind proxy) ──────────────────
    systemd.services.nix-serve-internal = {
      description = "Nix binary cache server (internal)";
      wantedBy = ["multi-user.target"];
      after = ["generate-nix-cache-keys.service" "network.target"];
      requires = ["generate-nix-cache-keys.service"];
      serviceConfig = {
        ExecStart = pkgs.writeShellScript "nix-serve-start" ''
          export NIX_SECRET_KEY_FILE="/etc/nix/cache-priv.key"
          exec ${pkgs.nix-serve-ng}/bin/nix-serve \
            --listen 127.0.0.1:${toString cfg.backendPort} \
            --timeout 300
        '';
        Restart = "always";
        RestartSec = "5s";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [cfg.nixStore];
        ReadOnlyPaths = ["/etc/nix/cache-priv.key"];
      };
    };

    # ── nix-cache-proxy (public, pull-through, metrics) ──────
    systemd.services.nix-cache-proxy = {
      description = "Nix cache proxy with pull-through and metrics";
      wantedBy = ["multi-user.target"];
      after = ["nix-serve-internal.service" "network.target"];
      requires = ["nix-serve-internal.service"];
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          "${lib.getExe pkgs.nix-cache-proxy}"
          "--listen ${cfg.bindAddress}:${toString cfg.port}"
          "--backend http://127.0.0.1:${toString cfg.backendPort}"
          "--nix-store ${cfg.nixStore}"
        ];
        Restart = "always";
        RestartSec = "5s";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadOnlyPaths = [cfg.nixStore];
      };
    };

    # ── Display public key on boot ────────────────────────────
    systemd.services.display-cache-key = {
      description = "Display Nix binary cache public key";
      wantedBy = ["multi-user.target"];
      after = ["generate-nix-cache-keys.service"];
      serviceConfig.Type = "oneshot";
      script = ''
        echo "========================================="
        echo "Nix Binary Cache Public Key:"
        echo "========================================="
        cat /etc/nix/cache-pub.key 2>/dev/null || echo "(not yet generated)"
        echo "========================================="
      '';
    };

    # ── Firewall ──────────────────────────────────────────────
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];

    # ── Prometheus metrics integration ────────────────────────
    services.prometheus.exporters = lib.mkIf (config.services.prometheus.exporters != {}) {
      nix-cache = {
        enable = cfg.metrics;
        port = cfg.port;
        metricsPath = "/metrics";
      };
    };

    environment.systemPackages = [pkgs.nix-cache-proxy];
  };
}
