#!/usr/bin/env bash

set -e

echo "=== Fixing Nix warnings and setting up reverb-os cache ==="

echo "Fixing builtins.toFile warning..."
mkdir -p /etc/nixos-colmena/options
cat > /etc/nixos-colmena/options/options.json << 'EOF'
{
  "experimental-features": ["nix-command" "flakes"],
  "max-jobs": 8,
  "cores": 16,
  "trusted-users": ["root" "j_kro"],
  "substituters": [
    "https://cache.nixos.org",
    "https://nix-community.cachix.org",
    "https://ezkea.cachix.org",
    "https://nixpkgs-wayland.cachix.org",
    "https://nix-gaming.cachix.org",
    "https://cuda-maintainers.cachix.org"
  ],
  "trusted-public-keys": [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=",
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=",
    "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI=",
    "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA=",
    "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLkq5CX+/rkCWyvRCYg3Fs=",
    "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
  ],
  "secret-key-files": "/etc/nixos/secrets/nix-cache-key.sec"
}
EOF

cat > /etc/systemd/system/nix-cache-server.service << 'EOF'
[Unit]
Description=Nix Cache Server
After=network.target
Wants=network.target

[Service]
Type=exec
ExecStart=/nix/store/*/bin/nix-store serve --store /nix/store --listen-address 0.0.0.0:3000
Restart=always
User=nixbld
Group=nixbld
Environment=PATH=/nix/store/*/bin:/usr/bin:/bin
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

if ! getent group nixbld > /dev/null 2>&1; then
    sudo groupadd nixbld
fi

if ! getent passwd nixbld > /dev/null 2>&1; then
    sudo useradd -r -g nixbld -G nixbld -d /var/empty -s /sbin/nologin nixbld
fi

echo "Setting up local cache server for reverb-os..."

sudo mkdir -p /var/cache/nix-cache
sudo chown nixbld:nixbld /var/cache/nix-cache

cat > /usr/local/bin/nix-cache-server.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
import socket
import threading
from http.server import HTTPServer, SimpleHTTPRequestHandler
import hashlib

class NixCacheHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/nix/store/'):
            file_path = self.path[1:]
            if os.path.exists(file_path):
                self.send_response(200)
                self.send_header('Content-type', 'application/octet-stream')
                self.end_headers()
                with open(file_path, 'rb') as f:
                    self.wfile.write(f.read())
            else:
                self.send_error(404)
        elif self.path == '/nix-cache-info':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 30\n")
        else:
            self.send_error(404)

if __name__ == '__main__':
    PORT = 3000
    with HTTPServer(("", PORT), NixCacheHandler) as httpd:
        print(f"Nix cache server running on port {PORT}")
        httpd.serve_forever()
EOF

chmod +x /usr/local/bin/nix-cache-server.py

cat > /etc/systemd/system/nix-cache-http.service << 'EOF'
[Unit]
Description=Nix HTTP Cache Server
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/nix-cache-server.py
Restart=always
User=nixbld
Group=nixbld
Environment=PATH=/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling and starting cache services..."
sudo systemctl daemon-reload
sudo systemctl enable nix-cache-http.service
sudo systemctl start nix-cache-http.service

echo "Updating firewall for cache server..."
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --reload

echo "Creating local cache configuration..."
echo "Local cache server: http://localhost:3000" > /tmp/reverb-cache-url.txt

echo "=== Setup complete! ==="
echo "Services status:"
systemctl status nix-cache-http.service --no-pager -l
echo ""
echo "Cache URLs configured:"
cat /tmp/reverb-cache-url.txt
echo ""
echo "To test the cache server:"
echo "curl -s http://localhost:3000/nix-cache-info"