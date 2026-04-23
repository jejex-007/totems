# Totems — business rules (source of truth)

This document is the authoritative specification of what the addon
*must* do. It describes behavior in terms of rules, not Lua. If a
rule contradicts the code, the code is wrong and must be fixed.

Each rule has a stable ID (`BR-<section>-<n>`) so it can be cited
from tests and commits.

---

## 1. Eligibility

- **BR-ELIG-1** — The addon is only useful on the Shaman class
  (the only class with totems).
- **BR-ELIG-2** — On login, if the player's class is not Shaman,
  the addon disables itself for that character (per-character
  enable flag) and performs no other action that session.

---

## 2. Totem database

- **BR-DB-1** — The addon ships a hardcoded spell-ID table grouped
  by element (air / fire / earth / water). Each totem lists every
  known rank ID.
- **BR-DB-2** — A totem is considered *learned* for the current
  character when at least one of its rank IDs is in the spellbook.
  The *learned rank* is the highest-rank ID the character knows.
- **BR-DB-3** — The spellbook scan reads the localized spell name
  for each learned totem (used for macro text and tooltips).
- **BR-DB-4** — A totem that is not learned is never shown in the
  picker and never appears in any generated macro.
- **BR-DB-5** — `/totems debug` prints any spell in the spellbook
  whose localized name contains "totem" and whose spell ID is not
  in the database. This exists so missing rank IDs can be added to
  the database.

---

## 3. Presets

A *preset* is a named 4-element totem configuration plus cast
options. Presets are stored per character.

- **BR-PRESET-1** — There is always a preset named `Default`. It
  cannot be deleted. It cannot be renamed.
- **BR-PRESET-2** — On first install, `Default` is seeded with a
  sensible starter configuration (Mana Spring, Stoneskin,
  Windfury, Searing — order: water, earth, air, fire, reset timer
  10 s, twist off).
- **BR-PRESET-3** — Exactly one preset is *active* at a time.
  `TotemsDB.active` stores its name.
- **BR-PRESET-4** — If the saved active preset no longer exists
  (e.g. was deleted in a previous session via a version that
  allowed it), the active preset falls back to `Default`.
- **BR-PRESET-5** — Creating a new preset clones the current
  active one and saves it under a new name. The new preset becomes
  active.
- **BR-PRESET-6** — Preset names must be non-empty (after trim)
  and unique. Attempts to create/rename with an empty or colliding
  name are silently rejected.
- **BR-PRESET-7** — Renaming a preset is only allowed for
  non-Default presets. The popup pre-fills the current name.
- **BR-PRESET-8** — Deleting a preset requires a confirmation
  popup. The action references the preset name captured when the
  popup opened (so switching the active preset mid-popup cannot
  delete the wrong entry).
- **BR-PRESET-9** — Deleting the active preset makes `Default`
  active.

### 3.1 Preset schema

Each preset has the following fields:

| field         | meaning                                                                 |
|---------------|-------------------------------------------------------------------------|
| `order`       | Permutation of `{"air","fire","earth","water"}`. Position = cast order. |
| `selections`  | Map `element -> totem-key`. One totem per element; may be nil.          |
| `resetTimer`  | Seconds of idle before the sequence rewinds to step 1. Default 10.      |
| `twist`       | Boolean. Opts the preset in to the totem-twisting behavior (§ 8).       |

---

## 4. Sequence model

- **BR-SEQ-1** — The *sequence* of a preset is the ordered list of
  totems obtained by walking `preset.order` left-to-right and
  looking up `preset.selections[element]` in the learned set.
  Elements whose selection is nil or whose selected totem is not
  learned are skipped. Sequence length can be 0 to 4.
- **BR-SEQ-2** — The first keypress of a session, or the first
  keypress after an idle reset, casts the first element of the
  sequence.
- **BR-SEQ-3** — Each subsequent keypress casts the next element.
  After the last element, the next press wraps back to the first.
- **BR-SEQ-4** — If no keypress happens for `preset.resetTimer`
  seconds, the next press restarts at the first element.
- **BR-SEQ-5** — An empty sequence (0 totems) produces no cast.
  The keypress is a no-op.

---

## 5. Hidden totems

- **BR-HIDE-1** — Each character has a persistent set of *hidden*
  totem keys per element. Hidden totems are excluded from the
  picker and from selection menus.
- **BR-HIDE-2** — On first install, the hidden set is seeded with
  a default list (elementals, Earthbind, Sentry, Mana Tide —
  situational totems that are rarely part of a rotating sequence).
- **BR-HIDE-3** — Shift-click on a totem icon in the picker
  toggles its hidden flag.
- **BR-HIDE-4** — A dedicated "Masqués" menu lists every currently
  hidden totem across all elements; clicking one un-hides it.
- **BR-HIDE-5** — Hiding a totem that is currently selected clears
  that selection so the macro stays consistent with the visible
  picker.

---

## 6. Keybinding

- **BR-BIND-1** — The addon registers two Blizzard keybindings
  named:
  - "Cast next totem in sequence" under the `TOTEMS` header
  - "Reset twist" under the `TOTEMS` header (cf **BR-TWIST-9**)
  The user assigns a key via the Blizzard Key Bindings UI.
- **BR-BIND-2** — The keystroke is routed directly to a click on
  the hidden secure action button (via `SetOverrideBindingClick`).
  This preserves the hardware-event trust so the macro can perform
  protected actions (casting) in combat.
- **BR-BIND-3** — The override is re-applied on PLAYER_LOGIN and
  on UPDATE_BINDINGS. If the addon is in combat when a rebind
  happens, the re-apply is deferred to PLAYER_REGEN_ENABLED.

---

## 7. Next-cast highlight

- **BR-HL-1** — The mini panel highlights the slot containing the
  totem that the cast key will fire next.
- **BR-HL-2** — The highlight advances when `UNIT_SPELLCAST_SUCCEEDED`
  fires on the player with a spell ID that matches the expected
  next totem's rank ID. Mismatches (the player cast something else)
  do not advance the highlight.
- **BR-HL-3** — The highlight resets to slot 1 when the sequence
  changes (preset switch, selection change, reorder, rename)
  and after `preset.resetTimer` seconds of no matching cast.
- **BR-HL-4** — If the sequence is empty, no slot is highlighted.

---

## 8. Totem twisting (opt-in per preset)

*Totem twisting* is a technique used by shamans to keep Windfury
buff rolling while also running another air totem (Grace of Air,
Wrath of Air, etc.).

### 8.1 Applicability

- **BR-TWIST-1** — Twisting is an opt-in flag on the preset. When
  off, the cast flow is the normal sequence (§ 4).
- **BR-TWIST-2** — Twisting is only *applicable* when all of:
  - the preset's `twist` flag is on, AND
  - the selected air totem is not Windfury, AND
  - Windfury Totem is learned by the character, AND
  - an air totem is actually selected.
  If any is false, twisting behaves as off.

### 8.2 Cast flow when twisting is applicable

- **BR-TWIST-3** — The cast flow has two phases: *full* and *twist*.
- **BR-TWIST-4** — The *full* phase is the initial pull phase. It
  fires, in order:
  1. Windfury Totem,
  2. the selected totems in `preset.order` (4 casts, one per
     element — including the selected air totem, which replaces
     the Windfury dropped at step 1).
  Total: 5 casts.
- **BR-TWIST-5** — After the *full* phase completes, the state
  machine enters the *twist* phase on the next keypress.
- **BR-TWIST-6** — The *twist* phase alternates two casts forever,
  looping:
  1. Windfury Totem,
  2. the selected air totem.
- **BR-TWIST-7** — The phase transition is based on keypress
  count, not on the `/castsequence` reset timer. Reaching the end
  of the *full* phase always switches to *twist*, regardless of
  how fast or slow the presses were.
- **BR-TWIST-8** — The *twist* phase never switches back to *full*
  on its own. Only an explicit reset (§ 8.3) returns the state
  machine to *full*.

### 8.3 Reset triggers

- **BR-TWIST-9** — A UI button on the mini panel ("Reset twist")
  resets the state machine to the *full* phase at step 1. This
  button must work in combat.
- **BR-TWIST-10** — Detecting the player cast "Totem Recall"
  (Rappel de totem) resets the state machine to *full*.
  - Out of combat, the reset applies immediately.
  - In combat, the reset is skipped (a non-secure event handler
    cannot modify protected attributes in combat); the user must
    click the UI reset button.
- **BR-TWIST-11** — Switching preset, toggling the twist flag,
  changing a selection, or reordering the sequence resets the
  state machine to *full* at step 1 (because the underlying
  sequence changed).

### 8.4 UI affordances

- **BR-TWIST-UI-1** — The main config exposes a per-preset
  checkbox "Totem twisting (WF)". The checkbox is disabled and
  unchecked when the preset's current state makes twisting
  inapplicable (see BR-TWIST-2).
- **BR-TWIST-UI-2** — The mini panel only shows the "Reset twist"
  button when twisting is applicable for the active preset.
- **BR-TWIST-UI-4** — When twisting is applicable on the active
  preset, the mini panel shows a small Windfury-icon badge to the
  LEFT of slot 1 (the "twist badge"). It has three visual states:
  (a) no halo + countdown text = full phase, countdown shows
  seconds remaining before the next required WF cast;
  (b) blue halo around the icon = short phase (WF ↔ air loop);
  the blue lights up as soon as the LAST full-phase cast lands
  (count reaches `twist-full-len`), not one press later;
  (c) hidden = twist not applicable on the active preset.
  The badge and the per-slot next-cast highlight are mutually
  exclusive: the yellow slot-highlight shows only in full phase,
  the blue badge-halo shows only in short phase. All three reset
  triggers (mini button, Totem Recall, Reset-twist keybind) drop
  the halo immediately via a shared `OnTwistReset` post-click
  path.
- **BR-TWIST-UI-3** — When twisting is applicable AND the player
  has cast Windfury at least once AND 10 or more seconds have
  elapsed since that last Windfury cast, a pulsing Windfury icon
  appears at the user-configured position on screen as a
  "refresh Windfury now" indicator. The indicator clears the
  moment any of the reset triggers fires (BR-TWIST-9 mini button,
  BR-TWIST-10 Totem Recall, BR-TWIST-9bis Reset-twist keybind) or
  when the player casts Windfury again. When the main config is
  open and the active preset has twist applicable, the icon is
  also shown (solid, non-pulsing) so it can be repositioned once
  the window is unlocked; its position is persisted across
  sessions.

---

## 9. Spec theming

- **BR-THEME-1** — An accent color is picked based on the shaman
  spec: the talent tab with the most points spent (1=Elemental,
  2=Enhancement, 3=Restoration). A default class-blue is used
  when no points are spent.
- **BR-THEME-2** — The accent color is applied to: the main
  config's title text, the selected-totem halo in the main
  config's columns.
- **BR-THEME-3** — The accent refreshes on
  `CHARACTER_POINTS_CHANGED` and `PLAYER_TALENT_UPDATE`.

---

## 10. Spec change / respec

- **BR-RESPEC-1** — Some totems are talent-gated (Totem of Wrath
  requires Elemental 51 pts; Mana Tide requires Restoration 41
  pts). They must appear/disappear from the picker as the player
  respecs without requiring a `/reload`.
- **BR-RESPEC-2** — On `SPELLS_CHANGED`, `CHARACTER_POINTS_CHANGED`
  or `PLAYER_TALENT_UPDATE`, the spellbook is re-scanned. Because
  the spellbook reads as half-empty during the respec transient,
  the rescan is scheduled with a delay (~2 s) so it catches the
  settled state.

---

## 11. Group sharing

- **BR-SHARE-1** — The mini panel exposes a "Share" button that
  links the active preset's totems to the chat as clickable spell
  links.
- **BR-SHARE-2** — Behavior on click:
  - If a chat edit box is already open, the links are inserted at
    the cursor (the user keeps whatever channel is active).
  - Otherwise, a new chat edit box opens, pre-filled with the
    links and a channel prefix: `/raid` in a raid, `/p` in a
    party, nothing solo.
- **BR-SHARE-3** — Shift-click on a single slot in the mini
  performs the same share flow but with just that slot's totem
  link (useful when a raid only needs one totem clarified).

---

## 12. Mini panel

The mini panel is the primary interface for day-to-day use.

- **BR-MINI-1** — The mini is always visible by default. Its
  visibility state is persisted.
- **BR-MINI-2** — It shows a row of 4 icons (the current sequence,
  in cast order) plus a preset selector below.
- **BR-MINI-3** — Click on a slot opens a dropdown to change just
  that element's selected totem.
- **BR-MINI-4** — Drag a slot onto another swaps the two columns
  in `preset.order`.
- **BR-MINI-5** — Right-click anywhere on the mini opens the main
  config.
- **BR-MINI-6** — Chrome controls (Gear, Share, Reset twist,
  Close, Lock) fade in only while the mouse is over the mini or
  any of those controls.
- **BR-MINI-7** — The Lock toggles a persistent flag that freezes
  both panels' positions (dragging is disabled).
- **BR-MINI-8** — The Close button hides the mini (remembered
  across sessions). `/totems` toggles the mini back.
- **BR-MINI-9** — The preset selector lists every preset; picking
  one activates it. The list ends with a "Nouveau…" entry
  (creates a new preset), and when the active preset is not
  `Default`, also "Renommer …" and "Supprimer …" entries.

---

## 13. Main configuration panel

The main config is the editor view. It is opened on demand (via
`/totems`, the mini's Gear button, or right-click on the mini),
and is not meant to stay open during play.

- **BR-MAIN-1** — The main config is not a secure frame. It may
  be opened, closed, and interacted with freely out of combat.
- **BR-MAIN-2** — `/totems` (or any Toggle path) refuses to open
  the main config in combat and shows a one-line chat message.
- **BR-MAIN-3** — If the main config is open when combat starts
  (`PLAYER_REGEN_DISABLED`), it auto-hides.
- **BR-MAIN-4** — ESC closes the main config (it is registered in
  `UISpecialFrames`).
- **BR-MAIN-5** — The main config shows: 4 element columns (with
  `<`/`>` arrows to reorder), a preset selector, a reset-timer
  input, a "Totem twisting" checkbox, a "Masqués" button (always
  visible), and hover-revealed Close + Lock chrome.
- **BR-MAIN-6** — The selected totem in each column is rendered
  with a halo in the spec accent color; the non-selected totems
  are dimmed.

---

## 14. Persistence

All persistent state lives under `TotemsDB`, a
`SavedVariablesPerCharacter`.

| field                   | meaning                                              |
|-------------------------|------------------------------------------------------|
| `TotemsDB.presets[name]`| The preset data (see § 3.1).                         |
| `TotemsDB.active`       | Name of the active preset.                           |
| `TotemsDB.ui.locked`    | Lock flag (shared between mini and main).            |
| `TotemsDB.ui.pos`       | Saved position of the main config.                   |
| `TotemsDB.ui.miniPos`   | Saved position of the mini.                          |
| `TotemsDB.ui.miniShown` | Mini visibility. Default true.                       |
| `TotemsDB.ui.hidden`    | Per-element set of hidden totem keys.                |

- **BR-PERSIST-1** — Initialization backfills any field missing
  in older SavedVariables so upgrades do not lose data.

---

## 15. Combat safety

- **BR-COMBAT-1** — Protected attributes on the secure cast button
  (`macrotext`, `type`, `macrotext-full`, `macrotext-twist`,
  `twistMode`, `twistCount`) must not be modified from non-secure
  Lua context during combat lockdown. Deferred via a `pending`
  flag to `PLAYER_REGEN_ENABLED`.
- **BR-COMBAT-2** — In-combat state changes that happen through
  secure snippets (cast-click handlers, the Reset-twist secure
  button) are allowed because they run in a secure context
  initiated by user input.
- **BR-COMBAT-3** — The secure button must stay shown with a
  non-trivial size (≥ 1×1 is insufficient on TBC Classic; use
  32×32 off-screen) so protected clicks fire.

---

## 16. Slash commands

- **BR-SLASH-1** — `/totems` — toggle the mini panel visibility.
- **BR-SLASH-2** — `/totems debug` — list spellbook "totem"
  entries whose spell IDs are missing from the database.
- **BR-SLASH-3** — `/totems test` — run the in-game unit test
  harness. Prints per-case PASS/FAIL to the default chat frame.

---

## 17. Non-goals

- The addon does not implement group-buff tracking, duration
  timers, totem placement positioning, or anything beyond the
  macro generation + UX around it.
- The addon does not ship its own Ace3/LibStub-style library set;
  it sticks to the vanilla Blizzard API.
- The addon targets TBC Classic (interface 20505) only. Retail or
  Wrath Classic are out of scope.

---

## 18. Localization

- The addon uses localization in order to implement French, English and German by default.
- The localization is the one of Blizzard inreface, i.e. if the game is in French the addon is in French. Same for any languages.
- If Blizzard interface is in unknown language, the addon will default to English.
