{
  # Astral Key OAuth2 application
  clientId = "astral-key-oidc";

  # OIDC issuer (Astral Key public URL)
  oidcIssuerUrl = "https://auth.lan";

  # OAuth2 callback redirect
  redirectUrl = "https://auth.lan/oauth2/callback";

  # Cookie domain for cross-service SSO
  cookieDomain = ".lan";

  # Scopes to request from Astral Key
  scope = "openid profile email";

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

  clientSecretFile = "/run/secrets/central-auth-client-secret";
  cookieSecretFile = "/run/secrets/central-auth-cookie-secret";
}
