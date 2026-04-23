# Totems — changelog

Entries are newest-first. One entry per commit/push once git is
introduced. Format: date + scope + one-paragraph summary.

## 2026-04-23 — twist badge + phase-aware halo + WF countdown

Scope: a dedicated indicator on the mini panel for twist mode,
replacing the implicit "WF is cast between each totem" mental
model with a visible badge. The per-slot yellow highlight stays
as the full-phase signal; the blue halo on the badge becomes the
short-phase signal (mutually exclusive). Implements
`BR-TWIST-UI-4`.

- `UI.lua` — new `UI.twistBadge` on the mini panel, anchored to
  the LEFT of slot 1 (y-offset -8 to clear the gear chrome icon).
  24x24 WF icon with a 3 px blue halo behind it (shown only in
  the twist short phase), an ARIALN 14pt THICKOUTLINE white
  countdown overlay centered on the icon, and a tooltip
  ("Twist active" + hint).
- Phase detection reads three attributes off the secure cast
  button: `twist-mode`, `twist-count`, `twist-full-len`. The UI
  treats `mode == "short"` OR (`mode == "full"` AND `count >=
  fullLen`) as the "short phase" for display purposes — the halo
  therefore lights up on the LAST cast of the full phase (press
  N) rather than waiting for the first cast of the short phase
  (press N+1). The secure macrotext swap threshold
  (`count > fullLen`) is unchanged; this is a pure UI
  anticipation.
- Countdown text: `WF_REFRESH_THRESHOLD - (GetTime() -
  lastWFCastTime)`, seconds. Hidden when twist isn't applicable,
  the player hasn't cast WF yet, or the threshold has elapsed
  (the floating WF icon pulse takes over past zero).
- `Core.lua` — `OnSpellCast` now calls `UI:RefreshMini()` right
  after the WF-cast timestamp update, so the badge halo / timer
  refresh as soon as WF itself fires (the earlier early-return
  on "cast doesn't match preset slot" skipped the mini refresh
  for WF casts).
- `Core.lua` — new `addon:OnTwistReset()` helper centralises the
  non-secure cleanup after any twist reset: clears
  `lastWFCastTime` AND calls `UI:RefreshMini`. Called from (1)
  `ResetTwist` (Lua path, out-of-combat via Totem Recall),
  (2) the keybind reset button's HookScript, (3) the mini reset
  button's HookScript. Before this, the halo stayed visible
  until the next matching cast instead of clearing immediately
  on reset.
- `Locales.lua` — new keys `TT_TWIST_BADGE` / `TT_TWIST_BADGE_HINT`
  in en/fr/de (and added to `REQUIRED_LOCALE_KEYS` in Tests.lua).
- `UI.lua` — layout constant `TWIST_HALO_R/G/B` at the top of the
  file (shaman-Elemental blue, matches `SPEC_COLORS[1]`).
- `docs/user-guide/business-rules.md` — new `BR-TWIST-UI-4`
  describing the three badge states and the mutual exclusion with
  the per-slot highlight.

Validated in-game: badge shows with WF icon when twist applicable;
countdown decrements on cast; halo lights up on the last full-
phase press (press 3 with 2 active totems, press 5 with 4 active
totems); halo clears immediately on any of the three reset paths.
93 tests passing (count unchanged — the new locale keys fold into
the existing per-language coverage assertion).

## 2026-04-23 — refactor wave (post-NFR creation): 8 items against the new spec

Scope: first refactor pass driven by `engineering-standards.md`. An
audit agent produced ~20 findings; 4 turned out to be false
alarms on verification, the others align to one or more NFRs.

- **NFR-SEC-5 — twistResetBtn guard removed.** The defensive
  `if addon.castBtn then` around `SetFrameRef("castBtn", addon.castBtn)`
  silently skipped FrameRef setup if the init order ever broke.
  `InitMini` runs after `createSecureButton` in the PLAYER_LOGIN
  flow, so the ref is always present — let a future regression
  error loudly instead of silently producing a dead reset button.
- **NFR-MAINT-5 — 3 position save/restore helper pairs → 1
  parameterized pair.** `savePos(f, dbKey)` /
  `applyPos(f, dbKey, defPoint, defX, defY)` replaces
  `savePosition/applyPosition`, `saveMiniPos/applyMiniPos`,
  `saveWFIconPos/applyWFIconPos` (6 helpers → 2, ~60 lines → 30).
- **NFR-LOCALE-3 — full locale key coverage test.** The old
  French/German spot-check (7 keys) missed typos in the other 33
  keys. Extracted `REQUIRED_LOCALE_KEYS` (40 keys) into a shared
  local + helper `missingKeysIn`; 3 tests now iterate every key
  in EN / FR / DE independently and name the missing key on
  failure. Overall assert count dropped 105 → 93 (fewer
  assertions, more coverage).
- **NFR-MAINT-5 — chrome hover helper.** The main and mini
  panel `OnUpdate` handlers both inlined the same 10-line
  "IsMouseOver + fade chrome alpha" pattern. Extracted to
  `updateChromeHover(frame, chrome)`; each caller keeps its own
  throttle loop (they have different per-frame / throttled work
  around the chrome bit).
- **NFR-DATA-2 — defensive re-inits removed.** `InitDB` is the
  single source of truth for `TotemsDB.ui`'s schema; the 4
  stray `TotemsDB.ui = TotemsDB.ui or {}` guards in `savePos`,
  `UI:SetLocked`, the mini close button, and `UI:ToggleMini`
  suggested (incorrectly) that `TotemsDB.ui` could be nil at
  those points. Removed.
- **NFR-MAINT-6 — magic numbers promoted to named constants.**
  Core: `DEFAULT_RESET_TIMER = 10` (4 call sites, also consumed
  from UI via `addon.`), `SPELLS_CHANGED_DEBOUNCE = 0.3`,
  `RESPEC_SCAN_DELAY = 2`, `OFFSCREEN_OFFSET = 9999` (2 call
  sites for off-screen secure buttons). UI: `UPDATE_THROTTLE = 0.1`,
  `WF_PULSE_HZ = 5` + `WF_PULSE_BASE = 0.5` +
  `WF_PULSE_AMPLITUDE = 0.5`, `EMPTY_SLOT_ALPHA = 0.35`,
  `SLOT_DRAG_ALPHA = 0.4`. All UI constants hoisted to the top
  of the file so they're declared before any function that
  captures them as upvalues (the `0.1` in `UI:Init`'s OnUpdate
  would have bound to a global otherwise).
- **Bug fix — "Masqués" dropdown didn't toggle.** Each click of
  the button ran `UIDropDownMenu_Initialize` again, which
  resets the dropdown state, so `ToggleDropDownMenu` always
  opened (never closed). Added a guard: if the dropdown is
  already open AND owned by our menu, close instead of
  re-initializing.
- **Polish — click outside a Totems dropdown now closes it.**
  TBC Classic's "MENU" dropdowns don't auto-close on outside
  clicks (retail-only behavior). Added an invisible fullscreen
  click-catcher (strata `HIGH`) shown whenever any Totems
  dropdown opens and hidden on its `OnHide`. A single helper
  `openDropdown(level, value, menuFrame, anchor, x, y)` replaces
  the 4 direct `ToggleDropDownMenu` call sites (Masqués, main
  preset, mini preset, mini slot picker).

Audit findings rejected on verification: `ApplyKeybind` pending
flag (already re-invoked in `PLAYER_REGEN_ENABLED`); "stale
`lastWFCastTime` on preset switch" (the timer represents "time
since last WF cast" regardless of preset, remains meaningful);
preset-deletion-mid-combat (active always resets to `"Default"`
before `ApplyMacrotext`, never nil); `GetTotemInfo` when mini
hidden (OnUpdate doesn't fire on hidden frames).

Tests: 93 passing, 0 failing.

## 2026-04-21 — dynamic sequence + twist (phase B + phase C)

Scope: finish the cast plumbing rebuild — first a dynamic
`/castsequence` from the active preset's order + selections
(phase B), then the full totem-twisting state machine (phase C).

- `Core.lua` — `BuildMacrotext(preset)` composes
  `/castsequence reset=N A, B, C, D` from `NormalSpells(preset)`,
  skipping empty slots; empty preset or nil returns `""`.
  `BuildTwistFullMacrotext` / `BuildTwistShortMacrotext` do the
  same for the two twist phases (full = WF + 4 normal totems;
  short = WF + selected air totem). `ApplyMacrotext` branches on
  `TwistApplicable(preset)`: in twist mode, both macrotext
  variants are pre-written to `macrotext-full` / `macrotext-short`
  on the secure button, with `twist-mode="full"`, `twist-count=0`
  and `twist-full-len=#full`; the live `macrotext` starts at full.
  Non-twist mode just sets `macrotext` from `BuildMacrotext` and
  clears all the twist-* attributes.
- State machine via `SecureHandlerWrapScript` preBody on the cast
  button (empirically required — postBody is silently dropped on
  `SecureActionButtonTemplate` clicks in TBC Classic 2.5.5).
  Snippet increments `twist-count` on each press while in full
  mode; when `count > twist-full-len`, swaps `macrotext` to
  `macrotext-short` and flips `twist-mode="short"`. Because
  preBody runs BEFORE the cast dispatch, the swap takes effect on
  the current press — press N+1 uses the short sequence starting
  fresh at position 1 (WF). Short mode is a pure `/castsequence`
  loop thereafter (WF, air, WF, air, ...), the snippet early-returns.
- `ResetTwist` rewritten to the new attribute scheme
  (`twist-mode="full"`, `twist-count=0`, `macrotext` ← full). The
  `UNIT_SPELLCAST_SUCCEEDED` handler already routes Totem Recall
  (spell ID 36936) to it, so out-of-combat recall resets the pull.
  `UI.lua` — the mini-panel Reset-twist button's secure `_onclick`
  snippet updated to the new attribute names (previously written
  against the abandoned per-slot-spell scheme); RegisterForClicks
  switched to `"AnyDown"` for consistency. In-combat resets go
  through this secure button.
- `Tests.lua` — 7 new cases: `BuildMacrotext` (happy path,
  `resetTimer` respected, empty preset, nil preset) +
  `BuildTwistFullMacrotext` / `BuildTwistShortMacrotext` (happy
  paths + empty-when-no-air-selection). 105 passing, 0 failing.
- Memory updated with the `postBody` silent-drop quirk — use
  preBody with `count > N` threshold instead.

Validated in-game: twist preset with air=Grace of Air cycles
WF → Mana Spring → Stoneskin → Grace → Searing over presses 1–5,
then WF → Grace → WF → Grace forever from press 6. Totem Recall
resets back to the full phase out of combat.

## 2026-04-23 — mini-panel polish: sorted presets + element placeholders + totem timers

Scope: three independent mini-panel usability improvements
landing together.

- **Alphabetical preset dropdown** (`UI.lua` / `dropdownInit`):
  collect the preset names into a list, `table.sort` case-insensitive,
  then iterate. Replaces the previous `pairs()` iteration which had
  Lua's non-deterministic order.
- **Element placeholder icons on empty slots** (`Core.lua` +
  `UI.lua` / `UI:RefreshMini`): new `addon.ELEMENT_ICON` table maps
  each element to a non-totem spell icon
  (`Spell_Nature_LightningShield` / `Spell_Fire_Fire` /
  `Spell_Nature_EarthShock` / `Spell_Frost_FrostShock`). When a slot
  has no totem selected (or the selection isn't learned), the slot
  shows the element icon at 35 % alpha. First iteration used actual
  totem icons (Stoneclaw / Searing / Mana Spring / Windfury) but
  those read as "there IS a totem selected" — swapped for generic
  shaman-school spell icons.
- **Per-slot active-totem countdown** (`UI.lua` slot creation +
  mini OnUpdate): new `slot.timer` FontString (ARIALN 18pt
  THICKOUTLINE white, centered) showing remaining seconds while
  the matching totem is active. Drives off `GetTotemInfo(1..4)`
  every 0.1 s; matches the active totem back to our preset slot by
  ICON path (locale-independent, more robust than name matching).
  Hides when the totem drops or the preset slot has no selection.

Validated in-game: presets list sorted A→Z (case-insensitive);
empty slots show faded element icons; timers count down in real
time and clear on expiry.

## 2026-04-22 — floating WF refresh icon (replaces the red border)

Scope: the 2026-04-21 WF refresh warning used a mini-anchored
pulsing red border. Adding a standalone, user-positionable WF
icon made the border redundant — the icon reads just as well
peripherally AND the player can park it where they actually look.

- `UI.lua` — new `TotemsWFIconFrame` (standalone 56x56 texture
  frame, movable when unlocked, `SetClampedToScreen`, position
  persisted in `TotemsDB.ui.wfIconPos`, default at
  `CENTER +0 +100`). Shown under the same conditions as the old
  red border (twist applicable + ≥ `WF_REFRESH_THRESHOLD` since
  last WF) AND additionally while the main config is open (with
  the preset having twist applicable) so the user can reposition
  it without waiting for a real warning. Pulse alpha on warning,
  solid 1.0 during positioning. Mini `OnUpdate` tracks the
  `warningActive` flag in the throttled block so the per-frame
  pulse branch doesn't re-run the timer math.
- `UI.lua` — removed the mini-anchored `wfWarn` red-border frame
  + its references in the OnUpdate. The floating icon replaces
  its role entirely.
- `docs/user-guide/business-rules.md` — `BR-TWIST-UI-3` rewritten
  to describe the icon rather than the border, and to document
  the positioning-mode behavior.

Validated in-game: icon appears at its saved position on warning
and pulses; appears solid (non-pulsing) when the main config is
open for repositioning; all three reset triggers still clear it
(Totem Recall, mini Reset button, Reset-twist keybind).

## 2026-04-22 — class-guard fix + clearer non-shaman message

Scope: the class-guard at PLAYER_LOGIN was erroring on non-shaman
alts, and the chat message it shows on those characters wasn't
giving the player enough context.

- `Core.lua` — wrap the auto-disable call in a namespace-aware
  fallback (`(C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn`).
  TBC Classic Anniversary 2.5.5 (build 66765) migrated the
  `DisableAddOn` global into `C_AddOns` as part of Blizzard's
  2024 API namespacing refactor, so calling the bare global
  threw `attempt to call global 'DisableAddOn' (a nil value)` on
  every non-shaman login.
- `Locales.lua` — rewrote `CHAT_DISABLED_CLASS` (EN/FR/DE) from
  the terse "disabled (this class has no totems)" to a clearer
  two-sentence message that names the addon, explains that it is
  only usable by shamans, and suggests uninstalling for other
  classes.
- `memory/tbc_secure_button_gotchas.md` — new entry recording the
  `C_AddOns` migration so we don't trip on it again on this
  build.

Validated in-game: warrior relog now prints the new French
message cleanly, no Lua error.

## 2026-04-21 — Windfury refresh warning

Scope: in twist mode, the Windfury Totem's pulse window lapses
quickly and it's easy to forget to re-cycle WF mid-rotation. New
visual cue on the mini panel so the player catches it in peripheral
vision without checking a timer.

- `Core.lua` — new `addon.lastWFCastTime` (tracks GetTime of the
  last Windfury cast, 0 = never) and `addon.WF_REFRESH_THRESHOLD`
  constant (10 s). `OnSpellCast` records the timestamp whenever the
  cast spell ID matches any WF rank via `WFEntry()`. `ResetTwist`
  clears the timestamp so the Totem Recall path also dismisses the
  warning. Both reset buttons (mini icon and keybind) HookScript
  OnClick to clear the timestamp too — the secure `_onclick` snippet
  mutates cast-button attributes, and the insecure post-hook then
  clears the Lua-side timer.
- `UI.lua` — new `wfWarn` overlay frame over the mini, with a red
  32-pixel tooltip-border edge and a tight outward inset; hidden by
  default. The mini's existing throttled OnUpdate now runs two
  extra checks: a smooth per-frame alpha pulse
  (`0.5 + 0.5 * |sin(t*5)|`) while the overlay is shown, and a
  throttled show/hide decision (shown iff twist applicable + WF
  previously cast + ≥ `WF_REFRESH_THRESHOLD` elapsed).
- `docs/user-guide/business-rules.md` — new **BR-TWIST-UI-3**
  describing the warning trigger and the four ways it clears.

Validated in-game: warning appears ≥10 s after the last WF in
twist mode, clears on next WF cast, Totem Recall, mini Reset
button, and Reset-twist keybind.

## 2026-04-21 — second keybind: Reset twist

Scope: close BR-BIND-1 by wiring the second Blizzard keybinding
so users can reset the twist state machine without opening the
mini panel.

- `Core.lua` — shared `addon.RESET_TWIST_SNIPPET` defined once
  (mutates `twist-mode` / `twist-count` / `macrotext` on the cast
  button referenced via `SetFrameRef`). New
  `createResetButton()` builds an invisible off-screen
  `SecureHandlerClickTemplate` button (`TotemsResetTwistButton`)
  whose `_onclick` runs that snippet; created at PLAYER_LOGIN
  alongside the cast button. `ApplyKeybind` extended to clear
  and re-apply overrides for both `TOTEMS_CAST` and the new
  `TOTEMS_RESET_TWIST`.
- `Bindings.xml` — second `<Binding name="TOTEMS_RESET_TWIST">`
  entry, same no-op body pattern as the cast binding.
- `UI.lua` — mini-panel reset icon now reuses
  `addon.RESET_TWIST_SNIPPET` instead of inlining the attribute
  writes, keeping a single source of truth.

Validated in-game: the Blizzard Key Bindings panel shows two
entries under Totems (Cast / Reset twist); binding Shift-R to
the reset pulls the state machine back to full phase mid-pull
(secure, in-combat safe).

## 2026-04-21 — cast plumbing rebuild (phase A): single-totem hardcoded

Scope: after the twist-dispatch rebuild attempted in the previous
session left the keybind silently non-casting on the live client,
strip the secure button back to a minimal hardcoded macrotext and
identify the real blocker before rebuilding anything dynamic.

- Root cause found: `RegisterForClicks("AnyUp")` alone silently
  drops the protected action on binding-triggered clicks on TBC
  Classic Anniversary 2.5.5 (build 66765). OnClick still fires
  (HookScript confirms) and `/dump` shows all attributes correct,
  but no cast happens — the engine evaluates the secure click on
  the "down" event and skips the protected action when only "up"
  is registered. Earlier sessions' diagnosis blaming WoWUIBugs
  #552 (macrotext dispatch removal) was a misread — dynamic
  macrotext works fine once the registration is right.
- `Core.lua` — `createSecureButton` now uses
  `RegisterForClicks("AnyDown")` only (single fire per keypress
  AND secure dispatch runs). `ApplyMacrotext` stripped down to a
  hardcoded `/castsequence reset=10 Totem de Force de la Terre`;
  all the state-machine attribute writing from the twist rebuild
  (type="spell"/per-button suffixed variants, phase/step/spell-N
  slots, PHASE_SLOTS) removed. `ResetStep` no longer touches
  secure attributes — only Lua-side `currentStep` + UI refresh.
  Diagnostic HookScript removed; `Bindings.xml` restored to its
  no-op body.
- Memory updated with two corrections: (a) click registration —
  `"AnyDown"` alone is correct, `"AnyUp"` alone is the trap,
  `("AnyUp","AnyDown")` works but double-advances `/castsequence`
  per press; (b) macrotext dispatch is NOT blocked on the tested
  build — the WoWUIBugs #552 caveat was incorrect for this client.

Validated in-game: R now casts Totem de Force de la Terre on a
single press. Ready to restore dynamic sequences from the active
preset (phase B).

## 2026-04-21 — spec-first refactor (phase 1/3): business rules + localization

Scope: move to a spec-first approach before rebuilding the twisting
state machine. A single source of truth for behavior, and a
localization layer that clears the way for the cast-dispatch
rewrite (phase 2) and the Reset-twist keybinding (phase 3).

- `docs/user-guide/business-rules.md` — authoritative spec, 17
  sections, each rule stable-IDed as `BR-<section>-<n>`. Covers
  eligibility, totem DB, presets, sequence model, hidden totems,
  keybinding, next-cast highlight, twisting (§ 8, phases + reset
  triggers + UI affordances), spec theming, respec handling,
  group sharing, mini + main panels, persistence, combat safety,
  slash commands, non-goals. KySeEtH added § 18 (localization)
  and extended BR-BIND-1 to declare a second keybinding for
  "Reset twist".
- `Locales.lua` — new file loaded first. Tables per tag
  (`en` / `fr` / `de`) with 40+ keys covering every visible
  string. `addon:PickLocale(code)` maps Blizzard locale codes
  (`frFR`, `deDE`, `enUS`, `enGB`) to a tag, falls back to
  English for anything else. `addon.L` is backed by the picked
  table; missing keys fall through to English; keys missing
  everywhere surface as `[KEY_NAME]` so gaps are visible in-game.
- `Core.lua` — `ELEMENT_LABEL` rebuilt from `addon.L`; all chat
  messages (`CHAT_LOADED`, `CHAT_DISABLED_CLASS`, debug scan /
  unmapped / done) and binding globals (`BINDING_HEADER_TOTEMS`,
  `BINDING_NAME_TOTEMS_CAST`, new `BINDING_NAME_TOTEMS_RESET_TWIST`)
  now read from `addon.L`. Brand color code exposed as
  `addon.BRAND`.
- `UI.lua` — every hardcoded French string replaced with
  `addon.L.<key>`: element labels, picker tooltip, Masqués label
  and empty-menu entry, Nouveau / Renommer / Supprimer entries,
  all three popups (new / rename / delete) with their buttons,
  Lock tooltip (Verrouiller / Déverrouiller) on both panels,
  Reset (s) and Preset labels, Totem twisting checkbox + its
  tooltip (LABEL_TWIST_CHECK + TT_TWIST_INFO), combat-lockout
  chat message, gear / share / share-hint / reset-twist / slot
  tooltips (click, shift-click, drag, right-click).
- Tests — 8 new cases covering `PickLocale` for frFR / deDE /
  enUS / enGB / unknown (falls back to en), the `[KEY]` marker
  for truly missing keys, a presence check for every required
  key in English, and a non-`nil` check for core keys in French
  and German. 67 passing in total, 0 failed.
- Fix: `SecureHandlerWrapScript` rejects `nil` for `preBody` on
  TBC Classic 2.5.x ("Invalid pre-handler body"); pass the empty
  string `""` when you only want to wrap `postBody`. Memory
  updated with this and related TBC secure-button gotchas.

## 2026-04-20 — delete confirmation + per-totem link

Scope: safety on preset deletion and finer sharing for group
coordination.

- Deleting a preset via the dropdown now opens a confirmation
  popup ("Supprimer le preset 'X' ?" with `Supprimer` / `Annuler`).
  `UI:DeleteActivePreset` no longer wipes silently; the action
  happens in the popup's `OnAccept` against the name captured at
  prompt time, so a preset switch mid-prompt can't delete the
  wrong entry.
- Shift-clic on a totem slot in the mini links just that spell to
  chat (via a shared `insertOrOpenChat` helper: inserts at the
  cursor if a chat edit box is open, else opens a new one
  auto-prefixed with `/raid` or `/p`). Useful when a raid needs
  a single totem, not the whole sequence. Tooltip line added.
- Factored the share logic (`LinkToChat` + new `LinkTotemToChat`)
  behind the shared helper.

## 2026-04-20 — share sequence to chat

Scope: let the player broadcast the active preset to other shamans
in the group so the raid can diversify totems.

- New chrome button in the mini's bottom-left corner (symmetric
  with the lock in the bottom-right). Same hover-reveal pattern as
  the rest; icon is `UI-GuildButton-MOTD-Up` (scroll). Tooltip:
  "Partager la séquence dans le chat".
- `UI:LinkToChat` builds a space-separated string of
  `GetSpellLink(spellID)` for each non-empty slot in the active
  preset's sequence.
  - If a chat edit box is already open, insert at the cursor so
    the player keeps whatever channel they picked.
  - Otherwise call `ChatFrame_OpenChat(prefix .. text)` with an
    auto prefix: `/raid` in a raid, `/p` in a party, none solo.
- Clickable links on the receiving side — other shamans see the
  exact spells and can pick different ones.

## 2026-04-20 — respec-aware rescan + DB audit fix

Scope: real-shaman audit surfaced missing rank IDs and a respec
transient.

- Added `PLAYER_TALENT_UPDATE` listener and a second debounced
  scan (`scheduleRespecScan`, 2 s delay) alongside the existing
  0.3 s `SPELLS_CHANGED` debouncer. The spellbook briefly reads as
  half-empty during a respec; the fast scan can bake that stale
  state into `addon.known`. The late scan catches the settled
  spellbook so talent-gated totems (Totem of Wrath for Elemental,
  Mana Tide for Restoration) appear/disappear correctly after a
  respec without needing a `/reload`.
- `/totems debug` audit on KySeEtH's shaman (Enhancement + Resto
  spellbook) flagged three unmapped TBC Anniversary rank IDs —
  added to `TOTEM_DB`:
  - Windfury Totem: `25587`
  - Nature Resistance Totem: `25574`
  - Fire Nova Totem: `25547`

## 2026-04-20 — Details-inspired UI pass + preset rename

Scope: visual overhaul and final UX polish. The addon now looks
and behaves consistently with the Details addon style we took as
reference.

- Shared frame style via `SetBackdrop` (`BackdropTemplate` mixin):
  - `bgFile` = Blizzard's tiled `UI-Tooltip-Background` (subtle
    grain instead of a flat colored rectangle).
  - `edgeFile` = `WHITE8x8` at 1px, black 0.7 alpha — discreet.
  - Replaces the previous 1px spec-colored border which read as
    "painted rectangle".
- Chrome-on-hover pattern (both panels):
  - All meta controls (Close, Lock, and Gear on the mini) start at
    `SetAlpha(0)` and fade in when the mouse is over the frame or
    any chrome child. Throttled check every 100 ms via `OnUpdate`
    + `IsMouseOver` on the panel AND each chrome button (a single
    parent check flickered when the cursor entered a child that
    extended beyond the parent rect, like the close button).
  - Lock moved from a top-left checkbox to a 22×22 padlock in the
    bottom-right corner (Details pattern). Texture toggles between
    `LockButton-Locked-Up` and `LockButton-Unlocked-Up`; tooltip
    switches between "Verrouiller" / "Déverrouiller" based on state.
  - Masqués stays always visible on the main config (functional,
    not meta).
  - Mini's gear icon (top-left) opens the main config, matching
    the right-click fallback.
- Flat button / dropdown helpers:
  - `makeFlatButton` — dark-bg button with subtle hover highlight,
    centered text, no Blizzard tan template textures.
  - `makeFlatDropdown` — flat selector with centered text + golden
    expand-arrow, used by the mini AND the main panel's preset
    selector. Replaces the `UIDropDownMenuTemplate` whose outer
    visual ignored `SetWidth` (it overflowed the mini frame).
  - `<` / `>` column reorder arrows also converted to flat buttons.
  - Reset (s) input → plain `EditBox` with dark bg, no more gold
    `InputBoxTemplate` border.
- Rename preset: new "Renommer …" entry in the preset dropdown,
  visible only for non-Default presets. Popup pre-fills the current
  name, rejects empty / identical / duplicate names silently.
- Combat guard on the main panel:
  - `PLAYER_REGEN_DISABLED` hides the main config if it was open.
  - `UI:Toggle` refuses to open during combat with a chat notice.
  - The mini stays fully interactive — no secure attributes change
    when browsing it in combat.
- `UISpecialFrames`: ESC now closes the main config.
- Preset dropdown flat-ified on the main config, aligned on the
  same bottom baseline (`y = 8`, height 22) as the reset input,
  with both labels 2 px above their respective controls.
- Trimmed chat noise: removed success/error messages from the
  preset create and rename popups — effects are visible in the
  dropdown list, extra chat lines were clutter.

## 2026-04-19 — next-cast highlight + in-game test harness

Scope: show which totem will fire on the next keypress, and put
the cast-sequence advance logic under tests so this stays correct.

- Cast-sequence state mirror in Core.lua:
  - `addon.currentStep` tracks the next position (1..N) in the
    active sequence, where N = count of non-empty slots.
  - `UNIT_SPELLCAST_SUCCEEDED` listener advances `currentStep` when
    the fired spell matches the expected totem's `spellID`.
  - Wrap at the end of the sequence via `(step % len) + 1`. Holes
    in `preset.order` (no selection) shrink the cycle correctly.
  - `ApplyMacrotext` calls `ResetStep` since WoW's own castsequence
    state resets whenever the macrotext changes.
  - Idle reset: `C_Timer.After(resetTimer + 0.1)` after each cast;
    if no subsequent cast lands, `currentStep` goes back to 1.
- UI: new "next-cast" halo on the mini's current slot — warm yellow
  (1, 0.85, 0.2), 3px, drawn on BACKGROUND so the icon covers the
  middle. Distinct from the selection halo (which is spec-colored
  and lives on the main config columns).
- New file `Tests.lua` + `/totems test` slash command. 13 cases
  covering `SequenceLength`, `SlotForStep`, `NextCastSlot`, wrap,
  holes in the sequence (2-element and 1-element), empty sequence,
  `ResetStep`, and `OnSpellCast` with right/wrong spellIDs. Each
  case runs in a sandbox that swaps `TotemsDB` + `addon.known`
  and restores them — no side effects on the real state. Results
  printed to chat with PASS / FAIL color coding.

## 2026-04-19 — class guard

Scope: prevent the addon from doing anything on non-shaman alts.

- On `PLAYER_LOGIN`, check `UnitClass("player")`. If the class is
  not `SHAMAN`, call `DisableAddOn(ADDON)` (per-character state so
  the shaman stays enabled), print a one-line note, unregister all
  events, and return early. No UI, no secure button, no keybind
  override.

## 2026-04-19 — mini panel, UX pass, spec theming

Scope: making the addon usable day-to-day. The big config becomes a
rarely-opened editor; a small always-visible mini panel is the
primary interface.

- Mini panel (new primary UI):
  - Row of 4 totem icons (the current sequence) + custom preset
    selector button below.
  - Click an icon → dropdown of available totems for that element,
    restricted to non-hidden entries. Selecting one updates the
    macrotext in-place.
  - Drag an icon onto another → swap their positions in the
    sequence (reorder).
  - Right-click anywhere on the mini → opens the main config.
  - Top strip: Lock checkbox (shared state with the main config)
    and Blizzard close button. `/totems` toggles mini visibility.
    `/totems mini` alias removed.
  - Position persisted per character in `TotemsDB.ui.miniPos`.
- Preset management:
  - Dropdown now includes "Nouveau…" (opens the name prompt) and a
    red "Supprimer <preset>" entry (hidden when Default is active).
  - Removed the separate `New` / `Delete` footer buttons from the
    main config.
  - `PromptNewPreset` now reports success / empty-name / duplicate
    in chat instead of silently swallowing errors.
- Visual pass on both panels:
  - Ditched `BasicFrameTemplate` (ornate tan Blizzard look) in
    favor of a shared minimal dark backdrop.
  - Removed the 1px colored frame border (it looked like a painted
    rectangle). Spec color is now used only for the "Totems" title
    text and the selected-totem halo.
  - Selected-totem halo moved from OVERLAY to BACKGROUND so the
    icon sits on top of it — no more colored wash over the art.
    Full opacity, 3px thick, bright and readable.
  - Mini icons sit directly on the frame bg (removed redundant
    per-slot black squares).
  - Column `MAX_ROWS` reduced from 8 to 7 (kills the empty bottom
    row in the config panel).
  - Mini preset selector replaced with a custom button +
    expand-arrow glyph — `UIDropDownMenu_SetWidth` was silently
    ignored by the template's outer visual, making the dropdown
    overflow the mini frame on TBC Classic.
- Spec theming:
  - Accent color picked from the talent tab with the most points:
    Elemental blue, Enhancement orange, Restoration green. Falls
    back to class blue when no points are spent.
  - Re-applied on `CHARACTER_POINTS_CHANGED` so a respec updates
    the UI immediately.
  - `GetTalentTabInfo` can return an empty string for points spent
    on an untouched tab; wrapped in `tonumber(…) or 0`.
- Performance:
  - `SPELLS_CHANGED` coalesced into a single scan via a 300 ms
    `C_Timer.After` debounce — avoids rebuilding the `known` table
    5–10× on login and during talent swaps.
- Gotchas encountered (noted in memory):
  - `EasyMenu` is retail-only — replaced with
    `UIDropDownMenu_Initialize` + `ToggleDropDownMenu`.
  - `GetMouseFocus()` is retail-only — use `frame:IsMouseOver()`
    on each candidate instead.

## 2026-04-18 — spell DB audit + hide-totem feature

Scope: wave-2 polish after the first working build.

- Spell DB audit via `/totems debug` on KySeEtH's shaman: one bad ID
  (Frost Resistance Totem rank 4 was `25559`; real ID is `25560`).
  Fixed.
- Hide-totem feature:
  - Shift-clic on a totem icon hides it from the picker.
  - New "Masqués" button (top-right of the config window) opens a
    menu of currently hidden totems; click one to restore it.
  - Default hidden set seeded on first launch: Sentinelle (Air),
    Glèbe + Élémentaire de terre (Terre), Élémentaire de feu (Feu),
    Vague de mana (Eau). Stored per character in `TotemsDB.ui.hidden`.
  - Hiding the currently selected totem clears the selection so the
    generated macrotext stays consistent with what the picker shows.
- Gotcha encountered: `EasyMenu()` is retail-only; in TBC Classic
  it's `nil`. Rewrote the dropdown with `UIDropDownMenu_Initialize`
  + `ToggleDropDownMenu`.

## 2026-04-18 — first working build in-game

Scope: wave-2 smoke test. The addon now loads without errors on TBC
Classic 2.5.5 (Anniversary) and the bound key actually casts the
sequence.

- UI: made the config window movable with a persisted position per
  character and a Lock checkbox in the title bar (stored under
  `TotemsDB.ui`).
- Fixed three silent "bind fires but no cast" traps specific to TBC
  Classic (see `memory/tbc_secure_button_gotchas.md`):
  - Removed `Bindings.xml` from the TOC so WoW auto-loads it with
    the right XML schema (listing it in the TOC parses it as UI XML
    which doesn't know `<Binding>`).
  - Switched the keybind handler from a Lua-body `Click()` call
    (tainted — protected action blocked) to
    `SetOverrideBindingClick` applied on PLAYER_LOGIN and
    UPDATE_BINDINGS.
  - Gave the secure button a non-trivial size (32x32, parked off-
    screen, mouse disabled). 1x1 or hidden buttons silently drop
    the protected action.
- Dropped `LEARNED_SPELL_IN_TAB` event registration — it doesn't
  exist in TBC Classic 2.5.x. `SPELLS_CHANGED` alone is enough.

## 2026-04-18 — project init

Scope: scaffolding + addon skeleton + first working UI.

- Created project structure: `Totems/` (addon folder),
  `docs/project/`, `docs/user-guide/`, `CLAUDE.md`.
- Addon skeleton (`Totems.toc`, `Bindings.xml`, `Core.lua`,
  `UI.lua`):
  - Hardcoded TBC shaman totem spell ID database (by element, all
    ranks listed per totem so lower-level characters see the ranks
    they actually have).
  - Spellbook scan picks the highest-known rank per totem via
    `IsSpellKnown`.
  - Hidden `SecureActionButton` (`TotemsCastButton`) whose
    `macrotext` is (re)generated from the active preset.
    In-combat updates are deferred to `PLAYER_REGEN_ENABLED`.
  - Config window: 4 element columns, click a totem icon to
    select/unselect, `<` / `>` arrows to reorder columns
    (column order = castsequence order, left → right).
  - Preset dropdown at the bottom: New (clones active), Delete
    (can't delete `Default`), plus a reset-timer input (per preset).
  - Slash commands: `/totems` (open UI), `/totems debug` (list
    spellbook entries named "…totem…" whose spell ID is missing
    from the database — safety net for rank/ID gaps).
- Purpose: replace KySeEtH's hand-edited
  `/castsequence reset=10 T1,T2,T3,T4` macro with a UI where
  picking and reordering totems is a click operation.
- TOC `Interface: 20505` (TBC Anniversary, patch 2.5.5 — verified
  via web search). Client folder: `_anniversary_`.
- Not yet tested in-game.
