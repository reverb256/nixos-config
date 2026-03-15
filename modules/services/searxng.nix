# Searxng Module
# Privacy-respecting metasearch engine (from XNM1)
{config, lib, pkgs, ...}: let
  inherit (lib) mkEnableOption mkOption types mkIf literalExpression;
in {
  options.services.searx = {
    enable = mkEnableOption "SearXNG privacy-respecting metasearch engine";

    enableEngine = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable this search engine";
          };
          time_range_support = mkOption {
            type = types.bool;
            default = false;
            description = "Whether this engine supports time range filtering";
          };
        };
      });
      default = {};
      description = "Per-engine configuration";
    };
  };

  config = mkIf config.services.searx.enable {
    # ============================================================================
    # SEARXNG - Privacy-Focused Metasearch Engine
    # ============================================================================
    services.searx = {
      enable = true;
      settings = let
        # SearXNG secret key from agenix
        secretKeyFile = config.age.secrets.searxng-secret.path or "/run/agenix/searxng-secret";
      in {
        server = {
          port = 7777;
          bind_address = "127.0.0.1"; # Localhost only
          secret_key = "@SEARXNG_SECRET_KEY@";
          method = "GET";
          limiter = true;
          image_proxy = true;
        };

        search = {
          formats = ["html" "json" "csv" "rss"];
          safe_search = 0;
          autocomplete = "";
          autocomplete_min = 4;
        };

        ui = {
          infinite_scroll = false;
          static_use_hash = true;
          theme_path = "";
          center_alignment = true;
        };

        limiter = true;

        botdetection.ip_limit.link_token = false;
        botdetection.ip_limit.ip_lists.pass_searxng_org = true;

        outgoing = {
          request_timeout = 12.0;
          pool_connections = 100;
          pool_maxsize = 100;
          max_request_timeout = 18.0;
        };

        max_request_timeout = 18.0;

        # Engine configuration for robustness
        use_default_query = true;

        engines_drop = [
          # Drop problematic or spam engines
          "fds"
          "ytb" # YouTube broken (use youtube-video instead)
        ];

        # Categories for organized search
        categories = {
          general = ["google" "brave" "duckduckgo" "bing" "startpage"];
          science = ["google_scholar" "semantic_scholar" "arxiv" "wikipedia"];
          it = ["github" "stackoverflow" "reddit" "docker"];
          videos = ["youtube" "vimeo" "peertube"];
          images = ["google images" "bing images" "wikimedia" "flickr"];
          music = ["soundcloud"];
          files = ["kickass" "piratebay"];
          social = ["reddit" "twitter" "mastodon"];
        };
      };

      environmentFile = config.users.users.j_kro.home + "/.config/.env.searxng";
    };

    # Open firewall for local access
    networking.firewall.allowedTCPPorts = [7777];
  };

  # ============================================================================
  # NOTES
  # ============================================================================
  # 1. Generate secret key: `openssl rand -hex 32`
  # 2. Create environment file: ~/.config/.env.searxng
  # 3. Access at: http://127.0.0.1:7777
  #
  # AI/LLM Integration:
  # - JSON format: /search?format=json&q=query
  # - Categories: general, images, videos, news, science, it, files, music, map
  # - Site search: site:example.com query
  # - Time ranges: day, week, month, year
  #
  # Available Skills:
  # - mypares/agent-skills@searxng-search (271 installs)
  # - sundial-org/awesome-openclaw-skills@searxng (55 installs)
}
