{
  config,
  lib,
  ...
}: {
  # Centralized environment variables for consistency across the system
  environment.sessionVariables =
    {
      # Basic system variables
      EDITOR = "nvim";
      BROWSER = "zen";
      TERMINAL = "konsole";
      PAGER = "less";
      LESS = "-R --mouse --wheel-lines=3";

      # Path additions
      # Note: CUDA binaries are provided via environment.sessionVariables in host configs
      # through hardware.nvidia.package, not via /usr/local/cuda
      PATH = "$HOME/.local/bin:$PATH";

      # Gaming and Wayland
      NIXOS_OZONE_WL = "1";

      # DXVK for DirectX to Vulkan translation (AAGL games)
      DXVK_CONFIG_FILE = "$HOME/.config/dxvk/dxvk.conf";
      DXVK_LOG_LEVEL = "none";
      DXVK_HUD = "0";

      # KDE Plasma environment
      XDG_CURRENT_DESKTOP = "KDE";
      KDE_SESSION_VERSION = "6";
      QT_QPA_PLATFORMTHEME = "kde";
      QT_STYLE_OVERRIDE = "kvantum";

      # System tray and desktop integration
      XDG_SESSION_DESKTOP = "KDE";
      DESKTOP_SESSION = "plasma";
      KDE_FULL_SESSION = "true";

      # Locale settings for Wine/AAGL compatibility (modern NixOS approach)
      # Use NixOS's built-in locale management instead of manual force overrides
      # This allows the system to handle locale properly while maintaining compatibility

      # DualSense controller environment variables - ENABLED for native DualSense support in AAGL
      # Note: May cause conflicts with some Wine games, but required for native DualSense features
      SDL_JOYSTICK_HIDAPI_PS5 = "1"; # Enable native DualSense HIDAPI driver (gyro, haptics, adaptive triggers)
      SDL_JOYSTICK_HIDAPI_PS5_RUMBLE = "1"; # Enable rumble support

      # Wine hidraw support - ENABLED for proper keyboard input in Wine applications
      WINEHIDRAW = "1"; # Required for keyboard input in AAGL and other Wine apps

      # Wine input and Wayland compatibility
      WINEDEBUG = "-all"; # Reduce Wine debug output for better performance
      WINEPREFIX = "$HOME/.wine-aagl"; # Dedicated Wine prefix for AAGL
      WINEARCH = "win64"; # Use 64-bit Wine prefix
      WINEESYNC = "1"; # Enable esync for better performance
      WINE_FPS = "0"; # Disable FPS limiting
      WINE_DISABLE_BYPASS_HEAP_ALLOCATION_CHECKS = "1"; # Fix memory allocation issues

      # Wayland-compatible Wine input fixes (keep Wayland, don't force X11)
      # GDK_BACKEND = "wayland"; # Let Wine use Wayland when possible
      # QT_QPA_PLATFORM = "wayland"; # Let Qt use Wayland when possible
      SDL_VIDEODRIVER = "wayland"; # Prefer Wayland for SDL applications
      SDL_AUDIODRIVER = "pulseaudio"; # Use PulseAudio for audio

      # Wine keyboard and input fixes
      WINEDLLOVERRIDES = "mscoree,mshtml="; # Disable problematic DLLs

      # Wayland portal services for complete functionality (avoid duplicates)
      # XDG_CURRENT_DESKTOP and XDG_SESSION_DESKTOP already defined above
      XDG_DESKTOP_SESSION_ID = "1";
      # DESKTOP_SESSION and KDE_FULL_SESSION already defined above

      # Additional portal environment variables
      XDG_SESSION_CLASS = "user";
      XDG_SESSION_ID = "1";
    }
    // lib.optionalAttrs ((builtins.hasAttr "age" config) && (config.age.secrets ? "claude-api-key")) {
      # Enhanced Claude Code with MCP support - Multiple API providers
      ANTHROPIC_AUTH_TOKEN_FILE = config.age.secrets.claude-api-key.path;
      API_TIMEOUT_MS = "3000000";
      ANTHROPIC_BASE_URL = "https://vanchin.streamlake.ai/api/gateway/coding/kat-coder-pro-v1/claude-code-proxy";
      ANTHROPIC_MODEL = "kat-coder-pro-v1";
      ANTHROPIC_SMALL_FAST_MODEL = "kat-coder-pro-v1";
      ANTHROPIC_DEFAULT_SONNET_MODEL = "kat-coder-pro-v1";
      ANTHROPIC_DEFAULT_OPUS_MODEL = "kat-coder-pro-v1";
      ANTHROPIC_DEFAULT_HAIKU_MODEL = "kat-coder-pro-v1";

      # MCP Server Configuration
      MCP_SERVER_URL = "http://localhost:3000";
      MCP_ENABLED = "true";
      WEB_SEARCH_ENABLED = "true";

      # Multiple API provider support for redundancy
      OPENROUTER_API_KEY_FILE = config.age.secrets.openrouter-api-key.path or "";
      OPENAI_API_KEY_FILE = config.age.secrets.openai-api-key.path or "";
      ZHIPU_API_KEY_FILE = config.age.secrets.zhipu-api-key.path or "";
    }
    // lib.optionalAttrs ((builtins.hasAttr "age" config) && (config.age.secrets ? "cachix-token")) {
      # Cachix authentication token for authenticated cache operations
      CACHIX_AUTH_TOKEN_FILE = config.age.secrets.cachix-token.path;
    };
}
