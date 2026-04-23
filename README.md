# Totems

Lightweight shaman totem manager for WoW Classic TBC (Anniversary,
patch 2.5.5 / Interface `20505`).

Replaces the hand-edited `/castsequence` macro with a configurable
UI: pick your 4 totems per preset, bind a key, and the addon cycles
through them on each press — with optional Windfury twisting for
Enhancement.

## Features

- **Per-preset totem selection** across the four elements
  (air / fire / earth / water), reorderable at will.
- **Multiple named presets** with create / rename / delete,
  alphabetically sorted.
- **Windfury twisting**: after a first "WF + 4 totems" full phase,
  the rotation alternates Windfury with the selected air totem
  forever. Reset via a mini-panel button, a dedicated keybind, or
  automatically on Totem Recall.
- **Windfury refresh warning**: a floating, positionable Windfury
  icon appears (pulsing) when the totem is about to lapse.
- **Active-totem timers** on the mini panel (remaining seconds
  per slot).
- **Next-cast highlight** so you always know which totem the
  keybind will fire next.
- **Share-to-chat**: link the active preset (or a single slot)
  into `/raid`, `/p` or the open chat edit box.
- **Spec-aware accent color** (ele blue / enh orange / resto green).
- **Localization**: English, French, German (fallback to English).

## Install

1. [Download the latest
   release](https://github.com/jejex-007/totems/releases) (or clone
   this repo).
2. Copy the `Totems` folder into your addons directory:
   ```
   World of Warcraft\_anniversary_\Interface\AddOns\
   ```
3. In-game, open **Options → Key Bindings → AddOns → Totems** and
   assign a key to *Cast next totem* (and optionally to *Reset
   twist*).
4. Open the config with `/totems`, pick your totems, pick a key,
   press it.

## Slash commands

- `/totems` — toggle the mini panel / open the config window.
- `/totems debug` — scan the spellbook for any "totem" spell not
  yet mapped in the addon's DB. Useful if a rank is missing from
  the picker.
- `/totems test` — run the built-in test harness.

## Compatibility

- **WoW Classic TBC Anniversary (2.5.5)** — primary target.
  Tested on build `66765`.
- **Class gating**: the addon disables itself on non-shaman
  characters at login (no Lua error, single chat line).
- **No external dependencies** (no Ace3, no LibStub). Pure
  Blizzard API.

## Documentation

- [Business rules (source of truth)](docs/user-guide/business-rules.md)
- [Changelog](docs/project/changelog.md)
- [Backlog](docs/project/backlog.md)
- [TBC secure-button gotchas](https://github.com/jejex-007/totems/wiki)
  — non-obvious TBC API traps we hit building this addon (see
  `CLAUDE.md` and commit messages for now).

## License

[MIT](LICENSE) — © 2026 KySeEtH.
