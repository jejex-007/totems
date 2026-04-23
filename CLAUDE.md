# Totems — working agreement

A WoW TBC Classic Anniversary shaman addon that replaces static
`/castsequence` totem macros with a small config UI.

## Stack
- Lua + XML, Blizzard addon API for TBC Classic 2.5.x.
- Target TOC Interface version: `20505` (TBC Anniversary, patch
  2.5.5). Verify in-game with
  `/dump (select(4, GetBuildInfo()))` if anything acts strange on
  load.
- No external libs for v0.1 (no Ace3, no LibStub). Keep it vanilla
  so the codebase stays small and readable.

## Layout
```
.                         # repo root (Git)
├── README.md             # public-facing install + feature list
├── LICENSE               # MIT
├── .gitignore            # editor / OS noise
├── CLAUDE.md             # this file (working agreement)
├── Totems/               # the addon folder — copy into Interface/AddOns/
│   ├── Totems.toc
│   ├── Bindings.xml
│   ├── Locales.lua       # en / fr / de tables + addon.L
│   ├── Core.lua          # spell DB, state, secure button, events, slash cmd
│   ├── UI.lua            # mini + main config panels, dropdowns, tooltips
│   └── Tests.lua         # in-game test harness (`/totems test`)
└── docs/
    ├── project/          # backlog + changelog + timesheet (house rules)
    └── user-guide/       # sources of truth
        ├── business-rules.md       # WHAT the addon does (BR-* IDs)
        └── engineering-standards.md # HOW the code is written (NFR-* IDs)
```

## Testing
- The addon runs in-game only; no automated suite. Smoke-test loop:
  1. Copy `Totems/` into
     `World of Warcraft/_anniversary_/Interface/AddOns/`
     (Jérôme's install: `D:\Jeux\World of Warcraft\_anniversary_\Interface\AddOns\`).
  2. `/reload` (or fresh login).
  3. Open `/totems`, pick totems, bind the key under
     *Key Bindings → AddOns → Totems*, press it in-game.
- If a learned totem is missing from the picker, run `/totems debug`
  — it prints any spellbook entry whose name matches "totem" but
  whose spell ID is not in our database.

## Definition of done
- Code loads without Lua errors on `/reload`.
- `/totems` opens the config window.
- Pressing the bound key casts the next totem in the active preset's
  sequence (in-combat too — macrotext is always valid).
- The change does not violate any **MUST** rule in
  `docs/user-guide/engineering-standards.md` (NFR-*). Any
  deviation from a **SHOULD** rule is justified in the changelog
  entry.
- `business-rules.md` is updated if the change alters a BR-*.
- Changelog entry added the same day the feature ships.
- Timesheet row updated with duration + features shipped.
- Backlog item moved to Done if it was tracked there.

## Things to ask before doing
- Adding dependencies (Ace3, LibStub, LibSharedMedia…). Default is
  still vanilla.
- Changing SavedVariables schema (migrations matter; users may
  have existing presets).
- Adding files to the addon (the TOC must list them, order matters).

## Conventions
- Code, comments, and docs in English. Chat with Jérôme in French.
- Keep files small; keep Lua style simple (no OOP unless a feature
  demands it).
- No emojis in code or docs.
- Do not use `--no-verify` or similar shortcuts. No root-cause, no
  fix.

## Privacy — public repo
This repository is public at https://github.com/jejex-007/totems.
Never introduce the maintainer's full real name in committed files.
Naming convention:
- **`KySeEtH`** — public attribution: addon author in the TOC,
  copyright in LICENSE, credits in README, references in changelog /
  backlog / timesheet / code comments.
- **`jejex-007`** — GitHub handle: repo URLs, `git remote` config,
  issue / PR URLs.
- **`Jérôme`** (first name) — permitted ONLY in this `CLAUDE.md` as
  the name of the working-agreement party. Never in
  `README.md`, `LICENSE`, `docs/`, code comments, or commit messages.
- **Full real name** — never in any tracked file.

Per-repo git identity (already configured, do not revert):
- `user.name  = jejex-007`
- `user.email = jejex-007@users.noreply.github.com`
