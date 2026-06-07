{ config, pkgs, lib, ... }:

let
  enabledApps = {
    grok = "https://grok.com";
    chatgpt = "https://chatgpt.com";
  };
in
{
  config = lib.mkIf config.programs.firefoxpwa.enable {
    home.packages = [ pkgs.firefoxpwa ];

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

      ${lib.concatStringsSep "\\n" (lib.mapAttrsToList (id: url: ''
        if firefoxpwa site list 2>/dev/null | grep -q "^${id}$"; then
          echo "PWA ${id} already installed"
        else
          echo "Installing PWA ${id}..."
          firefoxpwa site install \\
            --name "${id}" \\
            --id "${id}" \\
            "${url}" 2>/dev/null || true
        fi
      '') enabledApps)}
    '';

    # Create desktop entries for PWA apps
    xdg.dataFile."applications" = lib.mkIf config.wayland.windowManager.niri.enable (
      lib.mapAttrs' (id: url: lib.nameValuePair "${id}.desktop" (
        pkgs.makeDesktopItem {
          name = id;
          exec = "firefoxpwa site launch ${id}";
          icon = "firefox";
          desktopName = lib.strings.toUpper (builtins.substring 0 1 id) + builtins.substring 1 (-1) id;
          categories = ["Network" "WebBrowser"];
        }
      ))
    ) enabledApps;
  };
}
