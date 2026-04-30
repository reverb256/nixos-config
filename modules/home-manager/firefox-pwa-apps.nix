{
  config,
  lib,
  pkgs,
  ...
}: let
  pwaApps = {
    "grok" = {
      name = "Grok";
      url = "https://grok.com";
      icon = "https://grok.com/favicon.ico";
      description = "xAI Grok - AI Assistant";
      categories = "AI;Chat;Network";
    };
    "chatgpt" = {
      name = "ChatGPT";
      url = "https://chatgpt.com";
      icon = "https://cdn.oaistatic.com/assets/apple-touch-icon-mz9nytnj.webp";
      description = "OpenAI ChatGPT - AI Assistant";
      categories = "AI;Chat;Network";
    };
  };

  installPwaScript = pkgs.writeShellScriptBin "install-pwa-apps" ''
    set -euo pipefail

    if ! command -v firefoxpwa &>/dev/null; then
      echo "firefoxpwa not found in PATH"
      exit 1
    fi

    if ! firefoxpwa runtime status 2>/dev/null | grep -q "installed"; then
      echo "Installing firefoxpwa runtime..."
      firefoxpwa runtime install --silent 2>/dev/null || true
    fi

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (id: app: ''
        if firefoxpwa site list 2>/dev/null | grep -q "^${id}$"; then
          echo "PWA ${id} already installed"
        else
          echo "Installing PWA: ${app.name} (${app.url})"
          firefoxpwa site install \
            --document-url "${app.url}" \
            --name "${app.name}" \
            --description "${app.description}" \
            --categories "${app.categories}" \
            --icon-url "${app.icon}" \
            --launch-now=false \
            "${app.url}" 2>/dev/null || echo "Note: ${id} may need manual install via browser extension"
        fi
      '')
      pwaApps)}

    echo "PWA installation check complete"
  '';
in {
  home.packages = with pkgs; [
    firefoxpwa
    installPwaScript
  ];

  home.activation.installPwaApps = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${installPwaScript}/bin/install-pwa-apps 2>/dev/null || true &
  '';

  xdg.dataFile =
    lib.mapAttrs' (id: app: {
      name = "applications/pwa-${id}.desktop";
      value.text = ''
        [Desktop Entry]
        Version=1.0
        Name=${app.name}
        Comment=${app.description}
        Exec=firefoxpwa site launch ${id}
        Icon=pwa-${id}
        Terminal=false
        Type=Application
        Categories=${app.categories}
        StartupWMClass=${app.name}
        MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
      '';
    })
    pwaApps;
}
