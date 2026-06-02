{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) types mkEnableOption mkOption mkIf;
  cluster = config.networking.cluster;
  cfg = config.services.binary-cache;
in {
  options.services.binary-cache = {
    enable = mkEnableOption "Nix binary cache server (nix-serve)";

    port = mkOption {
      type = types.port;
      default = 50000;
      description = "Port for nix-serve to listen on";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "10.1.1.120";
      description = "Address to bind nix-serve to";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [openssl];

    services.nix-serve = {
      enable = true;
      secretKeyFile = "/etc/nix/cache-priv.key";
      inherit (cfg) port;
      inherit (cfg) bindAddress;
    };

    systemd.services.nix-serve.serviceConfig.ExecStart = lib.mkForce [
      (pkgs.writeShellScript "nix-serve-start" ''
        export NIX_SECRET_KEY_FILE="$CREDENTIALS_DIRECTORY/NIX_SECRET_KEY_FILE"
        exec ${pkgs.nix-serve}/bin/nix-serve \
          --listen ${cfg.bindAddress}:${toString cfg.port} \
          --workers 20 \
          --keepalive-timeout 60 \
          --read-timeout 300
      '')
    ];

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];

    systemd.services.generate-nix-cache-keys = {
      description = "Generate Nix cache signing keys";
      wantedBy = ["multi-user.target"];
      before = ["nix-serve.service"];
      serviceConfig.Type = "oneshot";
      script = ''
        if [ ! -f /etc/nix/cache-priv.key ]; then
          ${pkgs.nix}/bin/nix key generate-secret --key-name zephyr-cache-1 > /etc/nix/cache-priv.key.tmp
          mv /etc/nix/cache-priv.key.tmp /etc/nix/cache-priv.key
          chmod 640 /etc/nix/cache-priv.key

          ${pkgs.nix}/bin/nix key convert-secret-to-public < /etc/nix/cache-priv.key > /etc/nix/cache-pub.key
          chmod 444 /etc/nix/cache-pub.key

          echo "Binary cache keys generated"
          echo "Public key:"
          cat /etc/nix/cache-pub.key
        fi
      '';
    };

    systemd.services.display-cache-key = {
      description = "Display Nix binary cache public key";
      wantedBy = ["multi-user.target"];
      after = ["generate-nix-cache-keys.service"];
      serviceConfig.Type = "oneshot";
      script = ''
        echo "========================================="
        echo "Nix Binary Cache Public Key:"
        echo "========================================="
        cat /etc/nix/cache-pub.key
        echo "========================================="
        echo "Add this to trusted-public-keys on other nodes:"
        echo "nix.settings.trusted-public-keys = ["
        echo "  \"zephyr-cache-1:$(cat /etc/nix/cache-pub.key | cut -d: -f2)\""
        echo "];"
        echo "========================================="
      '';
    };
  };
}
