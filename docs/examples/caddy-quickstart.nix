# Caddy Quickstart Example
# Replace nginx with Caddy for simple reverse proxy scenarios

# Example 1: Simple reverse proxy (replaces nginx proxy_pass)
services.caddy-module = {
  # Reverse proxy for a web service
  "localhost:8080" = {
    reverseProxy = "127.0.0.1";
    reverseProxyPort = 3000; # Port to proxy to
  };
};

# Example 2: With basic authentication
services.caddy-module = {
  "private.example.com" = {
    reverseProxy = "127.0.0.1";
    reverseProxyPort = 8080;
    basicAuth = {
      user = "admin";
      password = "$2a$14$..."; # Use: caddy hash-password --plaintext "your-password"
    };
  };
};

# Example 3: Static file server
services.caddy-module = {
  "files.example.com" = {
    port = 80;
    fileServer = "/var/lib/files";
  };
};

# Example 4: Health check endpoint
services.caddy-module = {
  ":8080" = {
    respond = "/health \"OK\"";
  };
};

# Example 5: With automatic HTTPS (Let's Encrypt)
services.caddy-module = {
  "example.com" = {
    port = 443;
    reverseProxy = "127.0.0.1";
    reverseProxyPort = 3000;
    tls = {
      email = "admin@example.com"; # For Let's Encrypt
    };
  };
};
