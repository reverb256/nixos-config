{ config, lib, ... }: let
  inherit (lib) mkIf;
  cfg = config.stylix;
  enabled = cfg.enable or false;
in mkIf enabled (let
  # Stylix colors (without hashtag — "RRGGBB" format)
  raw = config.lib.stylix.colors;
  h = hex: "#" + hex;

  # ── Semantic base16 roles (Osaka Jade scheme) ──
  surface    = h raw.base00;  # deepest bg
  surfaceV   = h raw.base01;  # raised surface
  outline    = h raw.base03;  # borders / muted
  onSurface  = h raw.base05;  # primary text
  onSurfaceV = h raw.base04;  # medium-emphasis text
  primary    = h raw.base0D;  # main accent
  secondary  = h raw.base0B;  # secondary accent
  error      = h raw.base08;  # error red

  # ── niri color include (KDL) ────────────────────────────────
  # Replaces the frozen v4 noctalia.kdl snapshot. niri's main
  # config.kdl does not currently `include` this file, so also write
  # it where niri expects and document the include in niri-config.nix.
  niriKdl = ''
    layout {

        focus-ring {
            active-color   "${primary}"
            inactive-color "${surface}"
            urgent-color   "${error}"
        }

        border {
            active-color   "${primary}"
            inactive-color "${surface}"
            urgent-color   "${error}"
        }

        shadow {
            color "${surface}70"
        }

        tab-indicator {
            active-color   "${primary}"
            inactive-color "${secondary}"
            urgent-color   "${error}"
        }

        insert-hint {
            color "${primary}80"
        }
    }

    recent-windows {
        highlight {
            active-color "${primary}"
            urgent-color "${error}"
        }
    }
  '';

  # ── Telegram Desktop theme (base16 → tdesktop format) ───────
  telegramTheme = ''
    // Material You theme for Telegram Desktop
    // Generated from stylix base16 (LIVE — tracks the active scheme)

    COLOR_GRAY: ${secondary};
    COLOR_DARK: ${surfaceV};

    windowBg: ${surface}; // Main background
    windowFg: ${onSurface}; // Main text
    windowBgOver: ${surfaceV}; // Generic background on hover
    windowBgRipple: ${surfaceV}; // Ripple effect
    windowFgOver: ${onSurfaceV}; // Text on hover
    windowSubTextFg: ${secondary}; // Minor text
    windowSubTextFgOver: ${secondary}; // Minor text on hover
    windowBoldFg: ${onSurface}; // Bold text
    windowBoldFgOver: ${onSurfaceV}; // Bold text on hover
    windowBgActive: ${primary}; // Active items background
    windowFgActive: ${onSurface}; // Active items text
    windowActiveTextFg: ${primary}; // Active items text
    windowShadowFg: ${surface}; // Window shadow
    windowShadowFgFallback: ${surface}; // Fallback for shadow
    historyOutIconFg: ${primary};
    historyIconFgInverted: ${onSurface};

    msgServiceBg: ${secondary};
    msgServiceFg: ${onSurface};
    msgOutBg: ${secondary};
    msgOutBgSelected : ${secondary};
    msgOutServiceFg: ${onSurface};
    msgOutDateFg: ${onSurface};
    historySentIconFg: ${onSurface};
    msgOutDateFgSelected: ${onSurface};
    msgDateImgFg: ${onSurface};
    dialogsSentIconFg: ${primary};
    dialogsSentIconFgOver: ${primary};
    dialogsOnlineBadgeFg: ${primary};

    shadowFg: ${surface}; // General shadow
    slideFadeOutBg: ${surface};
    slideFadeOutShadowFg: ${surface};

    imageBg: ${surface};
    imageBgTransparent: ${surface};

    activeButtonBg: ${primary}; // Active button background
    activeButtonBgOver: ${secondary}; // Active button hover background
    activeButtonBgRipple: ${onSurface}; // Active button ripple
    activeButtonFg: ${onSurface}; // Active button text
    activeButtonFgOver: ${onSurface}; // Active button hover text
    activeButtonSecondaryFg: ${onSurface}; // Active button secondary text
    activeButtonSecondaryFgOver: ${onSurface}; // Active button secondary hover text
    activeLineFg: ${onSurface};
    dialogsBgActive: ${primary};

    lightButtonBg: ${surface}; // Light button background
    lightButtonBgOver: ${surfaceV}; // Light button hover background
    lightButtonBgRipple: ${primary}; // Light button ripple
    lightButtonFg: ${onSurface}; // Light button text
    lightButtonFgOver: ${onSurfaceV}; // Light button hover text

    attentionButtonFg: ${error};
    attentionButtonFgOver: ${error};
    attentionButtonBgOver: ${error};
    attentionButtonBgRipple: ${onSurface};

    outlineButtonBg: ${surface}; // Outline button background
    outlineButtonBgOver: ${surfaceV}; // Outline button hover background
    outlineButtonOutlineFg: ${primary}; // Outline button color
    outlineButtonBgRipple: ${primary}; // Outline button ripple

    menuBg: ${surface};
    menuBgOver: ${surfaceV};
    menuBgRipple: ${primary};
    menuIconFg: ${onSurface};
    menuIconFgOver: ${onSurfaceV};
    menuSubmenuArrowFg: ${secondary};
    menuFgDisabled: ${secondary};
    menuSeparatorFg: ${secondary};

    scrollBarBg: ${primary}40; // Scroll bar background (40% opacity)
    scrollBarBgOver: ${primary}60; // Scroll bar hover background (60% opacity)
    scrollBg: ${surfaceV}40; // Scroll bar track (40% opacity)
    scrollBgOver: ${surfaceV}60; // Scroll bar track on hover (60% opacity)

    smallCloseIconFg: ${secondary};
    smallCloseIconFgOver: ${onSurfaceV};

    radialFg: ${primary};
    radialBg: ${surface};

    placeholderFg: ${secondary}; // Placeholder text
    placeholderFgActive: ${primary}; // Active placeholder text
    inputBorderFg: ${secondary}; // Input border
    filterInputBorderFg: ${secondary}; // Search input border
    filterInputInactiveBg: ${surface}; // Inactive search input background
    checkboxFg: ${primary}; // Checkbox color

    titleBg: ${surface}; // Window title background
    titleShadow: ${surface};
    titleButtonFg: ${onSurface}; // Title button color
    titleButtonBgOver: ${surfaceV}; // Title button hover background
    titleButtonFgOver: ${onSurfaceV}; // Title button hover color
    titleButtonCloseBgOver: ${error};
    titleButtonCloseFgOver: ${onSurface};
    titleFgActive: ${onSurface}; // Active title text
    titleFg: ${onSurface}; // Inactive title text

    trayCounterBg: ${error}; // Tray counter background
    trayCounterBgMute: ${secondary}; // Muted tray counter background
    trayCounterFg: ${onSurface}; // Tray counter text
    trayCounterBgMacInvert: ${error}; // Mac tray counter
    trayCounterFgMacInvert: ${onSurface}; // Mac tray counter text

    layerBg: ${surface}99; // Layer background (60% opacity)

    cancelIconFg: ${error}; // Cancel icon
    cancelIconFgOver: ${error}; // Cancel icon on hover

    boxBg: ${surface}; // Box background
    boxTextFg: ${onSurface}; // Box text
    boxTextFgGood: ${primary}; // Box good text
    boxTextFgError: ${error}; // Box error text
    boxTitleFg: ${onSurface}; // Box title text
    boxSearchBg: ${surface}; // Box search field background
    boxSearchCancelIconFg: ${error}; // Box search cancel icon
    boxSearchCancelIconFgOver: ${error}; // Box search cancel icon on hover

    contactsBg: ${surface}; // Contacts background
    contactsBgOver: ${surfaceV}; // Contacts background on hover
    contactsNameFg: ${onSurface}; // Contact name
    contactsStatusFg: ${secondary}; // Contact status
    contactsStatusFgOver: ${onSurfaceV}; // Contact status on hover
    contactsStatusFgOnline: ${primary}; // Online contact status

    photoCropFadeBg: ${surface}cc; // Photo crop fade background
    photoCropPointFg: ${primary}; // Photo crop points

    chat_inBubbleSelected: ${surfaceV}; // inbox selected chat background
    chat_outBubbleSelected: ${surfaceV}; // outbox selected chat background
  '';
in {
  # ── niri color include (base16-driven) ────────────────────────
  xdg.configFile."niri/noctalia.kdl".text = niriKdl;

  # ── Telegram Desktop theme (base16-driven) ───────────────────
  xdg.configFile."telegram-desktop/themes/stylix.tdesktop-theme".text = telegramTheme;

  # ── Remove stale "noctalia.*" theme snapshots that bypass stylix ──
  # 2026-07-15: the v4→v5 migration wrote frozen noctalia.* theme files
  # (alacritty themes, gtk css, btop theme, qt colors, niri kdl, telegram
  # theme, scroll config) that hardcode old colors and shadow stylix's
  # live Osaka Jade base16. These are regenerated by stylix/HM where a
  # target exists, or by the bridges above. Delete the orphans at switch
  # so Osaka Jade is the single source of truth everywhere.
  home.activation.removeStaleNoctaliaThemes = ''
    for f in \
      "$HOME/.config/alacritty/themes/noctalia.toml" \
      "$HOME/.config/gtk-3.0/noctalia.css" \
      "$HOME/.config/gtk-4.0/noctalia.css" \
      "$HOME/.config/qt5ct/colors/noctalia.conf" \
      "$HOME/.config/qt6ct/colors/noctalia.conf" \
      "$HOME/.config/scroll/noctalia" \
      "$HOME/.config/btop/themes/noctalia.theme" \
      "$HOME/.config/telegram-desktop/themes/stylix.tdesktop-theme" ; do
      if [ -e "$f" ]; then
        rm -f "$f"
      fi
    done
  '';

  # ── Remove stale Kvantum config ──────────────────────────────────────
  # 2026-07-15: kvantum removed from config (QT_STYLE_OVERRIDE=kvantum
  # dropped from env-vars; stylix's KDE+Qt targets own Qt theming).
  # A prior home-manager generation left a stale ~/.config/Kvantum/ symlink
  # (kvantum.kvconfig -> <hm-files>/.config/Kvantum/...). With no
  # active declaration it is never recreated, but lingers until explicitly
  # cleaned. Delete the orphan dir at switch so nothing points at it.
  home.activation.removeStaleKvantum = ''
    if [ -e "$HOME/.config/Kvantum" ]; then
      rm -rf "$HOME/.config/Kvantum"
    fi
  '';
})
