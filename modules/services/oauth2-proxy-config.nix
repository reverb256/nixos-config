# ─────────────────────────────────────────────────────────────────
# OAuth2-Proxy Configuration — single source of truth for BOTH
# the NixOS central-auth systemd service AND the K8s oauth2-proxy
# deployment. Edit here, both sides stay in sync.
# ─────────────────────────────────────────────────────────────────
{
  # Authelia OAuth2 application
  clientId = "authelia-oidc";

  # OIDC issuer (Authelia public URL)
  oidcIssuerUrl = "https://auth.lan";

  # OAuth2 callback redirect
  redirectUrl = "https://auth.lan/oauth2/callback";

  # Cookie domain for cross-service SSO
  cookieDomain = ".lan";

  # Scopes to request from Authelia
  scope = "openid profile email";

  # Routes that skip authentication (regex, comma-separated for K8s)
  skipAuthRoutes = [
    "^/health$"
    "^/healthz$"
    "^/api/health$"
    "^/ready$"
    "^/metrics$"
    "^/favicon"
    "^/assets/"
    "^/public/"
    "^/static/"
  ];

  # Secret file paths (NixOS systemd service only)
  # K8s deployment uses volume-mounted secrets at /etc/oauth2/secrets/
  clientSecretFile = "/run/secrets/central-auth-client-secret";
  cookieSecretFile = "/run/secrets/central-auth-cookie-secret";
}
