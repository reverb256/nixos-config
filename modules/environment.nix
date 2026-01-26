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
      PATH = "$HOME/.local/bin:$PATH";

       # NVIDIA environment variables
       __GL_SYNC_TO_VBLANK = "0";
       __GL_SHADER_DISK_CACHE = "1";
       __GL_SHADER_DISK_CACHE_PATH = "/tmp/nvidia-shader-cache";
       
       # NEW: Enhanced NVIDIA Wayland support
       "WLR_DRM_NO_MODIFIERS" = "1";
       "NVD_BACKEND" = "direct";
       "__NV_PRIME_RENDER_OFFLOAD" = "1";
       "__NV_PRIME_RENDER_OFFLOAD_PROVIDER" = "nvidia";

      # DLSS and ray tracing optimizations
      NVDX_GL_COMPUTE_SHADER_STORAGE_IMAGE_EXTENDED = "1";
      NVDX_GL_SHADER_STORAGE_IMAGE_ATOMIC = "1";

      # Low latency gaming
      NVDX_INTEROP_FLIPABLE = "0";
      NVDX_INTEROP_BYTE_ADDRESSABLE = "1";

       # VR optimizations
       NVDX_INTEROP_DX_INTEROP2 = "1";

       # CUDA and NVENC optimizations
       CUDA_VISIBLE_DEVICES = "all";
       
        # NEW: CUDA environment
        "CUDA_HOME" = "/run/current-system/sw/lib";
        "LD_LIBRARY_PATH" = lib.mkForce "/run/current-system/sw/lib";

       # RTX 3090 specific encoding optimizations
       NV_ENC_ENABLE_PRESET_P7 = "1"; # High quality preset for streaming
       NV_ENC_ENABLE_PRESET_P1 = "1"; # Low latency preset for gaming

       # NVENC specific optimizations
       NVDX_Capture_Vulkan_Enable = "1";
       NVDX_Capture_Enable = "1";
       NVDX_Encoder_Enable = "1";
       NVDX_Vulkan_Enable = "1";
       __EGL_VENDOR_LIBRARY_FILENAMES = "/usr/share/glvnd/egl_vendor.d/10_nvidia.json";

      # Gaming and Wayland
      GBM_BACKEND = "nvidia-drm";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      WLR_NO_HARDWARE_CURSORS = "1";
      WLR_EGL_NO_MODIFIERS = "1";
      STEAM_RUNTIME = "1";
      NIXOS_OZONE_WL = "1";

      # DXVK for DirectX to Vulkan translation (AAGL games)
      DXVK_CONFIG_FILE = "/home/j_kro/.config/dxvk/dxvk.conf";
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

      # Locale settings for Wine/AAGL compatibility (fixes keyboard input issues)
      LANG = lib.mkForce "en_CA.UTF-8";
      LC_ALL = lib.mkForce "en_CA.UTF-8";
      LC_CTYPE = lib.mkForce "en_CA.UTF-8"; # Force CTYPE for input handling
      LC_NUMERIC = lib.mkForce "en_CA.UTF-8";
      LC_TIME = lib.mkForce "en_CA.UTF-8";
      LC_COLLATE = lib.mkForce "en_CA.UTF-8";
      LC_MONETARY = lib.mkForce "en_CA.UTF-8";
      LC_MESSAGES = lib.mkForce "en_CA.UTF-8";
      LC_PAPER = lib.mkForce "en_CA.UTF-8";
      LC_NAME = lib.mkForce "en_CA.UTF-8";
      LC_ADDRESS = lib.mkForce "en_CA.UTF-8";
      LC_TELEPHONE = lib.mkForce "en_CA.UTF-8";
      LC_MEASUREMENT = lib.mkForce "en_CA.UTF-8";
      LC_IDENTIFICATION = lib.mkForce "en_CA.UTF-8";

      # DualSense controller environment variables - DISABLED to prevent keyboard input conflicts
      SDL_JOYSTICK_HIDAPI_PS5 = "0"; # Disabled to prevent keyboard input conflicts with Wine
      SDL_JOYSTICK_HIDAPI_PS5_RUMBLE = "0"; # Disable rumble to prevent input conflicts

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
      __GL_VDPAU_CAPTURE_CLIENT_BUFFER = "0"; # Fix NVIDIA capture issues
      __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1"; # Improve shader cache performance
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
    };
}
