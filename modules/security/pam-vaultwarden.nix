# Vaultwarden PAM Authentication Module
# Allows system authentication using Vaultwarden credentials
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.security.pamVaultwarden;
  inherit (lib) mkEnableOption mkOption types mkIf mkBefore;
in {
  options.security.pamVaultwarden = {
    enable = mkEnableOption "Vaultwarden PAM authentication";

    url = mkOption {
      type = types.str;
      default = "http://localhost:8222";
      example = "http://vaultwarden.ts.net:8222";
      description = "Vaultwarden server URL";
    };

    services = mkOption {
      type = types.listOf types.str;
      default = ["login" "sshd" "su" "sudo"];
      example = ["login" "sshd" "sudo"];
      description = "PAM services to enable Vaultwarden authentication for";
    };

    fallbackToSystem = mkOption {
      type = types.bool;
      default = true;
      description = "Allow system authentication if Vaultwarden is unavailable";
    };
  };

  config = mkIf cfg.enable {
    # Install the authentication script
    environment.etc."pam-vaultwarden/auth.py".source = pkgs.writeScript "pam-vaultwarden-auth.py" ''
      #!${pkgs.python3}/bin/python3
      import sys
      import os
      import json
      import urllib.request
      import urllib.error

      VAULTWARDEN_URL = "${cfg.url}"
      VAULTWARDEN_API = f"{VAULTWARDEN_URL}/identity"
      REQUEST_TIMEOUT = 10

      def log_error(message):
          print(f"ERROR: {message}", file=sys.stderr)

      def prelogin(username):
          try:
              data = {"email": username}
              req = urllib.request.Request(
                  f"{VAULTWARDEN_API}/accounts/prelogin",
                  data=json.dumps(data).encode('utf-8'),
                  headers={
                      'Content-Type': 'application/json',
                      'Device-Type': '0',
                  }
              )
              with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
                  return json.loads(response.read().decode('utf-8'))
          except urllib.error.HTTPError as e:
              if e.code == 404:
                  return {"Kdf": 0, "KdfIterations": 600000}
              raise
          except Exception as e:
              log_error(f"Prelogin failed: {e}")
              raise

      def authenticate(username, password):
          try:
              prelogin_data = prelogin(username)

              data = {
                  "grant_type": "password",
                  "username": username,
                  "password": password,
                  "scope": "api offline_access",
                  "client_id": "browser",
                  "deviceType": 0,
              }

              req = urllib.request.Request(
                  f"{VAULTWARDEN_API}/connect/token",
                  data=json.dumps(data).encode('utf-8'),
                  headers={
                      'Content-Type': 'application/json',
                      'Accept': 'application/json',
                  }
              )

              with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
                  result = json.loads(response.read().decode('utf-8'))
                  return "access_token" in result

          except urllib.error.HTTPError as e:
              if e.code in (400, 401):
                  return False
              log_error(f"HTTP error during auth: {e.code}")
              return False
          except Exception as e:
              log_error(f"Authentication error: {e}")
              return False

      def main():
          username = os.environ.get("PAM_USER")
          if not username:
              log_error("PAM_USER not set")
              sys.exit(2)

          password = os.environ.get("PAM_AUTHTOK")
          if not password:
              try:
                  password = sys.stdin.readline().strip()
              except:
                  log_error("No password provided")
                  sys.exit(1)

          if authenticate(username, password):
              sys.exit(0)
          else:
              sys.exit(1)

      if __name__ == "__main__":
          main()
    '';

    # Configure PAM services
    security.pam.services = lib.listToAttrs (map (service: {
      name = service;
      value = {
        rules = lib.mkBefore [
          {
            # Vaultwarden authentication (sufficient = success if it works)
            # ${lib.optionalString cfg.fallbackToSystem "[success=ignore default=1]"} = {
            control = if cfg.fallbackToSystem then "[success=ignore default=1]" else "sufficient";
            modulePath = "${pkgs.linux-pam}/lib/security/pam_exec.so";
            settings = {
              expose_authtok = true;
              quiet = true;
              # Set VAULTWARDEN_URL environment variable
              env = [
                { name = "VAULTWARDEN_URL"; value = cfg.url; }
              ];
              # The script to execute
              command = "/etc/pam-vaultwarden/auth.py";
            };
          }
        ];
      };
    }) cfg.services);
  };
}
