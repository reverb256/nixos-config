# Searxng Module
# Privacy-respecting metasearch engine (from XNM1)
{
  pkgs,
  config,
  ...
}: {
  # ============================================================================
  # SEARXNG - Privacy-Focused Metasearch Engine
  # ============================================================================
  services.searx = {
    enable = true;
    settings = {
      server = {
        port = 7777;
        bind_address = "127.0.0.1"; # Localhost only - use reverse proxy for external access
        secret_key = "@SEARX_SECRET_KEY@"; # Set via environmentFile
      };
      search = {
        formats = ["html" "json"];
      };
    };
    # Environment file at /etc/searxng/env with SEARX_SECRET_KEY variable
    environmentFile = config.users.users.j_kro.home + "/.config/.env.searxng";
  };

  # ============================================================================
  # NOTES
  # ============================================================================
  # 1. Generate a secret key: `openssl rand -hex 32`
  # 2. Create environment file: ~/.config/.env.searxng
  #    contents: SEARX_SECRET_KEY=your_generated_key_here
  # 3. Access at: http://127.0.0.1:7777
  # 4. For external access, configure nginx/caddy reverse proxy
}
