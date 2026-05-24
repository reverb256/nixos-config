# Desktop & Terminal Stack Polish — Implementation Plan

> **⚠️ STALE (20 days old, last verified 2026-05-03)** — Verify against current cluster state before following.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Polish the NixOS desktop/terminal stack with Stylix deep integration, Fish abbreviations, declarative git/tmux/lazygit, mimetype associations, and Omarchy feature parity.

**Architecture:** All changes are NixOS home-manager modules. Pattern: create/edit `.nix` module → register in `home-manager.nix` imports → rebuild → verify. No runtime tests — `nixos-rebuild switch` is the test.

**Tech Stack:** NixOS flakes, home-manager, Stylix, Fish, Alacritty, Starship, git, tmux, lazygit

---

## Phase 1: Bug Fixes & Quick Wins

### Task 1: Fix cursor conflict in icon-theme.nix

**Files:**
- Modify: `/etc/nixos/modules/home-manager/icon-theme.nix`

**Step 1: Edit icon-theme.nix to remove cursor lines**

Remove `cursor-theme = "Adwaita"` and `cursor-size = 24` from dconf settings. Stylix now owns cursor theming via `stylix.cursor` in `stylix.nix`.

Change:
```nix
dconf.settings."org/gnome/desktop/interface" = {
  icon-theme = "Papirus-Dark";
  cursor-theme = "Adwaita";
  cursor-size = 24;
  color-scheme = "prefer-dark";
};
```
To:
```nix
dconf.settings."org/gnome/desktop/interface" = {
  icon-theme = "Papirus-Dark";
  color-scheme = "prefer-dark";
};
```

**Step 2: Rebuild and verify**

Run: `sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos`
Expected: Successful rebuild, cursor remains Bibata-Modern-Ice (from Stylix)

**Step 3: Verify cursor is consistent**

Run: `gsettings get org.gnome.desktop.interface cursor-theme`
Expected: `Bibata-Modern-Ice` (or the Stylix-configured cursor)

**Step 4: Commit**

```bash
cd /etc/nixos && git add modules/home-manager/icon-theme.nix
git commit -m "fix: remove cursor-theme from dconf, let Stylix own cursor theming"
```

---

### Task 2: Verify BAT theme via Stylix

**Files:**
- No file changes expected

**Step 1: Check if Stylix auto-themes bat**

Run: `bat --theme`
Expected: A theme name (e.g., `base16` or `base16-stylix`). If empty, Stylix's bat target needs enabling.

**Step 2: If bat theme not set, add to home-manager.nix**

Add to `modules/system/home-manager.nix` in the `users.j_kro` block:
```nix
home.sessionVariables.BAT_THEME = "base16";
```

**Step 3: Rebuild and test**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: `bat ~/.config/fish/config.fish` — should show syntax-highlighted output with Nord colors.

**Step 4: Commit (only if changes were needed)**

```bash
git add modules/system/home-manager.nix
git commit -m "feat: set BAT_THEME to base16 for Nord-colored output"
```

---

### Task 3: Audit file watchers

**Files:**
- Possibly modify: an existing sysctl module or create a new one

**Step 1: Check current max_user_watches**

Run: `cat /proc/sys/fs/inotify/max_user_watches`
Expected: A number >= 524288. If 8192 (default), needs increasing.

**Step 2: If needed, check if any existing module sets it**

Run: `grep -r "max_user_watches" /etc/nixos/`

**Step 3: If not set, add to appropriate module**

Find the right sysctl module (e.g., in `modules/system/` or add to `modules/common-host-defaults.nix`):
```nix
boot.kernel.sysctl."fs.inotify.max_user_watches" = 524288;
```

**Step 4: Rebuild and verify**

Run: `cat /proc/sys/fs/inotify/max_user_watches` — should be 524288.

**Step 5: Commit**

```bash
git commit -m "feat: increase fs.inotify.max_user_watches for desktop workloads"
```

---

## Phase 2: Terminal & CLI

### Task 4: Convert Fish aliases to abbreviations

**Files:**
- Modify: `/etc/nixos/modules/home-manager/fish.nix`

**Step 1: Read current fish.nix**

Read the file. Identify all `alias` lines in `interactiveShellInit`.

**Step 2: Convert git aliases to shellAbbrs**

Move these aliases out of `interactiveShellInit` and into `programs.fish.shellAbbrs`:

```nix
shellAbbrs = {
  # Git
  gs = "git status";
  ga = "git add";
  gc = "git commit";
  gp = "git push";
  gl = "git log --oneline --graph --decorate --all";
  gd = "git diff";
  gds = "git diff --staged";

  # NixOS
  nswitch = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos";
  nswitchu = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos --upgrade";
  ntest = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh test --flake /etc/nixos";
  nconf = "nvim /etc/nixos/flake.nix";
  fconf = "nvim ~/.config/fish/config.fish";
  nclean = "sudo nix-collect-garbage --delete-older-than 14d";
  ngo = "sudo nix-collect-garbage --delete-old";
  noptimise = "nix-store --optimise";
  nverify = "nix-store --verify";
  nrepair = "nix-store --repair";
  nixos = "cd /etc/nixos";
  store = "cd /nix/store";
  conf = "cd ~/.config";
  nq = "nix-env -qaP";
  nsearch = "nix search nixpkgs";

  # Navigation
  ".." = "cd ..";
  "..." = "cd ../..";
  "...." = "cd ../../..";

  # Quick commands
  sysinfo = "fastfetch";
  neofetch = "fastfetch";

  # Wayland screenshots
  swl = "grim - | wl-copy";
  killhypr = "pkill Hyprland";
  restartwaybar = "pkill waybar; waybar &";
};
```

Keep as `alias` (not abbr) for tool replacements where you want the short form:
```nix
# These stay as aliases — you type "ll" and want it to stay "ll"
alias ll "eza -lh --group-directories-first --icons=auto"
alias la "eza -la --group-directories-first --icons=auto"
alias l "eza --group-directories-first --icons=auto"
alias lt "eza --tree --level=2 --long --icons"
alias cat "bat --paging=never"
alias top "btop"
alias du "dust"
alias df "dufs"
```

**Step 3: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: Open new fish shell. Type `gs` then space — should expand to `git status` inline.

**Step 4: Commit**

```bash
git add modules/home-manager/fish.nix
git commit -m "refactor: convert Fish aliases to abbreviations for inline expansion"
```

---

### Task 5: Add fzf Fish integration

**Files:**
- Modify: `/etc/nixos/modules/home-manager/fish.nix`

**Step 1: Add fzf integration to interactiveShellInit**

Add to the end of `interactiveShellInit`:
```fish
fzf --fish | source
```

**Step 2: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: In fish, press `Ctrl+R` — should show fuzzy history search.
Test: Press `Ctrl+T` — should show fuzzy file finder.

**Step 3: Commit**

```bash
git add modules/home-manager/fish.nix
git commit -m "feat: add fzf key bindings (Ctrl+R, Ctrl+T) to Fish shell"
```

---

### Task 6: Create declarative git.nix

**Files:**
- Create: `/etc/nixos/modules/home-manager/git.nix`
- Modify: `/etc/nixos/modules/system/home-manager.nix` (add import)

**Step 1: Get current git config**

Run: `git config --global --list 2>/dev/null` to see any existing user config.

**Step 2: Create git.nix**

```nix
{ pkgs, ... }:
let
  userName = "j_kro";  # UPDATE with actual name
  userEmail = "j_kro@users.noreply.github.com";  # UPDATE with actual email
in {
  programs.git = {
    enable = true;
    inherit userName userEmail;

    delta = {
      enable = true;
      options = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
      };
    };

    lfs.enable = true;

    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
      rerere.enabled = true;
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      merge.conflictstyle = "diff3";
    };
  };
}
```

**Step 3: Register in home-manager.nix**

Add `../../modules/home-manager/git.nix` to the imports list in `modules/system/home-manager.nix`.

**Step 4: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: `git config --global user.name` — should return the configured name.
Test: `git config --global core.pager` — should return `delta`.

**Step 5: Commit**

```bash
git add modules/home-manager/git.nix modules/system/home-manager.nix
git commit -m "feat: declarative git config with delta pager via home-manager"
```

---

### Task 7: Create tmux.nix

**Files:**
- Create: `/etc/nixos/modules/home-manager/tmux.nix`
- Modify: `/etc/nixos/modules/system/home-manager.nix` (add import)
- Modify: `/etc/nixos/modules/system/system-packages.nix` (remove tmux)

**Step 1: Create tmux.nix**

```nix
{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    mouse = true;
    prefix = "C-a";
    baseIndex = 1;
    keyMode = "vi";
    terminal = "tmux-256color";
    extraConfig = ''
      set -ga terminal-overrides ",*256col*:Tc"
      set -g renumber-windows on
      set -g escape-time 0
      set -g history-limit 50000
    '';
  };
}
```

**Step 2: Register in home-manager.nix**

Add `../../modules/home-manager/tmux.nix` to imports.

**Step 3: Remove tmux from system-packages.nix**

Remove `tmux` from the system packages list since home-manager now manages it.

**Step 4: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: `tmux` — should start with mouse support, C-a prefix, vi key mode.

**Step 5: Commit**

```bash
git add modules/home-manager/tmux.nix modules/system/home-manager.nix modules/system/system-packages.nix
git commit -m "feat: declarative tmux config via home-manager with vi mode and mouse"
```

---

### Task 8: Create lazygit.nix

**Files:**
- Create: `/etc/nixos/modules/home-manager/lazygit.nix`
- Modify: `/etc/nixos/modules/system/home-manager.nix` (add import)

**Step 1: Create lazygit.nix**

```nix
{ config, ... }:
{
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        theme = {
          activeBorderColor = [ "cyan" "bold" ];
          cherryPickedCommitBgStyle = [ "cyan" ];
          cherryPickedCommitFgStyle = [ "blue" ];
          unstagedChangesStyle = [ "red" ];
          defaultFgColor = [ "default" ];
        };
        showIcons = true;
      };
      git = {
        paging = {
          pager = "delta --dark --paging=never";
        };
        autoFetch = true;
        autoStageResolvedConflicts = true;
      };
    };
  };
}
```

**Step 2: Register in home-manager.nix**

Add `../../modules/home-manager/lazygit.nix` to imports.

**Step 3: Remove lazygit from system-packages if present**

Check if lazygit is in `modules/development/tools.nix` or `modules/system/system-packages.nix` — if so, remove it since home-manager now manages it.

**Step 4: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: `lazygit` — should open with Nord-ish colors and delta pager.

**Step 5: Commit**

```bash
git add modules/home-manager/lazygit.nix modules/system/home-manager.nix
git commit -m "feat: declarative lazygit config with delta integration via home-manager"
```

---

## Phase 3: Stylix Deep Integration

### Task 9: Starship via Stylix colors

**Files:**
- Modify: `/etc/nixos/modules/home-manager/starship.nix`

**Step 1: Read current starship.nix**

Note the per-host palettes and hardcoded colors.

**Step 2: Replace hardcoded colors with Stylix derivation**

```nix
{ config, ... }:
let
  c = config.lib.stylix.colors.withHashtag;
in {
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;

      character = {
        success_symbol = "[❯](bold ${c.base0D})";
        error_symbol = "[✗](bold ${c.base08})";
        vicmd_symbol = "[❮](bold ${c.base0B})";
      };

      format = "$hostname$git_branch$git_status$nix_shell$character";

      command_timeout = 10000;

      hostname = {
        ssh_only = false;
        format = "[$hostname]($style) ";
        style = "bold ${c.base0B}";
        disabled = false;
      };

      username = {
        show_always = false;
        disabled = true;
      };

      directory = {
        truncation_length = 3;
        truncation_symbol = ".../";
        repo_root_style = "bold ${c.base0D}";
        style = "bold ${c.base0D}";
        read_only = " 🔒";
      };

      git_branch = {
        format = "[$branch ]($style)";
        style = "italic ${c.base0D}";
        symbol = "";
      };

      git_status = {
        format = "[$all_status]($style) ";
        style = "${c.base0D}";
        ahead = "⇡";
        behind = "⇣";
        diverged = "⇕";
        conflicted = "✖";
        untracked = "•";
        modified = "▲";
        staged = "●";
        stashed = "≡";
      };

      nix_shell = {
        symbol = "";
        format = "[local ]($style)";
        style = "bold dimmed white";
        disabled = false;
        heuristic = true;
      };

      sudo.disabled = true;
      python.disabled = true;
      ruby.disabled = true;
      golang.disabled = true;
      rust.disabled = true;
      terraform.disabled = true;
      vagrant.disabled = true;
      conda.disabled = true;
      meson.disabled = true;
      spack.disabled = true;
      kubernetes.disabled = true;
      docker_context.disabled = true;
      nodejs.disabled = true;
    };
  };
}
```

**Step 3: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: Open new fish shell — prompt should look identical (Nord colors derived from Stylix).

**Step 4: Commit**

```bash
git add modules/home-manager/starship.nix
git commit -m "refactor: derive Starship colors from Stylix palette instead of hardcoded values"
```

---

### Task 10: Stylix colors in custom scripts

**Files:**
- Modify: `/etc/nixos/modules/home-manager/desktop-utilities.nix`

**Step 1: Add config parameter to desktop-utilities.nix**

Change the module function signature from `{ pkgs, config, ... }:` and use `config.lib.stylix.colors.withHashtag.base0E` for the slurp border color in the screenshot script.

Replace the hardcoded `8fbcbb` with `${config.lib.stylix.colors.withHashtag.base0E}` in:
```
${pkgs.slurp}/bin/slurp -b 00000066 -c 8fbcbb -s 00000000 -w 2
```
→
```
${pkgs.slurp}/bin/slurp -b 00000066 -c ${config.lib.stylix.colors.withHashtag.base0E} -s 00000000 -w 2
```

**Step 2: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: `screenshot region` — slurp border should be Nord cyan.

**Step 3: Commit**

```bash
git add modules/home-manager/desktop-utilities.nix
git commit -m "refactor: derive screenshot slurp color from Stylix palette"
```

---

### Task 11: Audit Stylix targets

**Step 1: Rebuild and check active targets**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`

**Step 2: Check which targets Stylix is theming**

Run: `nixos-option stylix.targets 2>/dev/null | head -50` or check home-manager options.

**Step 3: Verify key targets**

Check that these are active (autoEnable should handle most):
- `stylix.targets.fish.enable` — should be true
- `stylix.targets.alacritty.enable` — should be true
- `stylix.targets.bat.enable` — should be true
- `stylix.targets.gtk.enable` — should be true
- `stylix.targets.qt.enable` — should be true (via qt platform setting)

**Step 4: Document findings**

No commit needed — just note which targets are active for reference.

---

## Phase 4: Desktop Polish

### Task 12: Create centralized mime-apps.nix

**Files:**
- Create: `/etc/nixos/modules/home-manager/mime-apps.nix`
- Modify: `/etc/nixos/modules/system/home-manager.nix` (add import)
- Modify: `/etc/nixos/modules/home-manager/zen-browser.nix` (remove dup mimetypes)
- Modify: `/etc/nixos/modules/home-manager/obsidian.nix` (remove dup mimetypes)

**Step 1: Check which apps are available**

Run: `which imv mpv nvim` to verify these are installed.

**Step 2: Create mime-apps.nix**

```nix
{ lib, ... }:
{
  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    # Browser
    "text/html" = "zen-twilight.desktop";
    "x-scheme-handler/http" = "zen-twilight.desktop";
    "x-scheme-handler/https" = "zen-twilight.desktop";
    "x-scheme-handler/ftp" = "zen-twilight.desktop";
    "x-scheme-handler/about" = "zen-twilight.desktop";
    "x-scheme-handler/unknown" = "zen-twilight.desktop";
    "x-scheme-handler/mailto" = "zen-twilight.desktop";
    "x-scheme-handler/webcal" = "zen-twilight.desktop";

    # Images -> imv
    "image/png" = "imv.desktop";
    "image/jpeg" = "imv.desktop";
    "image/gif" = "imv.desktop";
    "image/webp" = "imv.desktop";
    "image/bmp" = "imv.desktop";
    "image/svg+xml" = "imv.desktop";
    "image/tiff" = "imv.desktop";

    # Video -> mpv
    "video/mp4" = "mpv.desktop";
    "video/x-matroska" = "mpv.desktop";
    "video/webm" = "mpv.desktop";
    "video/mpeg" = "mpv.desktop";
    "video/quicktime" = "mpv.desktop";
    "video/x-msvideo" = "mpv.desktop";

    # PDF -> Evince
    "application/pdf" = "org.gnome.Evince.desktop";

    # Directories -> Dolphin
    "inode/directory" = "org.kde.dolphin.desktop";
    "application/x-gnome-saved-search" = "org.kde.dolphin.desktop";
  };
}
```

**Step 3: Register in home-manager.nix**

Add `../../modules/home-manager/mime-apps.nix` to imports.

**Step 4: Remove duplicate mimetypes from zen-browser.nix**

Remove the `xdg.mimeApps.defaultApplications` block from `zen-browser.nix`. Keep only the `xdg.mimeApps.enable = true` if needed, or remove entirely since `mime-apps.nix` handles it.

**Step 5: Remove duplicate mimetypes from obsidian.nix**

Remove any `xdg.mimeApps.defaultApplications` from `obsidian.nix`.

**Step 6: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: `xdg-mime query default image/png` — should return `imv.desktop`.
Test: `xdg-mime query default video/mp4` — should return `mpv.desktop`.

**Step 7: Commit**

```bash
git add modules/home-manager/mime-apps.nix modules/system/home-manager.nix modules/home-manager/zen-browser.nix modules/home-manager/obsidian.nix
git commit -m "feat: centralized mimetype associations, deduplicate from browser/obsidian"
```

---

### Task 13: Create TUI desktop entries

**Files:**
- Create: `/etc/nixos/modules/home-manager/tui-apps.nix`
- Modify: `/etc/nixos/modules/system/home-manager.nix` (add import)

**Step 1: Create tui-apps.nix**

```nix
{ lib, pkgs, ... }:
let
  mkTuiEntry = { name, exec, icon ? "utilities-terminal", categories ? "System;ConsoleOnly;" }: {
    text = ''
      [Desktop Entry]
      Version=1.0
      Name=${name}
      Comment=Terminal: ${name}
      Exec=alacritty -e ${exec}
      Icon=${icon}
      Terminal=false
      Type=Application
      Categories=${categories}
    '';
  };
in {
  xdg.dataFile = {
    "applications/tui-lazydocker.desktop" = mkTuiEntry { name = "LazyDocker"; exec = "lazydocker"; icon = "docker"; categories = "System;ConsoleOnly;Docker;"; };
    "applications/tui-btop.desktop" = mkTuiEntry { name = "btop"; exec = "btop"; icon = "utilities-system-monitor"; };
    "applications/tui-lazygit.desktop" = mkTuiEntry { name = "LazyGit"; exec = "lazygit"; icon = "git"; categories = "Development;ConsoleOnly;"; };
    "applications/tui-dust.desktop" = mkTuiEntry { name = "Disk Usage"; exec = "dust"; icon = "folder"; };
  };
}
```

**Step 2: Register in home-manager.nix**

Add `../../modules/home-manager/tui-apps.nix` to imports.

**Step 3: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: Check if entries appear in app launcher: `ls ~/.local/share/applications/tui-*.desktop`

**Step 4: Commit**

```bash
git add modules/home-manager/tui-apps.nix modules/system/home-manager.nix
git commit -m "feat: TUI app desktop entries for lazydocker, btop, lazygit, dust"
```

---

### Task 14: Create EditorConfig

**Files:**
- Create: `/etc/nixos/modules/home-manager/editorconfig.nix`
- Modify: `/etc/nixos/modules/system/home-manager.nix` (add import)

**Step 1: Create editorconfig.nix**

```nix
{ ... }:
{
  editorconfig = {
    enable = true;
    settings = {
      "*" = {
        charset = "utf-8";
        end_of_line = "lf";
        insert_final_newline = true;
        trim_trailing_whitespace = true;
        indent_style = "space";
        indent_size = 2;
      };
      "*.py" = { indent_size = 4; };
      "Makefile" = { indent_style = "tab"; };
    };
  };
}
```

**Step 2: Register in home-manager.nix**

Add `../../modules/home-manager/editorconfig.nix` to imports.

**Step 3: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: `cat ~/.editorconfig` — should show the generated config.

**Step 4: Commit**

```bash
git add modules/home-manager/editorconfig.nix modules/system/home-manager.nix
git commit -m "feat: global editorconfig via home-manager"
```

---

### Task 15: GH CLI config

**Files:**
- Modify: `/etc/nixos/modules/home-manager/git.nix` (add gh config)

**Step 1: Add programs.gh to git.nix**

Add to the existing git.nix module:
```nix
programs.gh = {
  enable = true;
  settings = {
    git_protocol = "ssh";
    prompt = "enabled";
  };
};
```

**Step 2: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: `gh config get git_protocol` — should return `ssh`.

**Step 3: Commit**

```bash
git add modules/home-manager/git.nix
git commit -m "feat: declarative gh CLI config with SSH protocol"
```

---

## Phase 5: Omarchy Parity

### Task 16: Create theme switcher script

**Files:**
- Modify: `/etc/nixos/modules/home-manager/fish.nix` (add script package)
OR
- Modify: `/etc/nixos/modules/home-manager/desktop-utilities.nix` (add to home.packages)

**Step 1: Add theme-switch script**

Create as a writeShellScriptBin in an appropriate module:
```nix
theme-switch = pkgs.writeShellScriptBin "theme-switch" ''
  #!/usr/bin/env bash
  set -euo pipefail

  SCHEME_FILE="/etc/nixos/modules/desktop/stylix.nix"

  if [ "''${1:-}" = "list" ]; then
    echo "Available themes in base16-schemes:"
    nix eval --raw nixpkgs#base16-schemes 2>/dev/null | head -1 || \
      find /nix/store -maxdepth 3 -path '*/base16-schemes/share/themes/*.yaml' 2>/dev/null | \
      xargs -I{} basename {} .yaml | sort -u | head -50
    exit 0
  fi

  THEME="''${1:?Usage: theme-switch <theme-name> | theme-switch list}"

  if ! grep -q 'share/themes/.*\.yaml' "$SCHEME_FILE"; then
    echo "ERROR: Cannot find theme line in $SCHEME_FILE"
    exit 1
  fi

  sed -i "s|share/themes/.*\.yaml|share/themes/''${THEME}.yaml|" "$SCHEME_FILE"
  echo "Theme set to $THEME. Rebuilding..."
  sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos
'';
```

Add to `home.packages` in the chosen module.

**Step 2: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: `theme-switch list` — should show available themes.

**Step 3: Commit**

```bash
git commit -m "feat: add theme-switch helper for NixOS+Stylix theme changes"
```

---

### Task 17: Create fastfetch config

**Files:**
- Create: Add to `modules/home-manager/fish.nix` or a new file

**Step 1: Add fastfetch config**

Add to an appropriate module:
```nix
xdg.configFile."fastfetch/config.jsonc".text = builtins.toJSON {
  logo = { source = "nixos_small"; color = { }; };
  display = { separator = " → "; };
  modules = [
    "title"
    "separator"
    { type = "os"; format = "{3} {12}"; }
    "kernel"
    { type = "shell"; format = "{1} {2}"; }
    "terminal"
    "cpu"
    "gpu"
    "memory"
    { type = "disk"; folders = "/"; format = "{1} / {2} ({3})"; }
  ];
};
```

**Step 2: Rebuild and verify**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Test: `fastfetch` — should show clean system info with NixOS logo.

**Step 3: Commit**

```bash
git commit -m "feat: declarative fastfetch config via home-manager"
```

---

## Summary

| Phase | Tasks | New Files | Modified Files |
|-------|-------|-----------|----------------|
| 1: Quick wins | 3 | 0 | 1-2 |
| 2: Terminal CLI | 5 | 3 (git, tmux, lazygit) | 3 (fish, home-manager, system-packages) |
| 3: Stylix | 3 | 0 | 2 (starship, desktop-utilities) |
| 4: Desktop | 4 | 3 (mime-apps, tui-apps, editorconfig) | 4 (home-manager, zen-browser, obsidian, git) |
| 5: Omarchy | 2 | 0 | 1-2 |
| **Total** | **17** | **6** | **~13** |

**Estimated time**: 2-3 hours total across all phases.
