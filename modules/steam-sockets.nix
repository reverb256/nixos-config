# Steam Runtime Socket Services
# Provides essential socket services for Steam sandbox communication
{pkgs, ...}: {
  # ============================================================================
  # STEAM RUNTIME SOCKETS
  # ============================================================================

  # Steam user socket directory - automatically managed by systemd tmpfiles
  systemd.tmpfiles.rules = [
    "d /run/user/%i/steam 0700 %i %i"
    "d /run/user/%i/.cache/steam 0700 %i %i"
    "d /run/user/%i/tmux 0700 %i %i"
  ];
}
