# Omarchy vs. NixOS Cluster — App & Tool Parity

> Source: `basecamp/omarchy` @ local checkout (`~/Projects/omarchy`) vs. this repo
> (nixos-config) + `reverb256/home-manager-config`. Snapshot: 2026-08-18.

This is the *data* behind issues #655–660 (Omarchy UX port). It maps every
Omarchy tool to what the cluster already ships, so the port plan can decide
"reuse", "port", or "gap" per item.

---

## 1. Backends (the interesting part — most already overlap)

| Omarchy | Cluster | Status |
|---------|---------|--------|
| `herdr` (bar/menu router, `config/herdr/config.toml`) | `packages/herdr.nix` (shipped) | ✅ **already ours** |
| `omarchy-bar` / `omarchy-menu` → **route through herdr** | herdr | ✅ backend present, frontends TBD |
| `quickshell-git` (the shell) | ❌ no quickshell input | 🕳 **gap** (issue #657) |
| Hyprland | **niri** (deliberate, issue #658) | 🔀 different compositor |

Omarchy does **not** use rofi/waybar/anyrun — its launcher/bar/menu are custom
frontends over herdr + quickshell. The cluster already has herdr, so the port is
"write the quickshell frontends + retarget to niri", not "import a launcher".

---

## 2. Core packages — `install/omarchy-base.packages` (131 entries)

Legend: ✅ have · 🕳 missing · 🔀 different-but-equivalent · — N/A/OS-specific

### Terminal / shell / CLI

| Omarchy | Cluster | Status |
|---------|---------|--------|
| `foot` (default terminal) | **alacritty** (default) + kitty | 🔀 different |
| `starship` | `starship.nix` | ✅ |
| `tmux` | `tmux.nix` | ✅ |
| `zoxide`, `fzf`, `eza`, `bat`, `ripgrep`, `fd` | all in `fish.nix` home.packages | ✅ |
| `btop` | `btop.nix` | ✅ |
| `lazygit`, `lazydocker` | `lazygit.nix` + `tui-apps.nix` | ✅ |
| `fastfetch` | `fish.nix` | ✅ |
| `dua-cli` | **dust** | 🔀 equivalent |
| `tldr` | ❌ | 🕳 (trivial) |
| `gum` | ❌ | 🕳 (scripting UI) |
| `omarchy-nvim` (neovim) | **helix** (`desktop-utilities.nix`) | 🔀 different editor |
| `usage`, `tree-sitter-cli`, `luarocks`, `ruby`, `clang`, `llvm`, `dotnet-runtime`, `poetry-core`, `mise` | ❌ (dev-toolchain) | 🕳 (nix-shell covers most) |

### Media / capture

| Omarchy | Cluster | Status |
|---------|---------|--------|
| `mpv`, `mpv-mpris` | `mpv` (`desktop-utilities.nix`, firejail) | ✅ |
| `imv` | `imv` (`desktop-utilities.nix`) | ✅ |
| `grim`, `slurp`, `hyprpicker` | `grim`/`slurp` (screenshot scripts) | ✅ |
| `wl-clipboard`, `wtype` | `wl-clipboard` | ✅ |
| `tesseract` (+ eng) | `tesseract` (ocr-extract) | ✅ |
| `imagemagick`, `libvips`, `ffmpegthumbnailer` | ❌ | 🕳 (image stack) |
| `gpu-screen-recorder` | `screenrecord` (custom) | 🔀 equivalent |
| `kdenlive`, `obs-studio`, `pinta`, `xournalpp` | ❌ | 🕳 (content-creation apps) |
| `voxtype` (TTS) | **chatterbox-tts** | 🔀 equivalent |

### System / infra

| Omarchy | Cluster | Status |
|---------|---------|--------|
| `docker`, `docker-compose`, `docker-buildx` | k3s/containerd (different model) | 🔀 different |
| `networkmanager`, `bluez*`, `avahi`, `nss-mdns`, `cups*` | NixOS networking/bluetooth/printing modules | ✅ (declarative) |
| `power-profiles-daemon`, `brightnessctl`, `ddcutil`, `hyprsunset` | NixOS power + `zephyr-sdr-brightness.nix` | ✅/🔀 |
| `udiskie`, `gvfs-*`, `gnome-disk-utility` | Dolphin/KDE stack | 🔀 different |
| `ufw` (+ `ufw-docker`) | NixOS firewall | 🔀 different (declarative) |
| `snapper` (snapshots) | NixOS generations | 🔀 different |
| `plymouth`, `sddm`, `limine` | systemd-boot (see UKI issue #705) | 🔀 different boot |
| `fido2`/`fingerprint` helpers | security.nix | 🔀 |
| `qemu-user-static-binfmt` | ❌ | 🕳 (cross-arch) |

### Apps

| Omarchy | Cluster | Status |
|---------|---------|--------|
| `chromium` (default browser) | **zen-browser** (twilight) | 🔀 different |
| `firefox` | firejail-wrapped firefox | 🔀 |
| `obsidian` | `obsidian.nix` | ✅ |
| `nautilus` (+ `sushi` preview) | **Dolphin** (`dolphin.nix`) | 🔀 different FM |
| `libreoffice-fresh` | ❌ | 🕳 |
| `evince` (PDF) | ❌ | 🕳 |
| `localsend` | ❌ | 🕳 |
| `moonlight-qt` | ❌ | 🕳 (streaming) |
| `telegram-desktop` | `telegram-desktop` (opencode opt) | 🔀 partial |
| Discord / WhatsApp / HEY / Zoom / YouTube | `vesktop` + `caprine` + `firefox-pwa-apps` | 🔀 partial |

### Gaming

| Omarchy | Cluster | Status |
|---------|---------|--------|
| `steam` | `steam` (gaming-base, firejail+steam-run wrappers) | ✅ |
| `retroarch` | ❌ | 🕳 |
| battlenet (desktop entry) | ❌ | 🕳 |
| `mangohud` | `mangohud` + `vkbasalt` | ✅ |
| `gamemode` (via `asdcontrol`/`cliamp`?) | `gamemode` (gaming-base) | ✅ |
| `gamescope` | `gamescope` (gaming-base + gaming-hdr) | ✅ |
| VR (OpenVR) | VR via WiVRn (`gaming-vr-unlock`) | ✅ (different stack) |

### Fonts / IME

| Omarchy | Cluster | Status |
|---------|---------|--------|
| `ttf-jetbrains-mono-nerd-basic`, `ttf-ia-writer`, `noto-*` | `nerd-fonts.jetbrains-mono` (stylix) | ✅ |
| `fcitx5` (+ gtk/qt) | ❌ | 🕳 (IME) |
| `yaru-icon-theme` | custom icon theme | 🔀 |

---

## 3. `install/omarchy-other.packages` (drivers/hardware)

Almost entirely Arch/NixOS-orthogonal: `linux`, `nvidia-*dkms`, `intel-*`,
`vulkan-*`, `snapper`, `limine`, `zram-generator`, `asusctl`, `thermald`, and
MacBook/T2/Tuxedo/Dell-XPS firmware paths. NixOS owns all of this declaratively
(hardware modules, `hardware.nvidia`, boot loader). **Nothing to port** — this
list maps 1:1 onto already-working NixOS config. Worth a skim only for the
*zram* and *power-profiles* nudges (both already handled).

---

## 4. The `bin/` toolbelt (~160 `omarchy-*` commands)

Not apps to install — they're Omarchy's own operator scripts (theme system,
update guard, snapshot, audio/brightness routing, webapp installers, agent
tooling). These are the real port surface for issues #656–#659. Buckets:

- **Theme system** (`omarchy-theme-*`, `omarchy-toggle-*`) → maps to Stylix +
  `noctalia` palette (already live). Port = frontend only.
- **Update guard** (`omarchy-update-*`, pacman ALPM hook) → N/A. NixOS is
  declarative; the cluster's equivalent is `just` recipes + `deploy.yml`.
- **Hardware toggles** (`omarchy-brightness-*`, `-audio-*`, `-bluetooth-*`,
  `-toggle-hybrid-gpu`) → some exist (`zephyr-sdr-brightness.nix`); others are
  gaps worth porting as niri keybind scripts.
- **Capture** (`omarchy-capture-*`, `-qr`) → cluster has screenshot/screenrecord
  scripts; the QR + webcam-list variants are gaps.
- **Agent tooling** (`omarchy-agent*`) → cluster equivalent: MCP servers + hermes.

---

## 5. Summary — what's actually missing

**High-value gaps** (worth scoping as follow-ups):

1. **quickshell shell** — the single biggest gap (#657). Everything else below
   hangs off it (bar, menu, notifications, osd, clipboard, emoji, image-picker,
   lock, polkit, reminders panels).
2. **Content-creation suite** — kdenlive, obs-studio, pinta, xournalpp, evince,
   libreoffice.
3. **Image/media libs** — imagemagick, libvips, ffmpegthumbnailer.
4. **Dev toolchain convenience** — mise, tldr, gum, tree-sitter-cli, dotnet.
5. **Gaming niceties** — retroarch, battlenet, moonlight-qt.
6. **Comms/misc** — localsend, fcitx5 (IME), full Telegram.

**Already-equivalent (do NOT re-port):** herdr, mpv/imv, grim/slurp/tesseract/
wl-clipboard, btop/lazygit/lazydocker/fastfetch/eza/bat/ripgrep/fd/fzf/zoxide/
starship/tmux, steam/gamemode/gamescope/mangohud, obsidian, all system infra.

**Different-by-decision (keep):** niri over Hyprland, alacritty over foot,
helix over neovim, zen over chromium, Dolphin over nautilus, systemd-boot/UKI
over limine/sddm.
