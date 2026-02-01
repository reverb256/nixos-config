{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  # ============================================================================
  # FLATPAK - Declarative configuration with Flathub integration
  # ============================================================================

  # Enable Flatpak support using the standard NixOS module
  services.flatpak.enable = true;

  # Enable Flatpak PolicyKit rules to fix permissions
  services.flatpak.polkit.enable = true;
  services.flatpak.polkit.allowAppstreamOperations = true;
  services.flatpak.polkit.allowUserOperations = true;

  # ============================================================================
  # DECLARATIVE REMOTES - Ensure Flathub is always configured
  # ============================================================================
  system.activationScripts.flatpak-remotes = lib.stringAfter ["usrbinenv"] ''
    # Add Flathub remotes declaratively (idempotent)
    ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system flathub-beta https://flathub.org/beta-repo/flathub-beta.flatpakrepo 2>/dev/null || true
  '';

  # ============================================================================
  # FLATPAK OVERRIDES - Better Wayland, theming, and Steam integration
  # ============================================================================
  # Note: Using activation scripts since services.flatpak.overrides doesn't exist
  system.activationScripts.flatpak-overrides = lib.stringAfter ["flatpak-remotes"] ''
        # Create global overrides for all flatpaks
        mkdir -p /var/lib/flatpak/overrides

        # Global override - Comprehensive socket and filesystem access
        cat > /var/lib/flatpak/overrides/global << 'EOF'
    [Context]
    # Socket access - comprehensive for all app types
    sockets=wayland;x11;pulseaudio;session-bus;system-bus;ssh-auth;pcsc;cups;gpg-agent;

    # Filesystem access - common user directories
    filesystems=xdg-download;xdg-documents;xdg-pictures;xdg-music;xdg-videos;xdg-desktop;xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro;xdg-config/Kvantum:ro;xdg-config/qt5ct:ro;xdg-config/qt6ct:ro;

    # Device access - needed for GPU acceleration, controllers, etc.
    devices=dri;shm;all;

    # Shared resources
    shared=network;ipc;

    # Features
    features=bluetooth;canbus;inhibit;multiarch;devel;

    [Environment]
    # Theming
    XCURSOR_PATH=/run/host/user-share/icons:/run/host/share/icons
    GTK_THEME=Breeze
    QT_QPA_PLATFORMTHEME=kde
    QT_STYLE_OVERRIDE=Breeze

    # Wayland by default, but allow X11 fallback
    SDL_VIDEODRIVER=wayland
    QT_QPA_PLATFORM=wayland
    GDK_BACKEND=wayland

    # Fix for NVIDIA + Flatpak
    __GLX_VENDOR_LIBRARY_NAME=nvidia
    EOF

        # Steam override - Additional permissions for gaming
        cat > /var/lib/flatpak/overrides/com.valvesoftware.Steam << 'EOF'
    [Context]
    sockets=wayland;x11;pulseaudio;system-talk-bus;session-talk-bus;
    filesystems=xdg-download;xdg-documents;xdg-pictures;xdg-music;xdg-videos;~/.local/share/Steam:create;~/.steam:create;/run/media:rw;/mnt:rw;
    devices=all;
    shared=network;

    [Environment]
    XCURSOR_PATH=/run/host/user-share/icons:/run/host/share/icons
    GTK_THEME=Breeze
    QT_QPA_PLATFORMTHEME=kde
    SDL_VIDEODRIVER=wayland
    EOF

        # Steam (native) override - Same permissions for native Steam if installed via flatpak
        cat > /var/lib/flatpak/overrides/com.valvesoftware.Steam.CompatibilityTool.Proton << 'EOF'
    [Context]
    filesystems=~/.local/share/Steam:rw;~/.steam:rw;
    EOF
  '';
}
