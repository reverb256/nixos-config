{ config, pkgs, lib, ... }:

let
  cfg = config.programs.firefoxpwa;
  enabledApps = {
    grok = "https://grok.com";
    chatgpt = "https://chatgpt.com";
  };
in
{
  config = lib.mkIf cfg.enable {
    # Install PWA apps on first login
    home.activation.installFirefoxPWA = lib.mkIf (!config.wayland.windowManager.niri.enable) ''
      if ! command -v firefoxpwa &>/dev/null; then
        echo "firefoxpwa not found in PATH"
        exit 0
      fi

      if ! firefoxpwa runtime status 2>/dev/null | grep -q "installed"; then
        echo "Installing firefoxpwa runtime..."
        firefoxpwa runtime install --silent 2>/dev/null || true
      fi

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (id: url: ''
        if firefoxpwa site list 2>/dev/null | grep -q "^${id}$"; then
          echo "PWA ${id} already installed"
        else
          echo "Installing PWA ${id}..."
          firefoxpwa site install \
            --name "${id}" \
            --id "${id}" \
            "${url}" 2>/dev/null || true
        fi
      '') enabledApps)}
    '';

    # Create desktop entries for PWA apps
    xdg.dataFile."applications" = lib.mkIf config.wayland.windowManager.niri.enable (
      lib.mapAttrs' (id: url: lib.nameValuePair "${id}.desktop" (
        pkgs.writeText "${id}.desktop" ''
          [Desktop Entry]
          Name=${lib.strings.toUpper (builtins.substring 0 1 id) + builtins.substring 1 (-1) id}
          Exec=firefoxpwa site launch ${id}
          Icon=firefox
          Terminal=false
          Type=Application
          Categories=Network;WebBrowser;
        ''
      ))
    ) enabledApps;
  };
}
