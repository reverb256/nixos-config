# Helix desktop entry with explicit dev MIME associations.
#
# Background: Home-Manager's xdg.mimeApps is STRICT — it only writes a
# Default Applications / Added Associations entry when the target .desktop's
# own MimeType= line includes that type (freedesktop "a default must be
# associated" rule). The upstream Helix.desktop only declares
# text/plain + application/x-shellscript, so defaults for text/markdown,
# application/json, text/csv, application/toml, application/x-yaml, text/x-log
# were silently pruned.
#
# This module declares a Helix desktop entry (Exec=hx %F) that lists the full
# dev MimeType set, so mime-apps.nix can legitimately route those types to
# Helix. The binary (hx) comes from pkgs.helix (already in home.packages via
# desktop-utilities.nix). We do NOT set Terminal=true because hx is launched
# by the DE/file-manager into an existing terminal; if a standalone launch is
# needed the DE opens it in a terminal automatically for %F text files.
{ config, pkgs, lib, ... }:

let
  helixBin = lib.getExe pkgs.helix;
in
{
  xdg.desktopEntries.helix-dev = {
    name = "Helix";
    genericName = "Text Editor";
    comment = "A post-modern modal text editor (hx)";
    exec = "${helixBin} %F";
    terminal = false;
    type = "Application";
    categories = [ "Development" "Utility" "TextEditor" ];
    mimeType = [
      "text/plain"
      "text/markdown"
      "text/csv"
      "text/x-log"
      "application/json"
      "application/toml"
      "application/x-yaml"
      "application/x-shellscript"
      "text/x-script"
      "text/x-makefile"
      "text/x-c"
      "text/x-c++"
      "text/x-c++src"
      "text/x-c++hdr"
      "text/x-chdr"
      "text/x-csrc"
      "text/x-java"
      "text/x-pascal"
      "text/x-tcl"
      "text/x-tex"
      "text/x-moc"
      "text/x-english"
    ];
  };
}
