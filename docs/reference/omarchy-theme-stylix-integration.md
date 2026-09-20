# Omarchy × Stylix theme integration (three layers)

Feeds epic #655. Records the theme-system architecture and the
`colors.toml → base16` generator spec. Static analysis; no build.

## The three layers

| Layer | Surface | Mechanism |
|-------|---------|-----------|
| NixOS / Stylix | console TTY, plymouth, fonts, cursor, icons, system Qt | declarative, boot-time, **host identity** |
| Home Manager / Stylix | btop, starship, lazygit, obsidian, dolphin, telegram, nixcord/Vencord, niri focus-ring/cursor, fish, hermes skin | declarative, `config.lib.stylix.colors` → `modules/stylix-bridges.nix` + per-app `*.nix` |
| Omarchy | Quickshell shell, neovim, vscode, live "current theme" | imperative, instant (`~/.config/omarchy` + `~/.local/state/omarchy`) |

Omarchy is the **palette source of truth**; Stylix is the **render backend**
for the surfaces Omarchy can't reach (pre-session boot surfaces + the long tail
of apps Omarchy doesn't theme). They are unified by one generator, not by
merging the two mechanisms.

## Decision: feed, don't absorb

Keep the existing HM `stylix-bridges` (telegram, nixcord, dolphin, obsidian,
hermes skin — none of which Omarchy themes). Omarchy owns only its native
surfaces (shell + neovim + vscode) instantly. No config file is written by both
systems.

- **Instant** (`omarchy theme set`): shell + neovim/vscode, live.
- **Deferred**: the recorded choice re-derives the Stylix layers on the next
  `home-manager switch` (HM bridges) / `just deploy` (boot surfaces).

## Generator spec: `colors.toml` → base16/base24

Omarchy `themes/<name>/colors.toml` uses *semantic* fields; Stylix wants the
*positional* base16/base24 slots. Default mapping:

| `colors.toml` field | slot | | `colors.toml` field | slot |
|---|---|---|---|---|
| `background` | `base00` | | `red` | `base08` |
| `lighter_background` | `base01` | | `orange` | `base09` |
| `selection` | `base02` | | `yellow` | `base0A` |
| `muted` | `base03` | | `green` | `base0B` |
| `dark_foreground` | `base04` | | `cyan` | `base0C` |
| `foreground` | `base05` | | `blue` | `base0D` |
| `light_foreground` | `base06` | | `magenta` | `base0E` |
| `bright_foreground` | `base07` | | `brown` | `base0F` |
| `dark_background` | `base10` | | `bright_red` | `base12` |
| `darker_background` | `base11` | | `bright_yellow` | `base13` |
| | | | `bright_green` | `base14` |
| | | | `bright_cyan` | `base15` |
| | | | `bright_blue` | `base16` |
| | | | `bright_magenta` | `base17` |

Two cases need explicit rules, not the default:

1. **`yellow` is sometimes green-ish.** Osaka Jade's `yellow = "#459451"` is a
   green; its `bright_yellow = "#E5C736"` is the real yellow. The generator
   should take `bright_*` as authoritative for `base0A`/`base09` when the
   bright value is more saturated than the base, or allow a per-theme override.
2. **`accent` has no base16 slot.** It maps to niri's focus-ring/border color
   (already wired via `config.lib.stylix.colors` in `niri-config.nix`), not a
   base16 slot. Keep `accent` separate.

## Osaka Jade verification (2026-08-18)

The cluster's `modules/desktop/themes/osaka-jade.nix` **already matches**
Omarchy's `themes/osaka-jade/colors.toml` on the core colors:

| slot | Omarchy field | match |
|---|---|---|
| `base00 #111c18` | `background` | ✓ exact |
| `base02 #23372B` | `lighter_background` | ✓ exact (but placed at base02, not base01) |
| `base05 #C1C497` | `foreground` | ✓ exact |
| `base08`–`base0E` | `red`/`bright_red`/`bright_yellow`/`green`/`cyan`/`blue`/`magenta` | ✓ exact |

The **shaded slots are hand-interpolated** and do not follow the generator
mapping — this is the only drift:

| slot | cluster value | Omarchy field it *should* be |
|---|---|---|
| `base01 #1d2b25` | hand-picked | `lighter_background #23372B` |
| `base02 #23372B` | `lighter_background` | `selection #32473B` |
| `base03 #3a4f43` | hand-picked | `muted #53685B` |
| `base04 #8a9479` | hand-picked | `dark_foreground #81B8A8` |
| `base06 #E3E2C4` | hand-picked | `light_foreground #D6D5BC` |
| `base07 #F6F5DD` | hand-picked | `bright_foreground #F7E8B2` |
| `base0F #D7C995` | hand-picked | `brown #513925` |

Regenerating `osaka-jade.nix` through the generator fixes these seven slots.

## Host identity vs user theme

The six non-Omarchy host palettes (`forge-copper`, `nexus-ice`, `sentry-ember`,
`ci-amethyst`, `krash-tangerine`, `metadata-slate`) are intentional per-host
identities with no Omarchy counterpart. They stay declarative; the user's
session theme is independent (`omarchy theme set`). Only `osaka-jade` has an
Omarchy namesake and participates in the generator.

## Coupling to fix

`home-manager-config/modules/fish.nix` hardcodes
`SCHEME_FILE="/etc/nixos/modules/desktop/stylix.nix"` — the HM layer reaches
into the nixos-config repo. When the generator lands, this must become a
generated file reference, not a cross-repo path.
