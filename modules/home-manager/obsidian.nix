{config, pkgs, ...}: let
  c = config.lib.stylix.colors;
  bg = "#" + c.base00;
  fg = "#" + c.base05;
  accent = "#" + c.base0D;
  selBg = "#" + c.base02;
  color1 = "#" + c.base08;
  color2 = "#" + c.base0B;
  color3 = "#" + c.base0A;
  color4 = "#" + c.base0D;
  color5 = "#" + c.base0E;
  color6 = "#" + c.base0C;
  color8 = "#" + c.base03;
in {
  home.packages = with pkgs; [obsidian];

  xdg.configFile."obsidian/themes/Stylix/theme.css".text = ''
    .theme-dark, .theme-light {
      --background-primary: ${bg};
      --background-primary-alt: ${bg};
      --background-secondary: ${bg};
      --background-secondary-alt: ${bg};
      --text-normal: ${fg};
      --text-selection: ${selBg};
      --background-modifier-border: ${color8};
      --text-title-h1: ${color1};
      --text-title-h2: ${color2};
      --text-title-h3: ${color3};
      --text-title-h4: ${color4};
      --text-title-h5: ${color5};
      --text-title-h6: ${color5};
      --text-link: ${color4};
      --text-accent: ${accent};
      --text-accent-hover: ${accent};
      --interactive-accent: ${accent};
      --interactive-accent-hover: ${accent};
      --text-muted: color-mix(in srgb, ${fg} 70%, transparent);
      --text-faint: color-mix(in srgb, ${fg} 55%, transparent);
      --code-normal: ${color6};
      --text-error: ${color1};
      --text-error-hover: ${color1};
      --text-success: ${color2};
      --tag-color: ${color6};
      --tag-background: ${color8};
      --graph-line: ${color8};
      --graph-node: ${accent};
      --graph-node-focused: ${color4};
      --graph-node-tag: ${color6};
      --graph-node-attachment: ${color2};
    }

    .cm-header-1, .markdown-rendered h1 { color: var(--text-title-h1); }
    .cm-header-2, .markdown-rendered h2 { color: var(--text-title-h2); }
    .cm-header-3, .markdown-rendered h3 { color: var(--text-title-h3); }
    .cm-header-4, .markdown-rendered h4 { color: var(--text-title-h4); }
    .cm-header-5, .markdown-rendered h5 { color: var(--text-title-h5); }
    .cm-header-6, .markdown-rendered h6 { color: var(--text-title-h6); }

    .markdown-rendered code { color: ${color6}; }
    .cm-s-obsidian span.cm-keyword { color: ${color1}; }
    .cm-s-obsidian span.cm-string { color: ${color2}; }
    .cm-s-obsidian span.cm-number { color: ${color3}; }
    .cm-s-obsidian span.cm-comment { color: ${color8}; }
    .cm-s-obsidian span.cm-operator { color: ${color4}; }
    .cm-s-obsidian span.cm-def { color: ${color4}; }

    .markdown-rendered a { color: var(--text-link); }
    .markdown-rendered blockquote { border-left-color: ${accent}; }

    .workspace-leaf.mod-active .workspace-leaf-header-title { color: var(--interactive-accent); }
    .nav-file-title.is-active { color: var(--interactive-accent); }
    .search-result-file-title { color: var(--interactive-accent); }
  '';

  xdg.configFile."obsidian/themes/Stylix/manifest.json".text = builtins.toJSON {
    name = "Stylix";
    version = "1.0.0";
    minAppVersion = "1.0.0";
    author = "NixOS";
  };

  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/obsidian" = ["obsidian.desktop"];
  };
}
