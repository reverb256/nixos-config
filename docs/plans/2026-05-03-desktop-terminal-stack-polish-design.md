# Desktop & Terminal Stack Polish — Full Enhancement Plan

**Date**: 2026-05-03
**Scope**: NixOS Stylix deep integration, terminal/CLI polish, desktop polish, dev workflow, system hardening, Omarchy feature parity
**Status**: Design complete, pending implementation

---

## Context

After comparing our NixOS + Stylix setup against Basecamp's Omarchy (Arch + Hyprland), we identified gaps across 6 categories. Our Stylix declarative approach is fundamentally more powerful than Omarchy's imperative template system, but we're not leveraging it fully.

Already completed: Alacritty enhancements (TERM, OSC52, font variants, keybinds) and Stylix cursor (Bibata-Modern-Ice).

---

## A. Stylix Deep Integration

### A1. Fix cursor conflict in icon-theme.nix [BUG FIX]
**File**: `modules/home-manager/icon-theme.nix`
**Problem**: Sets `cursor-theme = "Adwaita"` in dconf, which conflicts with new Stylix Bibata cursor.
**Action**: Remove cursor lines from dconf settings, let Stylix own cursor theming system-wide.

### A2. Stylix color derivation for Starship
**File**: `modules/home-manager/starship.nix`
**Current**: Per-host hardcoded color palettes (`zephyr`, `nexus`, `forge`, `sentry`).
**Action**: Replace hardcoded colors with `config.lib.stylix.colors` derivation. Keep per-host accent differentiation via host-specific overrides if desired.
**Example**:
```nix
{ config, ... }:
let
  c = config.lib.stylix.colors.withHashtag;
in {
  programs.starship.settings = {
    character.success_symbol = "[❯](bold ${c.base0D})";
    character.error_symbol = "[✗](bold ${c.base08})";
    git_branch.style = "italic ${c.base0D}";
  };
}
```

### A3. Stylix color derivation in custom scripts
**File**: `modules/home-manager/desktop-utilities.nix`
**Current**: Screenshot slurp border uses hardcoded `8fbcbb`.
**Action**: Accept a `config` arg and derive from `config.lib.stylix.colors.withHashtag.base0E` (Nord cyan equivalent).

### A4. Verify Stylix targets are activating
**Action**: After rebuild, audit active Stylix targets:
```bash
nixos-option stylix.targets 2>/dev/null | grep enable
```
Key targets to verify: `fish`, `alacritty`, `gtk`, `bat`, `fzf`, `git`, `tmux`, `btop`, `lazygit`, `waybar`

### A5. Stylix for swaylock (if used)
**Current**: swaylock installed but no Stylix target.
**Action**: Verify `stylix.targets.swaylock.enable` activates with autoEnable. If using swaylock, colors will be injected automatically.

---

## B. Terminal & CLI Polish

### B1. Convert Fish aliases to abbreviations
**File**: `modules/home-manager/fish.nix`
**Current**: All git/nix/nav aliases defined via `alias` in `interactiveShellInit`.
**Problem**: Fish aliases don't expand inline. Abbreviations show the expanded command before execution — better UX, easier to learn.
**Action**: Convert to `programs.fish.shellAbbrs`:
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
  # ... (full list)

  # Navigation
  ".." = "cd ..";
  "..." = "cd ../..";
  "...." = "cd ../../..";
};
```
Keep `alias` for tools that shouldn't expand (eza, bat, btop — where the alias IS the command you want to type).

### B2. BAT theme via Stylix
**Current**: `bat` installed, aliased to `cat`, but no `BAT_THEME` set.
**Action**: Stylix auto-themes bat with `stylix.targets.bat.enable` (on by default). Verify it works, or set explicitly:
```nix
home.sessionVariables.BAT_THEME = "base16";
```

### B3. fzf key bindings for Fish
**Current**: fzf installed but no Fish integration configured.
**Action**: Add fzf Fish integration via `interactiveShellInit`:
```nix
interactiveShellInit = ''
  # ... existing init ...
  fzf --fish | source
'';
```
This enables `Ctrl+R` (history search), `Ctrl+T` (file finder), `Alt+C` (cd into subdirs).

### B4. Declarative git config
**File**: NEW `modules/home-manager/git.nix`
**Current**: Git aliases in Fish only. No `programs.git` in home-manager.
**Action**: Create git home-manager module:
```nix
{ config, pkgs, ... }:
let
  userName = "j_kro";  # confirm actual name
  userEmail = "j_kro@users.noreply.github.com";  # confirm actual email
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
    };
  };
}
```
Register in `home-manager.nix` imports. Remove git aliases from Fish that overlap (keep abbreviations for convenience).

### B5. Tmux config via home-manager
**File**: NEW `modules/home-manager/tmux.nix`
**Current**: tmux installed as system package with zero config.
**Action**: Create minimal tmux home-manager module:
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
Remove tmux from system-packages.nix (home-manager manages it now).

### B6. Lazygit config via home-manager
**File**: NEW `modules/home-manager/lazygit.nix`
**Current**: lazygit installed as system package with zero config.
**Action**: Create lazygit module with Nord-themed colors:
```nix
{ config, ... }:
{
  programs.lazygit = {
    enable = true;
    settings = {
      gui.theme = {
        activeBorderColor = [ "cyan" "bold" ];
        cherryPickedCommitBgFormat = [ "cyan" ];
        cherryPickedCommitFgFormat = [ "blue" ];
        unstagedChangesFormat = [ "red" ];
      };
      git.paging = {
        pager = "delta --dark --paging=never";
      };
    };
  };
}
```

---

## C. Desktop Polish

### C1. Comprehensive mimetype associations
**File**: NEW `modules/home-manager/mime-apps.nix`
**Current**: Only browser/directory mimetypes set in `zen-browser.nix` and `obsidian.nix`.
**Action**: Create centralized mimetype module with full coverage (matching Omarchy parity):
```nix
xdg.mimeApps.defaultApplications = {
  # Images -> imv
  "image/png" = "imv.desktop";
  "image/jpeg" = "imv.desktop";
  "image/gif" = "imv.desktop";
  "image/webp" = "imv.desktop";
  "image/bmp" = "imv.desktop";
  "image/svg+xml" = "imv.desktop";

  # Video -> mpv
  "video/mp4" = "mpv.desktop";
  "video/x-matroska" = "mpv.desktop";
  "video/webm" = "mpv.desktop";
  "video/mpeg" = "mpv.desktop";

  # PDF -> Evince
  "application/pdf" = "org.gnome.Evince.desktop";

  # Text/code -> nvim (via terminal)
  "text/plain" = "nvim.desktop";
  "text/x-shellscript" = "nvim.desktop";
  "application/xml" = "nvim.desktop";

  # Directories -> Dolphin
  "inode/directory" = "org.kde.dolphin.desktop";
};
```
Remove duplicate mimetype settings from `zen-browser.nix` and `obsidian.nix`.

### C2. TUI desktop entries
**File**: NEW `modules/home-manager/tui-apps.nix`
**Action**: Create .desktop entries for TUI tools so they appear in app launcher (walker):
```nix
let
  mkTuiEntry = { name, exec, icon ? "utilities-terminal"; }: {
    "applications/tui-${name}.desktop" = {
      text = ''
        [Desktop Entry]
        Name=${name}
        Exec=alacritty -e ${exec}
        Icon=${icon}
        Terminal=false
        Type=Application
        Categories=System;ConsoleOnly;
      '';
    };
  };
in {
  xdg.dataFile = lib.mkMerge [
    (mkTuiEntry { name = "LazyDocker"; exec = "lazydocker"; icon = "docker"; })
    (mkTuiEntry { name = "btop"; exec = "btop"; icon = "utilities-system-monitor"; })
    (mkTuiEntry { name = "LazyGit"; exec = "lazygit"; icon = "git"; })
    (mkTuiEntry { name = "Disk Usage"; exec = "dust"; icon = "folder"; })
  ];
}
```

---

## D. Development Workflow

### D1. EditorConfig
**File**: NEW `modules/home-manager/editorconfig.nix`
**Action**: Global editorconfig for consistent coding style:
```nix
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
      "*.nix" = {
        indent_size = 2;
      };
      "*.py" = {
        indent_size = 4;
      };
      "Makefile" = {
        indent_style = "tab";
      };
    };
  };
}
```

### D2. GH CLI config
**Current**: gh installed but no default settings.
**Action**: Add to git.nix or a separate module:
```nix
programs.gh = {
  enable = true;
  settings = {
    git_protocol = "ssh";
    prompt = "enabled";
  };
};
```

---

## E. System Hardening & Performance

### E1. File watcher audit
**Current**: No explicit `fs.inotify.max_user_watches` in visible config.
**Action**: Check if already set. If not, add to appropriate sysctl module:
```nix
boot.kernel.sysctl."fs.inotify.max_user_watches" = 524288;
```

### E2. Stylix target audit
**Action**: After all changes, run rebuild and check which Stylix targets activated.

---

## F. Omarchy Feature Parity

### F1. Theme switcher helper script
**File**: Add to `modules/home-manager/fish.nix` or `desktop-utilities.nix`
**Action**: Create a NixOS-aware theme switcher:
```nix
theme-switch = pkgs.writeShellScriptBin "theme-switch" ''
  #!/usr/bin/env bash
  set -euo pipefail
  THEME="''${1:?Usage: theme-switch <theme-name> (e.g., nord, tokyo-night, gruvbox)}"
  SCHEME_FILE="/etc/nixos/modules/desktop/stylix.nix"

  if [ "$THEME" = "list" ]; then
    ls /nix/store/*base16-schemes*/share/themes/ | sed 's/\.yaml$//' | sort
    exit 0
  fi

  sed -i "s|share/themes/.*\.yaml|share/themes/''${THEME}.yaml|" "$SCHEME_FILE"
  echo "Theme set to $THEME. Running nixos-rebuild..."
  sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos
'';
```

### F2. Fastfetch config via Stylix
**Current**: fastfetch installed with zero config.
**Action**: Create a minimal themed config:
```nix
xdg.configFile."fastfetch/config.jsonc".text = builtins.toJSON {
  logo = { source = "nixos_small"; };
  display = { separator = " -> "; };
  modules = [
    "title" "separator" "os" "kernel" "shell" "terminal" "cpu" "gpu" "memory" "disk"
  ];
};
```

---

## Implementation Order

### Phase 1: Bug fixes + quick wins (low risk)
1. **A1** — Fix cursor conflict in icon-theme.nix
2. **B2** — Verify BAT_THEME via Stylix
3. **E1** — Audit file watchers

### Phase 2: Terminal & CLI (medium scope, high daily impact)
4. **B1** — Convert Fish aliases -> abbreviations
5. **B3** — Add fzf Fish integration
6. **B4** — Create declarative git.nix
7. **B5** — Create tmux.nix
8. **B6** — Create lazygit.nix

### Phase 3: Stylix deep integration (medium scope)
9. **A2** — Starship via Stylix colors
10. **A3** — Script color derivation
11. **A4** — Audit Stylix targets

### Phase 4: Desktop polish (additive)
12. **C1** — Centralized mimetype associations
13. **C2** — TUI desktop entries
14. **D1** — EditorConfig
15. **D2** — GH CLI config

### Phase 5: Omarchy parity (nice-to-have)
16. **F1** — Theme switcher script
17. **F2** — Fastfetch config

---

## Files Changed (Summary)

| File | Action | Phase |
|------|--------|-------|
| `modules/home-manager/icon-theme.nix` | Edit: remove cursor lines | 1 |
| `modules/home-manager/fish.nix` | Edit: aliases -> abbrs, fzf | 2 |
| `modules/home-manager/git.nix` | NEW: declarative git | 2 |
| `modules/home-manager/tmux.nix` | NEW: tmux config | 2 |
| `modules/home-manager/lazygit.nix` | NEW: lazygit config | 2 |
| `modules/home-manager/starship.nix` | Edit: Stylix colors | 3 |
| `modules/home-manager/desktop-utilities.nix` | Edit: Stylix colors in scripts | 3 |
| `modules/home-manager/mime-apps.nix` | NEW: mimetype associations | 4 |
| `modules/home-manager/tui-apps.nix` | NEW: TUI desktop entries | 4 |
| `modules/home-manager/editorconfig.nix` | NEW: editorconfig | 4 |
| `modules/system/home-manager.nix` | Edit: register new imports | 2-4 |
| `modules/system/system-packages.nix` | Edit: remove HM-managed pkgs | 2 |
| `modules/home-manager/zen-browser.nix` | Edit: remove dup mimetypes | 4 |

---

## Open Questions

1. Git username/email — need to confirm actual values for `programs.git`
2. imv/mpv — are these installed on all hosts or just zephyr? Need to gate mimetype associations behind package availability.
3. Notification daemon — is Noctilia handling notifications, or should we add mako/fnott?
4. Swaylock — is it actively used, or just installed as a dependency?
5. GH CLI extensions — want gh-dash or any other extensions?
