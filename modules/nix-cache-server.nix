# Nix Cache Server Module
# Provides a local Nix cache server for reverb-os and other caches
{config, lib, pkgs, ...}:
with lib; {
  options.services.nix-cache-server = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable local Nix cache server";
    };
    
    port = mkOption {
      type = types.int;
      default = 3000;
      description = "Port for the Nix cache server";
    };
  };

  config = mkIf config.services.nix-cache-server.enable {
    # Create cache server service
    systemd.services.nix-cache-server = {
      description = "Nix Cache Server";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 /usr/local/bin/nix-cache-server.py";
        Restart = "always";
        User = "nixbld";
        Group = "nixbld";
        Environment = "PATH=${pkgs.coreutils}/bin:${pkgs.python3}/bin:/usr/bin:/bin";
      };
    };

    # Create nixbld user and group
    users.users.nixbld = {
      isSystemUser = true;
      group = "nixbld";
      description = "Nix build user";
      shell = "/sbin/nologin";
      home = "/var/empty";
    };

    users.groups.nixbld = {
      name = "nixbld";
      members = ["nixbld"];
    };

    # Create cache directory
    systemd.tmpfiles.rules = [
      "d /var/cache/nix-cache 0755 nixbld nixbld -"
    ];

    # Create cache server script
    environment.etc."nix-cache-server.py" = {
      source = pkgs.writeTextFile {
        name = "nix-cache-server.py";
        executable = true;
        text = ''
          #!/usr/bin/env python3
          import os
          import sys
          import socket
          import threading
          from http.server import HTTPServer, SimpleHTTPRequestHandler
          import hashlib

          class NixCacheHandler(SimpleHTTPRequestHandler):
              def do_GET(self):
                  # Handle Nix cache requests
                  if self.path.startswith('/nix/store/'):
                      # Serve store objects
                      file_path = self.path[1:]  # Remove leading slash
                      if os.path.exists(file_path):
                          self.send_response(200)
                          self.send_header('Content-type', 'application/octet-stream')
                          self.end_headers()
                          with open(file_path, 'rb') as f:
                              self.wfile.write(f.read())
                      else:
                          self.send_error(404)
                  elif self.path == '/nix-cache-info':
                      # Serve cache info
                      self.send_response(200)
                      self.send_header('Content-type', 'text/plain')
                      self.end_headers()
                      self.wfile.write(b"StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 30\n")
                  else:
                      self.send_error(404)

          if __name__ == '__main__':
              PORT = ${toString config.services.nix-cache-server.port}
              with HTTPServer(("", PORT), NixCacheHandler) as httpd:
                  print(f"Nix cache server running on port {PORT}")
                  httpd.serve_forever()
        '';
      };
    };

    # Open firewall port
    networking.firewall.allowedTCPPorts = [config.services.nix-cache-server.port];
  };
}