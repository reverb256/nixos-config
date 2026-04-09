# Programming Languages Module
# Comprehensive language runtimes and package managers
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # ============================================================================
    # GO
    # ============================================================================
    go
    gopls # Go LSP

    # ============================================================================
    # PYTHON
    # ============================================================================
    python313
    # Python with GUI and system integration packages
    (python313.withPackages (
      ps:
        with ps; [
          pygobject3 # Python bindings for GObject
          gobject-introspection # GObject introspection
          pyqt6-sip # PyQt6 SIP bindings
        ]
    ))

    # uv - Ultra-fast Python package installer (replaces pip/poetry)
    uv

    # ============================================================================
    # JAVASCRIPT / TYPESCRIPT
    # ============================================================================
    nodePackages_latest.nodejs
    nodePackages_latest.pnpm

    # bun - Ultra-fast JavaScript runtime (Node.js alternative)
    bun

    # ============================================================================
    # SYSTEM / EMBEDDED LANGUAGES
    # ============================================================================
    lua # Lightweight scripting language
    lua-language-server # Lua LSP

    zig # Modern system programming language
    zls # Zig LSP

    # ============================================================================
    # CALCULATOR / MATH
    # ============================================================================
    numbat # Scientific calculator with unit handling

    # ============================================================================
    # MISCELLANEOUS
    # ============================================================================
    typst # Alternative to LaTeX
  ];
}
