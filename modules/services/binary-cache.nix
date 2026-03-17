# Nix Binary Cache Server
# Serves pre-built Nix packages to the cluster
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) types mkEnableOption mkOption mkIf mkBefore;
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
      default = "10.1.1.110";
      description = "Address to bind nix-serve to";
    };
  };

  config = mkIf cfg.enable {
    # Ensure openssl is available for key generation
    environment.systemPackages = with pkgs; [openssl];

    # nix-serve service - serves binary cache via HTTP
    services.nix-serve = {
      enable = true;
      secretKeyFile = "/etc/nix/cache-priv.key";
      port = cfg.port;
      bindAddress = cfg.bindAddress;
    };

    # Open firewall for binary cache
    networking.firewall.allowedTCPPorts = [cfg.port];

    # Generate cache signing keys if they don't exist
    systemd.services.generate-nix-cache-keys = {
      description = "Generate Nix cache signing keys";
      wantedBy = ["multi-user.target"];
      before = ["nix-serve.service"];
      serviceConfig.Type = "oneshot";
      script = ''
        if [ ! -f /etc/nix/cache-priv.key ]; then
          # Generate binary cache signing keys using OpenSSL
          ${pkgs.openssl}/bin/openssl genrsa -out /etc/nix/cache-priv.key 4096
          chmod 640 /etc/nix/cache-priv.key

          # Convert to Nix format (cache-name-1:BASE64_KEY)
          # The full public key in DER format, base64 encoded
          PUB_KEY=$(${pkgs.openssl}/bin/openssl rsa -in /etc/nix/cache-priv.key -pubout | ${pkgs.openssl}/bin/openssl rsa -pubin -RSAPublicKey_in -outform DER 2>/dev/null | ${pkgs.coreutils}/bin/base64 -w 0)
          echo "zephyr-cache-1:$PUB_KEY" > /etc/nix/cache-pub.key
          chmod 444 /etc/nix/cache-pub.key

          echo "Binary cache keys generated"
          echo "Public key:"
          cat /etc/nix/cache-pub.key
        fi
      '';
    };

    # Display public key after generation for easy copy-paste
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
