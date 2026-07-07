{ config, lib, ... }:
let
  inherit (lib) mkIf;
  cfg = config.stylix;
  enabled = cfg.enable or false;
in mkIf enabled (let
  # Stylix colors (without hashtag — "RRGGBB" format)
  raw = config.lib.stylix.colors;
  # Format: prepend #
  h = hex: "#" + hex;

  # ── Material You palette from base16 ────────────────────────────
  # Maps base16 semantic slots to noctalia's Material You color roles
  dark = {
    mShadow        = h raw.base00;  # deepest bg / shadows
    mSurface       = h raw.base01;  # surface background
    mSurfaceVariant = h raw.base02; # variant surface
    mOutline       = h raw.base03;  # borders / outlines / muted
    mOnSurfaceVariant = h raw.base04; # text on variant (medium emphasis)
    mOnSurface     = h raw.base05;  # primary text
    mOnPrimary     = h raw.base07;  # text on accent (highest contrast)
    mOnSecondary   = h raw.base07;  # text on secondary
    mPrimary       = h raw.base0D;  # main accent (blue slot)
    mSecondary     = h raw.base0B;  # secondary (green slot)
    mTertiary      = h raw.base0A;  # tertiary (yellow slot)
    mError         = h raw.base08;  # error (red slot)
    mOnError       = h raw.base07;  # text on error
    mHover         = h raw.base09;  # hover state (orange slot)
    mOnHover       = h raw.base07;  # text on hover
    mOnTertiary    = h raw.base07;  # text on tertiary
  };

  # ── Terminal 16-color palette from base16 ───────────────────────
  # Standard base16 terminal mapping
  terminalDark = {
    cursorText   = h raw.base00;
    cursor       = h raw.base0D;  # accent-colored cursor
    foreground   = h raw.base05;
    background   = h raw.base00;
    selectionFg  = h raw.base05;
    selectionBg  = h raw.base02;
    normal = {
      black   = h raw.base00;
      red     = h raw.base08;
      green   = h raw.base0B;
      yellow  = h raw.base0A;
      blue    = h raw.base0D;
      magenta = h raw.base0E;
      cyan    = h raw.base0C;
      white   = h raw.base05;
    };
    bright = {
      black   = h raw.base03;
      red     = h raw.base08;
      green   = h raw.base0B;
      yellow  = h raw.base0A;
      blue    = h raw.base0D;
      magenta = h raw.base0E;
      cyan    = h raw.base0C;
      white   = h raw.base06;
    };
  };

  # ── Light mode (inverted) ──────────────────────────────────────
  # Swap surface ↔ text, keep accent colors
  light = {
    mShadow        = h raw.base07;
    mSurface       = h raw.base06;
    mSurfaceVariant = h raw.base05;
    mOutline       = h raw.base04;
    mOnSurfaceVariant = h raw.base02;
    mOnSurface     = h raw.base01;
    mOnPrimary     = h raw.base00;
    mOnSecondary   = h raw.base00;
    mPrimary       = h raw.base0D;  # same accent
    mSecondary     = h raw.base0B;
    mTertiary      = h raw.base0A;
    mError         = h raw.base08;
    mOnError       = h raw.base00;
    mHover         = h raw.base09;
    mOnHover       = h raw.base00;
    mOnTertiary    = h raw.base00;
  };

  terminalLight = {
    cursorText   = h raw.base07;
    cursor       = h raw.base0D;
    foreground   = h raw.base01;
    background   = h raw.base06;
    selectionFg  = h raw.base01;
    selectionBg  = h raw.base04;
    normal = {
      black   = h raw.base00;
      red     = h raw.base08;
      green   = h raw.base0B;
      yellow  = h raw.base0A;
      blue    = h raw.base0D;
      magenta = h raw.base0E;
      cyan    = h raw.base0C;
      white   = h raw.base05;
    };
    bright = {
      black   = h raw.base03;
      red     = h raw.base08;
      green   = h raw.base0B;
      yellow  = h raw.base0A;
      blue    = h raw.base0D;
      magenta = h raw.base0E;
      cyan    = h raw.base0C;
      white   = h raw.base04;
    };
  };

  # ── Full colorscheme JSON (dark + light + terminal) ────────────
  schemeJson = builtins.toJSON {
    dark = dark // { terminal = terminalDark; };
    light = light // { terminal = terminalLight; };
  };

  # ── Colors JSON (active palette — subset, no terminal/light) ───
  colorsJson = builtins.toJSON dark;

in {
  # ── Write full colorscheme for nocturnal ──────────────────────────
  xdg.configFile."noctalia/colorschemes/Stylix/Stylix.json" = {
    text = schemeJson;
    force = true;
  };

  # ── Write active palette (colors.json) ───────────────────────────
  xdg.configFile."noctalia/colors.json".text = colorsJson;

  # 2026-07-07: removed `home.activation.noctaliaStylix` entirely. v5
  # reads TOML only; the v4 hook ran `jq` against `settings.json` and
  # `pkill -USR1` for live reload -- both destructive against the v5
  # TOML loader. With the hook gone, no per-HM-switch activation entry
  # fires. User picks a colorscheme via the noctalia control center;
  # auto-injection from Stylix palettes is parked until the v5 TOML
  # schema is documented upstream.
})
