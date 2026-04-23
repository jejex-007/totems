# Totems — engineering standards (non-functional requirements)

Source of truth for **how** the code must be written. Paired with
[`business-rules.md`](business-rules.md), which defines **what** the
addon must do.

Every change should be evaluated against both documents before it
is considered done. Each rule has a stable `NFR-<category>-<n>` ID
so code review comments, backlog entries, and commit messages can
cite them by name.

Status values:
- **MUST** — violation is a bug; must fix before shipping.
- **SHOULD** — strong preference; deviate only with a written reason.
- **MAY** — guidance; follow when convenient.

---

## 0. Context — target game / client

These NFRs are written for a **specific** WoW flavor and client
build. API surface, secure-template quirks, locale tags, taint
rules, and even default font files differ between retail, Classic
Era, Wrath Classic, and TBC Classic. A rule that is correct on
one flavor may be wrong on another.

| Attribute                | Value                                    |
|--------------------------|------------------------------------------|
| Game flavor              | WoW Classic TBC (Burning Crusade)        |
| Variant                  | Anniversary                              |
| Patch                    | 2.5.5                                    |
| TOC `## Interface:`      | `20505`                                  |
| Client build (at spec-time) | `66765` (Mar 31 2026)                 |
| Install folder           | `World of Warcraft/_anniversary_/`       |
| Verify in-game with      | `/dump (select(4, GetBuildInfo()))`      |
| Context last verified on | `2026-04-23`                             |

**Scope of the NFRs:**
- Rules under **`NFR-SEC-*`**, **`NFR-COMPAT-*`**, and parts of
  **`NFR-COMBAT-*`** are pinned to the build above. They encode
  empirically-verified behavior that may not hold on retail or
  other Classic flavors (e.g. `RegisterForClicks("AnyDown")`
  alone, `SecureHandlerWrapScript` postBody silent-drop on
  `SecureActionButtonTemplate`, `C_AddOns.DisableAddOn`
  namespacing).
- Rules under **`NFR-PERF-*`**, **`NFR-MAINT-*`**, **`NFR-TEST-*`**,
  **`NFR-LOCALE-*`**, **`NFR-DATA-*`**, **`NFR-PRIV-*`**,
  **`NFR-DEP-*`** are largely version-agnostic and apply to any
  WoW addon.

**When the target changes** (Blizzard ships a new Anniversary
patch, or the addon is ported to Classic Era / retail):
1. Update this table with the new patch / build.
2. Re-verify every `NFR-SEC-*` / `NFR-COMPAT-*` rule on the new
   build. Keep the old rule with a note
   (*"verified last on 2.5.5 build 66765"*) rather than silently
   deleting it — the old behavior may return in a hotfix.
3. Record any delta as a new entry in
   `memory/tbc_secure_button_gotchas.md` (or its equivalent for
   the new flavor) with the build number.

The detailed empirical findings that back several NFR-SEC-* /
NFR-COMPAT-* rules live in
`memory/tbc_secure_button_gotchas.md`. That file is the
"story behind the rule"; this document is the concise rule itself.

---

## 1. Performance (NFR-PERF)

- **NFR-PERF-1** (MUST) — No `OnUpdate` handler may do heavy work
  every frame. Split into a per-frame path (lightweight — e.g.
  alpha pulse) and a throttled path (≥ 0.1 s) for anything
  involving table allocation, API calls, or state evaluation.
- **NFR-PERF-2** (MUST) — Prefer event-driven updates over polling.
  If a Blizzard event exists (`UNIT_SPELLCAST_SUCCEEDED`,
  `PLAYER_TOTEM_UPDATE`, `SPELLS_CHANGED`, …), register it rather
  than polling the corresponding API in `OnUpdate`.
- **NFR-PERF-3** (SHOULD) — Hot paths (anything called in `OnUpdate`
  or per keypress) must not allocate tables. Preallocate local
  tables at creation time, or mutate in place.
- **NFR-PERF-4** (SHOULD) — Debounce bursty events (e.g.
  `SPELLS_CHANGED` fires 5–10× at login). A `C_Timer.After(N)`
  coalesce is the canonical pattern.
- **NFR-PERF-5** (MAY) — Cache derived data that is expensive to
  compute and stable between invalidation events (e.g. a sorted
  preset-name list rebuilt only on create / rename / delete).

## 2. Combat safety (NFR-COMBAT)

- **NFR-COMBAT-1** (MUST) — Every write to a protected attribute
  (`SetAttribute` on a secure frame, `SetOverrideBindingClick`,
  `ClearOverrideBindings`, `CreateFrame` with a secure template)
  must be guarded by `InCombatLockdown()`.
- **NFR-COMBAT-2** (MUST) — When a protected write is blocked by
  combat, the code **must** queue it on a per-concern pending
  flag and re-apply it from `PLAYER_REGEN_ENABLED`. Setting a
  pending flag without re-applying is a bug.
- **NFR-COMBAT-3** (MUST) — The main config window auto-hides on
  `PLAYER_REGEN_DISABLED` (see BR-COMBAT-1). The mini panel may
  stay visible.
- **NFR-COMBAT-4** (SHOULD) — Reset buttons intended to work
  in-combat must be `SecureHandlerClickTemplate` frames with the
  protected mutation driven by `_onclick` snippets, not by Lua
  reacting to an insecure click.

## 3. Secure context (NFR-SEC)

- **NFR-SEC-1** (MUST) — Secure snippets (preBody / postBody /
  `_onclick`) may only call the restricted-environment whitelist.
  `GetTime`, `print`, and most globals are **not** available; test
  any new builtin on the target client before relying on it.
- **NFR-SEC-2** (MUST) — On TBC Classic 2.5.x,
  `SecureHandlerWrapScript` rejects `nil` for `preBody`. Pass
  `""` if only a postBody is desired.
- **NFR-SEC-3** (MUST) — Cast-dispatch buttons must use
  `RegisterForClicks("AnyDown")` alone. `"AnyUp"` silently drops
  the protected action; `("AnyUp","AnyDown")` double-fires
  `/castsequence`. See
  `memory/tbc_secure_button_gotchas.md` for the full rationale.
- **NFR-SEC-4** (MUST) — postBody on `SecureActionButtonTemplate`
  clicks is silently dropped on 2.5.5; put state-machine logic
  in preBody and adjust thresholds accordingly (e.g. `count > N`
  instead of `>=`).
- **NFR-SEC-5** (SHOULD) — Secure snippets that mutate attributes
  on another frame must store the target via
  `SetFrameRef("name", frame)` and read it via
  `self:GetFrameRef("name")`. Never assume a global exists inside
  a restricted snippet.
- **NFR-SEC-6** (MUST) — Key bindings must route through
  `SetOverrideBindingClick(owner, true, key, "ButtonName", "LeftButton")`.
  Calling `:Click()` from a Lua binding body runs in a tainted
  context and blocks the protected action.

## 4. Data (SavedVariables) (NFR-DATA)

- **NFR-DATA-1** (MUST) — SavedVariables schema changes ship with
  a migration in `InitDB`: default-initialize new keys, migrate
  renamed keys, and drop orphaned keys (e.g. `ui.hidden` entries
  for unlearned totems after a respec) no later than the next
  login.
- **NFR-DATA-2** (MUST) — Always `TotemsDB.x = TotemsDB.x or {}`
  before reading or writing nested fields. Never assume a key
  exists because it was initialized in a previous session.
- **NFR-DATA-3** (SHOULD) — Per-character state
  (`SavedVariablesPerCharacter`) is the default; promote to
  account-wide `SavedVariables` only when the value is truly
  account-global (window position, prefs).
- **NFR-DATA-4** (SHOULD) — Never store derived data that can be
  rebuilt from other state (e.g. sorted lists, indexes).

## 5. Event handling (NFR-EVT)

- **NFR-EVT-1** (MUST) — Register only the events the addon
  actually uses. No dead `RegisterEvent` calls.
- **NFR-EVT-2** (MUST) — Events that fire in bursts (`SPELLS_CHANGED`,
  `PLAYER_TOTEM_UPDATE`, `UNIT_SPELLCAST_SUCCEEDED`) must be
  debounced (`C_Timer.After`) if their handler does non-trivial
  work.
- **NFR-EVT-3** (SHOULD) — On `PLAYER_TALENT_UPDATE` /
  `CHARACTER_POINTS_CHANGED`, schedule a **second** spellbook
  rescan ~2 s later to catch the respec transient (the initial
  burst returns a half-empty spellbook).

## 6. Localization (NFR-LOCALE)

- **NFR-LOCALE-1** (MUST) — Every user-facing string (UI labels,
  tooltips, chat messages, popup titles, binding labels) must
  live in `Locales.lua` and be accessed via `addon.L.<KEY>`. No
  literal FR/EN/DE strings in `Core.lua` or `UI.lua`.
- **NFR-LOCALE-2** (MUST) — `addon.L` falls back to English when
  the active locale misses a key, and to `[KEY_NAME]` when
  English also misses it (bracketed so gaps are visible in-game).
- **NFR-LOCALE-3** (SHOULD) — The locale tests
  (`Tests.lua`) iterate every required key rather than spot-checking.
  A typo in any language's table must fail the suite.

## 7. API compatibility (NFR-COMPAT)

- **NFR-COMPAT-1** (MUST) — Target client is WoW Classic TBC
  Anniversary 2.5.5 (Interface `20505`, build 66765 as of
  2026-04-23). Any API use that differs from retail must be
  verified on this build.
- **NFR-COMPAT-2** (MUST) — Feature-detect Blizzard namespaces that
  changed in recent years (e.g. `C_AddOns.DisableAddOn` vs the
  flat `DisableAddOn`). Pattern:
  `local fn = (NS and NS.Func) or Func; if fn then fn(...) end`.
- **NFR-COMPAT-3** (MUST) — Do not use retail-only APIs (`EasyMenu`,
  `GetMouseFocus`, `LEARNED_SPELL_IN_TAB`) without a guard. See
  `memory/tbc_secure_button_gotchas.md`.
- **NFR-COMPAT-4** (SHOULD) — Bump the TOC `## Interface:` value
  on every client patch after verifying the addon still loads
  clean.
- **NFR-COMPAT-5** (MUST) — Before tagging any release version
  (`git tag -a vX.Y.Z`), re-verify every `NFR-SEC-*` and
  `NFR-COMPAT-*` rule on the current client build. Update
  Section 0's "Context" table with the new build number and
  verification date. If any empirical behavior changed, record
  it in `memory/tbc_secure_button_gotchas.md` and amend the
  corresponding NFR wording (keep the old note with a "verified
  last on &lt;build&gt;" tag rather than deleting it).
- **NFR-COMPAT-6** (SHOULD) — At the start of any working session
  that will touch secure code, version-sensitive APIs, or TOC
  metadata, confirm the build is still current. The trigger:
  the "Context last verified on" date in Section 0 is older than
  14 days, OR the maintainer mentions a recent client patch.
  The maintainer runs `/dump (select(4, GetBuildInfo()))`
  in-game; if the build differs from Section 0, refresh the
  table and re-verify the affected NFRs before making code
  changes.

## 8. UX conventions (NFR-UX)

- **NFR-UX-1** (MUST) — Slash commands follow `/<addon> [verb]`.
  Bare `/<addon>` toggles the primary UI; subcommands are
  space-separated (`/totems debug`, `/totems test`).
- **NFR-UX-2** (MUST) — Key bindings are declared in
  `Bindings.xml` with a no-op body (routed via
  `SetOverrideBindingClick`). Labels come from `addon.L` via
  `BINDING_NAME_<ID>` globals.
- **NFR-UX-3** (MUST) — `Bindings.xml` is auto-loaded from the
  addon root — **do not** list it in the TOC (the TOC's XML
  schema doesn't recognize `<Binding>` and throws errors).
- **NFR-UX-4** (SHOULD) — Windows are movable when unlocked and
  `SetClampedToScreen(true)` so they never drift off-screen.
  Position is persisted in `TotemsDB.ui.<frame>Pos`.
- **NFR-UX-5** (SHOULD) — The main config is registered in
  `UISpecialFrames` so ESC closes it.
- **NFR-UX-6** (SHOULD) — Hover-revealed chrome (close / lock /
  gear) uses a single throttled `OnUpdate` that polls
  `IsMouseOver` on parent + chrome children (MouseIsOver alone
  flickers around child buttons that extend past the parent rect).

## 9. Testability (NFR-TEST)

- **NFR-TEST-1** (MUST) — Business logic must be expressed as
  **pure functions** (no Blizzard API calls, no global state
  beyond `addon.known` / `TotemsDB`) so `Tests.lua` can exercise
  them by sandboxing the inputs.
- **NFR-TEST-2** (MUST) — Every pure function in `Core.lua` has
  at least one test in `Tests.lua`. Coverage is tracked by the
  test-name convention (function name in the test label).
- **NFR-TEST-3** (SHOULD) — Secure-snippet behavior that can't be
  unit-tested (preBody transitions, postBody drops) must have a
  pure-function mirror (`AdvanceState`, `NormalSpells`, etc.)
  that IS tested, plus an in-game validation note in the
  changelog.
- **NFR-TEST-4** (SHOULD) — Tests stub Blizzard API calls when
  they are the unit under test (e.g. stub `GetTotemInfo` to
  drive the timer matching).

## 10. Maintainability (NFR-MAINT)

- **NFR-MAINT-1** (MUST) — Code, comments, and docs are in
  English. French is only for in-game UI strings (via locales)
  and the chat with the author.
- **NFR-MAINT-2** (MUST) — Comments explain the *why* (non-obvious
  constraint, workaround reason), never the *what* (what the code
  does — the code itself does). Remove comments that only paraphrase
  the code.
- **NFR-MAINT-3** (SHOULD) — File size: no single file should
  exceed ~1500 lines. When a file grows past that, extract
  cohesive sections (e.g. a new `Secure.lua` if Core grows).
- **NFR-MAINT-4** (SHOULD) — No OOP (metatable `__index` chains
  for class hierarchies) unless a feature genuinely requires it.
  Tables-as-records + functions on `addon` are enough.
- **NFR-MAINT-5** (SHOULD) — Factor identical patterns (position
  save/restore for three panels, tooltip setup, secure snippet
  text) into shared helpers. Two occurrences = acceptable;
  three = refactor.
- **NFR-MAINT-6** (SHOULD) — No magic numbers. Each duration
  threshold, size constant, or frequency belongs in a named
  constant at the top of its file or on `addon` (e.g.
  `addon.WF_REFRESH_THRESHOLD`, `MINI_W`).
- **NFR-MAINT-7** (MAY) — Prefer `snake_case` for SavedVariables
  keys, `camelCase` for Lua locals, `PascalCase` for functions on
  `addon`. Stay consistent within a file.

## 11. Privacy (NFR-PRIV)

- **NFR-PRIV-1** (MUST) — This repo is public
  (https://github.com/jejex-007/totems). The author's full real
  name must never appear in any tracked file. Use `KySeEtH` for
  attribution and `jejex-007` for GitHub references.
- **NFR-PRIV-2** (MUST) — Per-repo git identity is set to
  `user.name = jejex-007` and
  `user.email = jejex-007@users.noreply.github.com`. Do not
  revert to global identity.
- **NFR-PRIV-3** (MUST) — `.claude/` (local tooling settings
  with machine paths) is in `.gitignore` and must stay there.
- **NFR-PRIV-4** (MUST) — Before every push, grep the tree for
  the real name / real email. Remediate any match before the
  push.

## 12. Dependencies (NFR-DEP)

- **NFR-DEP-1** (SHOULD) — No external libraries (Ace3, LibStub,
  LibSharedMedia, …) in v0.1. The codebase is small; vanilla
  Blizzard API keeps it portable and avoids library-version drift.
- **NFR-DEP-2** (MUST) — Any future dependency must be declared
  in the TOC (`## OptionalDeps:` / `## Dependencies:`) and loaded
  defensively (`if LibStub then …`).

---

## Cross-reference

When a change is reviewed or planned, cite the rule: e.g.
"Fixes NFR-COMBAT-2 (keybind rebind lost in combat)" or
"Adds NFR-TEST-3 compliance by mirroring the new twist transition
in `AdvanceState`". This keeps reviews grounded in a shared
vocabulary instead of relying on case-by-case judgement.
