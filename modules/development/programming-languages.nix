{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    go
    gopls

    python313
    (python313.withPackages (
      ps:
        with ps; [
          pygobject3
          gobject-introspection
          pyqt6-sip
        ]
    ))

    uv

    nodejs
    pnpm

    bun

    lua
    lua-language-server

    zig
    zls

    numbat

    typst
  ];
}
