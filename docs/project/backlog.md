# Totems — backlog

Effort scale (real hours, KySeEtH + Claude pair):
S (< 1h) · M (1–2h) · L (3–5h) · XL (6–8h)

## Milestone 0.1 — MVP (tagged `v0.1.0` on 2026-04-23)

Goal: replace the hand-edited castsequence macro with a working
addon and a minimal config UI. Must work in-game on a shaman.
Scope grew beyond "minimal" during iteration (twist state machine,
floating WF indicator, totem timers, engineering standards, public
release). All shipped under the `v0.1.0` tag — see the changelog
entries dated 2026-04-18 through 2026-04-23 for detail.

### Wave 1 — foundation (done in this session)
- [x] Project scaffolding (TOC, Bindings, file layout) — S
- [x] Spell DB for TBC shaman totems (all ranks per totem) — S
- [x] Spellbook scan picking the highest-known rank per totem — S
- [x] SavedVariablesPerCharacter schema + Default preset — S
- [x] Hidden SecureActionButton + `macrotext` generation — S
- [x] Combat-safe macrotext updates (deferred to REGEN_ENABLED) — S
- [x] Slash commands `/totems` and `/totems debug` — S
- [x] Config UI: 4 element columns, click-to-select totem — M
- [x] Config UI: reorder columns via `<` / `>` arrows — S
- [x] Preset dropdown, create / delete, reset-timer input — S

### Wave 2 — validation & polish
- [x] In-game smoke test (pick 4 totems, bind key, cast sequence) — S
      (actual: ~1h; spent on three TBC-specific secure button traps —
      see `memory/tbc_secure_button_gotchas.md`)
- [x] Audit spell DB vs KySeEtH's actual spellbook via
      `/totems debug`; fix any wrong or missing rank IDs — S
      (1 bad ID: Frost Res. rank 4 was `25559`, real `25560`)
- [x] Hide unwanted totems from the picker (Shift-clic + "Masqués"
      menu; per-character defaults seeded) — S
- [x] Always-visible mini panel as primary UI: sequence icons,
      preset selector, reorder by drag, change totem per slot via
      dropdown, lock/close, `/totems` toggles it — M
- [x] UX pass: minimal dark styling, spec-colored accent, no frame
      borders, proper selection halo, custom preset selector to
      fix TBC dropdown overflow — M
- [x] Perf: debounce `SPELLS_CHANGED` rebuilds via
      `C_Timer.After(0.3)` — S
- [x] Guard: disable the addon for non-shaman characters at
      `PLAYER_LOGIN` — S
- [x] Next-cast highlight on the mini: warm-yellow halo on the slot
      that the cast key will fire next; advances on
      `UNIT_SPELLCAST_SUCCEEDED`, resets on macrotext change or
      after `resetTimer` idle — S
- [x] In-game unit tests (`/totems test`) for cast-sequence advance
      logic, wrap, and sequence holes — S
- [x] Rename preset (dropdown entry + popup, silent on invalid
      names) — S
- [x] Details-inspired visual pass: tiled `UI-Tooltip-Background`
      + 1 px black edge; chrome-on-hover (Close, Lock, Gear) with
      padlock in bottom-right; flat button/dropdown helpers —
      `<`/`>` arrows, Masqués, reset input, both preset selectors
      converted — M
- [x] Combat guard: main panel auto-hides on `PLAYER_REGEN_DISABLED`,
      `/totems` refuses to open the main config in combat — S
- [x] ESC closes the main config (`UISpecialFrames`) — S
- [x] Share the active sequence in chat for group coordination
      (chrome button bottom-left, spell-links pre-filled with
      `/raid` or `/p` prefix) — S
- [x] Confirmation popup before deleting a preset — S
- [x] Shift-clic on a mini slot links just that totem to chat — S
- [x] Spec-first refactor — phase 1: `docs/user-guide/business-rules.md`
      as authoritative spec (17 sections, BR IDs); `Locales.lua`
      with en/fr/de tables, `addon:PickLocale()`, `addon.L` with
      English fallback + `[KEY]` marker; every hardcoded French
      string in Core.lua and UI.lua routed through `addon.L`;
      tests cover locale mapping + key coverage (67 passing) — M
- [~] Spec-first refactor — phase 2: custom cast dispatch replacing
      `/castsequence` with a per-click secure snippet that composes
      `/cast <spell>` from a `(phase, step)` state machine.
      **Deferred (likely obsolete).** The motivation was to escape
      `/castsequence` quirks (macrotext-swap resets,
      preBody/postBody timing); phase C shipped the full twist
      state machine on top of `/castsequence` using a preBody
      wrap, so the quirks are navigated. Rebuilding the dispatch
      would be pure re-work with no user-visible benefit. Revisit
      only if a BR change requires something `/castsequence`
      genuinely cannot express — L
- [x] Spec-first refactor — phase 3: "Reset twist" keybinding per
      BR-BIND-1 (second `<Binding>` entry in Bindings.xml, a second
      invisible `SecureHandlerClickTemplate` button routed via
      `SetOverrideBindingClick`, shared `addon.RESET_TWIST_SNIPPET`
      reused by the mini-panel icon) — S
- [x] Re-audit DB on KySeEtH's own shaman after a spec change:
      added Windfury 25587, Nature Resistance 25574, Fire Nova
      25547 (TBC Anniversary ranks not in the initial DB) — S
- [x] Respec-aware rescan: `PLAYER_TALENT_UPDATE` +
      `scheduleRespecScan` (2 s delayed scan) so talent-gated
      totems pop in/out of the picker without `/reload` — S
- [ ] Re-audit DB on other shamans (different levels/accounts may
      still surface bad rank IDs) — S
- [x] Apply the same custom preset selector to the main config —
      S (shipped 2026-04-20 as part of the Details-inspired visual
      pass; `buildPresetDropdown` + `mainPresetMenu` using
      `makeFlatDropdown`).

### Wave 3 — twist state machine + secure cast rebuild
- [x] Phase A: diagnose silent cast failure on TBC Anniversary
      2.5.5; root cause `RegisterForClicks("AnyUp")` dropping the
      secure dispatch. Fix: `"AnyDown"` alone. Strip `Core.lua` to
      minimal hardcoded `/castsequence` to validate the plumbing
      before rebuilding dynamic logic. — M
- [x] Phase B: dynamic `/castsequence` from the active preset
      (`BuildMacrotext`). — S
- [x] Phase C: full twist state machine via
      `SecureHandlerWrapScript` preBody (postBody is silently
      dropped on `SecureActionButtonTemplate` clicks in 2.5.5 —
      verified with a heartbeat). — M
- [x] Second keybind "Reset twist" per BR-BIND-1. — S

### Wave 4 — WF refresh indicator + mini-panel polish
- [x] Windfury refresh warning: pulsing overlay when >=10 s since
      last WF cast in twist mode; initial red-border implementation
      superseded by the floating WF icon. — S
- [x] Floating WF icon (`TotemsWFIconFrame`): positionable,
      persisted in `TotemsDB.ui.wfIconPos`; visible on warning
      (pulsing) OR while the main config is open with a twist
      preset (solid, for repositioning). Red border removed. — S
- [x] Alphabetical preset ordering in both dropdowns. — S
- [x] Default element icons (generic shaman-school spell icons,
      NOT totem icons) faded on empty mini slots. — S
- [x] Active-totem countdown on each mini slot driven by
      `GetTotemInfo`, matched to preset slot by icon (locale-
      robust). — S
- [x] Class-guard fix on non-shaman alts: `DisableAddOn` → 
      `C_AddOns.DisableAddOn` fallback; clearer
      `CHAT_DISABLED_CLASS` message in en/fr/de. — S
- [x] Twist badge on the mini panel (BR-TWIST-UI-4): WF icon
      anchored left of slot 1 with a blue halo during the short
      phase, countdown overlay showing seconds before the next
      required WF cast. Halo lights up on the last full-phase
      press (UI anticipation — secure swap threshold unchanged).
      `addon:OnTwistReset()` helper centralises the post-reset
      cleanup so the halo drops immediately on any of the three
      reset paths. — S

### Wave 5 — public release + engineering standards + refactor
- [x] Public git repo `jejex-007/totems` with README + MIT LICENSE
      + `.gitignore`; per-repo git identity to keep the real name
      out of the public history; tag `v0.1.0`. — M
- [x] `engineering-standards.md` (NFR-*): second source of truth
      alongside `business-rules.md`. 12 categories with stable
      IDs and MUST/SHOULD/MAY status; Section 0 pins rules to the
      current client build with re-verification triggers; CLAUDE.md
      Definition of Done updated. — M
- [x] First refactor wave driven by the NFRs: position helpers
      consolidation, chrome hover helper extraction, defensive
      re-inits removal, 10+ magic numbers → named constants, full
      locale key coverage in tests, twistResetBtn guard removal
      (loud-fail). Plus dropdown toggle fix + click-outside-to-close
      via fullscreen click-catcher. — M

### Wave 6 — deferred P3 refactor items
All micro-wins, not worth a dedicated pass; pick up opportunistically
when adjacent code is touched for another reason.
- [ ] `FindTotem` memoization per preset (currently linear scan
      over `addon.known[element]` on each call; <10 entries per
      element, negligible at current scale). — S
- [ ] Unify `makeFlatButton` + `makeFlatDropdown` helpers (differ
      only in arrow presence and click behavior). — S
- [ ] Cache the sorted preset-name list in `dropdownInit` instead
      of rebuilding on each menu open; invalidate on preset
      add / rename / delete. — S
- [ ] Throttle the WF icon pulse `math.sin` update to every 2–3
      frames instead of every frame (imperceptible visual change,
      saves tiny amount of per-frame CPU). — S
- [ ] Full comment audit (NFR-MAINT-2): remove comments that only
      paraphrase the code; keep only the ones that document a
      non-obvious constraint or workaround. Do naturally as part
      of feature work rather than a dedicated pass. — S

## Milestone 0.2 — nice-to-haves

- [ ] Drag-and-drop column reorder (replace `<` / `>` arrows) — M
- [ ] Import / export preset as a string — S
- [x] Remember window position between sessions — S
      (shipped 2026-04-18 alongside the Lock checkbox)
- [ ] Per-preset keybinding (requires multiple secure buttons) — M
- [ ] Promote UI prefs (lock + window position) from
      `SavedVariablesPerCharacter` to `SavedVariables` so they're
      shared across all shamans on the account — S

## Open questions / deferred

- TOC Interface version: `20505` (TBC Anniversary, patch 2.5.5),
  verified via web search 2026-04-18. Re-check if Blizzard ships
  a 2.5.6+.
- Tranquil Air Totem (spell ID 25908): may be vanilla-only. Keep
  the entry; `/totems debug` will tell us in-game.
- Do we want per-talent-build preset auto-switching? Not v0.1.
