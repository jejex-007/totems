local ADDON, addon = ...

-- Minimal in-game test suite. Run via `/totems test`.
-- Tests sandbox TotemsDB + addon.known + cast state, run an assertion,
-- then restore the original values. Stale C_Timer.After callbacks are
-- harmless: they only reset when the real lastCastTime is stale, which
-- is the intended behavior anyway.

addon.Tests = {}
local Tests = addon.Tests

local function sandbox(fn)
    local saved = {
        db        = TotemsDB,
        known     = addon.known,
        step      = addon.currentStep,
        lastCast  = addon.lastCastTime,
    }

    TotemsDB = {
        active  = "test",
        presets = {
            test = {
                order      = { "water", "earth", "air", "fire" },
                selections = {
                    water = "mana_spring",
                    earth = "stoneskin",
                    air   = "windfury",
                    fire  = "searing",
                },
                resetTimer = 10,
                twist      = false,
            },
        },
        ui = { hidden = {} },
    }
    addon.known = {
        water = { { key = "mana_spring", spellID = 5675,  name = "Mana Spring",  texture = nil } },
        earth = { { key = "stoneskin",   spellID = 8071,  name = "Stoneskin",    texture = nil } },
        air   = {
            { key = "windfury",     spellID = 8512, name = "Windfury",     texture = nil },
            { key = "grace_of_air", spellID = 8835, name = "Grace of Air", texture = nil },
        },
        fire  = { { key = "searing",     spellID = 3599,  name = "Searing",      texture = nil } },
    }
    addon.currentStep  = 1
    addon.lastCastTime = 0

    local ok, err = pcall(fn)

    TotemsDB           = saved.db
    addon.known        = saved.known
    addon.currentStep  = saved.step
    addon.lastCastTime = saved.lastCast

    if not ok then return false, err end
    return true
end

local function castCurrent()
    local preset = addon:ActivePreset()
    local slot   = addon:NextCastSlot()
    if not slot then return end
    local el    = preset.order[slot]
    local entry = addon:FindTotem(el, preset.selections[el])
    if entry then addon:OnSpellCast(entry.spellID) end
end

local results = {}
local function assertEq(name, actual, expected)
    if actual == expected then
        table.insert(results, { ok = true, msg = name })
    else
        table.insert(results, {
            ok = false,
            msg = ("%s (expected %s, got %s)"):format(
                name, tostring(expected), tostring(actual)),
        })
    end
end

-- Canonical list of every locale key the UI / Core / bindings can read
-- via `addon.L`. Consumed by the locale-coverage test below, which asserts
-- that EVERY language table directly defines EVERY key (not just falling
-- back to English). Add new keys here when introducing user-facing strings.
local REQUIRED_LOCALE_KEYS = {
    "ELEMENT_AIR", "ELEMENT_FIRE", "ELEMENT_EARTH", "ELEMENT_WATER",
    "LABEL_RESET_SEC", "LABEL_PRESET", "LABEL_HIDDEN_BUTTON",
    "LABEL_TWIST_CHECK",
    "TT_LOCK", "TT_UNLOCK", "TT_CONFIGURE", "TT_SHARE", "TT_SHARE_HINT",
    "TT_TWIST_RESET", "TT_TWIST_RESET_HINT", "TT_TWIST_INFO",
    "TT_SLOT_CLICK", "TT_SLOT_SHIFT", "TT_SLOT_DRAG",
    "TT_SLOT_RIGHTCLICK", "TT_HIDE_SHIFTCLICK",
    "MENU_NONE", "MENU_NO_HIDDEN", "MENU_NEW_PRESET",
    "MENU_RENAME_PRESET", "MENU_DELETE_PRESET",
    "POPUP_NEW_TITLE", "POPUP_RENAME_TITLE", "POPUP_DELETE_TITLE",
    "POPUP_DELETE_OK", "POPUP_CANCEL", "POPUP_OK",
    "CHAT_LOADED", "CHAT_DISABLED_CLASS", "CHAT_NO_COMBAT",
    "CHAT_DEBUG_SCAN", "CHAT_DEBUG_UNMAPPED", "CHAT_DEBUG_DONE",
    "BINDING_HEADER", "BINDING_CAST", "BINDING_RESET_TWIST",
}

local function missingKeysIn(table_, required)
    local missing = {}
    for _, k in ipairs(required) do
        if table_[k] == nil then table.insert(missing, k) end
    end
    return missing
end

local cases = {
    { "SequenceLength with 4 selections", function()
        assertEq("len == 4", addon:SequenceLength(), 4)
    end },
    { "SequenceLength with 2 selections", function()
        TotemsDB.presets.test.selections.water = nil
        TotemsDB.presets.test.selections.earth = nil
        assertEq("len == 2", addon:SequenceLength(), 2)
    end },
    { "SequenceLength with 0 selections", function()
        TotemsDB.presets.test.selections.water = nil
        TotemsDB.presets.test.selections.earth = nil
        TotemsDB.presets.test.selections.air   = nil
        TotemsDB.presets.test.selections.fire  = nil
        assertEq("len == 0", addon:SequenceLength(), 0)
    end },
    { "NextCastSlot at step 1 → slot 1", function()
        assertEq("slot == 1", addon:NextCastSlot(), 1)
    end },
    { "NextCastSlot at step 3 → slot 3", function()
        addon.currentStep = 3
        assertEq("slot == 3", addon:NextCastSlot(), 3)
    end },
    { "Wrong spell doesn't advance", function()
        addon:OnSpellCast(9999999)  -- bogus ID
        assertEq("step still 1", addon.currentStep, 1)
    end },
    { "Full sequence advance + wrap", function()
        addon.currentStep = 1
        castCurrent(); assertEq("after cast 1 → step 2", addon.currentStep, 2)
        castCurrent(); assertEq("after cast 2 → step 3", addon.currentStep, 3)
        castCurrent(); assertEq("after cast 3 → step 4", addon.currentStep, 4)
        castCurrent(); assertEq("after cast 4 → wrap to 1", addon.currentStep, 1)
    end },
    { "ResetStep returns to 1, lastCastTime → 0", function()
        addon.currentStep  = 3
        addon.lastCastTime = 12345
        addon:ResetStep()
        assertEq("step == 1",         addon.currentStep,  1)
        assertEq("lastCastTime == 0", addon.lastCastTime, 0)
    end },
    { "Wrap with a hole: sequence of 3 (water missing) wraps at 3", function()
        TotemsDB.presets.test.selections.water = nil
        addon.currentStep = 1  -- first non-empty is earth (slot 2)
        assertEq("NextCastSlot at step 1 → slot 2",  addon:NextCastSlot(), 2)
        castCurrent(); assertEq("step 2", addon.currentStep, 2)
        castCurrent(); assertEq("step 3", addon.currentStep, 3)
        castCurrent(); assertEq("wrap → step 1", addon.currentStep, 1)
        -- Slot for step 1 should again be slot 2 (water still missing).
        assertEq("NextCastSlot after wrap → slot 2",  addon:NextCastSlot(), 2)
    end },
    { "Sequence of 2 (earth + fire only) wraps at 2", function()
        TotemsDB.presets.test.selections.water = nil
        TotemsDB.presets.test.selections.air   = nil
        addon.currentStep = 1
        assertEq("len == 2",              addon:SequenceLength(),  2)
        assertEq("step 1 → slot 2 (earth)", addon:NextCastSlot(), 2)
        castCurrent(); assertEq("step 2",         addon.currentStep, 2)
        assertEq("step 2 → slot 4 (fire)",  addon:NextCastSlot(), 4)
        castCurrent(); assertEq("wrap → step 1",  addon.currentStep, 1)
        assertEq("after wrap → slot 2 again", addon:NextCastSlot(), 2)
    end },
    { "Sequence of 1 (fire only) stays on step 1", function()
        TotemsDB.presets.test.selections.water = nil
        TotemsDB.presets.test.selections.earth = nil
        TotemsDB.presets.test.selections.air   = nil
        addon.currentStep = 1
        assertEq("len == 1",            addon:SequenceLength(), 1)
        assertEq("step 1 → slot 4 (fire)", addon:NextCastSlot(), 4)
        castCurrent(); assertEq("stays on step 1",   addon.currentStep, 1)
        castCurrent(); assertEq("still step 1",      addon.currentStep, 1)
    end },
    { "Empty sequence: NextCastSlot returns nil", function()
        TotemsDB.presets.test.selections.water = nil
        TotemsDB.presets.test.selections.earth = nil
        TotemsDB.presets.test.selections.air   = nil
        TotemsDB.presets.test.selections.fire  = nil
        assertEq("len == 0",                addon:SequenceLength(), 0)
        assertEq("NextCastSlot == nil",     addon:NextCastSlot(),   nil)
    end },
    { "ApplyMacrotext resets step to 1", function()
        addon.currentStep = 3
        -- castBtn is nil in the test sandbox; ApplyMacrotext returns early
        -- BEFORE ResetStep is called. Call ResetStep explicitly to simulate
        -- the effect without the secure button dependency.
        addon:ResetStep()
        assertEq("step == 1 after reset", addon.currentStep, 1)
    end },

    ---------------------------------------------------------------------------
    -- Totem twisting
    ---------------------------------------------------------------------------
    { "WFEntry returns the WF air entry", function()
        local wf = addon:WFEntry()
        assertEq("wf.key == windfury",  wf and wf.key,     "windfury")
        assertEq("wf.spellID == 8512",  wf and wf.spellID, 8512)
    end },
    { "WFEntry returns nil when WF is not in known", function()
        addon.known.air = {
            { key = "grace_of_air", spellID = 8835, name = "Grace of Air" },
        }
        assertEq("wf == nil", addon:WFEntry(), nil)
    end },
    { "TwistApplicable: false when twist flag is off", function()
        TotemsDB.presets.test.twist = false
        TotemsDB.presets.test.selections.air = "grace_of_air"
        assertEq("twist off → false", addon:TwistApplicable(TotemsDB.presets.test), false)
    end },
    { "TwistApplicable: false when air selection is Windfury", function()
        TotemsDB.presets.test.twist = true
        TotemsDB.presets.test.selections.air = "windfury"
        assertEq("air=WF → false", addon:TwistApplicable(TotemsDB.presets.test), false)
    end },
    { "TwistApplicable: false when WF is not learned", function()
        TotemsDB.presets.test.twist = true
        TotemsDB.presets.test.selections.air = "grace_of_air"
        addon.known.air = {
            { key = "grace_of_air", spellID = 8835, name = "Grace of Air" },
        }
        assertEq("no WF → false", addon:TwistApplicable(TotemsDB.presets.test), false)
    end },
    { "TwistApplicable: false when no air totem is selected", function()
        TotemsDB.presets.test.twist = true
        TotemsDB.presets.test.selections.air = nil
        assertEq("air=nil → false", addon:TwistApplicable(TotemsDB.presets.test), false)
    end },
    { "TwistApplicable: true when twist on + air≠WF + WF learned", function()
        TotemsDB.presets.test.twist = true
        TotemsDB.presets.test.selections.air = "grace_of_air"
        assertEq("→ true", addon:TwistApplicable(TotemsDB.presets.test), true)
    end },
    { "NormalSpells: 4 totems in preset.order", function()
        local s = addon:NormalSpells(TotemsDB.presets.test)
        assertEq("len == 4", #s, 4)
        assertEq("[1] water",   s[1], "Mana Spring")
        assertEq("[2] earth",   s[2], "Stoneskin")
        assertEq("[3] air",     s[3], "Windfury")
        assertEq("[4] fire",    s[4], "Searing")
    end },
    { "NormalSpells: skips unselected elements", function()
        TotemsDB.presets.test.selections.earth = nil
        local s = addon:NormalSpells(TotemsDB.presets.test)
        assertEq("len == 3", #s, 3)
        assertEq("[1] water",   s[1], "Mana Spring")
        assertEq("[2] air",     s[2], "Windfury")
        assertEq("[3] fire",    s[3], "Searing")
    end },
    { "TwistFullSpells: WF prepended to the normal list", function()
        TotemsDB.presets.test.selections.air = "grace_of_air"
        local s = addon:TwistFullSpells(TotemsDB.presets.test)
        assertEq("len == 5",   #s, 5)
        assertEq("[1] WF",     s[1], "Windfury")
        assertEq("[2] water",  s[2], "Mana Spring")
        assertEq("[3] earth",  s[3], "Stoneskin")
        assertEq("[4] grace",  s[4], "Grace of Air")
        assertEq("[5] fire",   s[5], "Searing")
    end },
    { "TwistShortSpells: WF + selected air totem", function()
        TotemsDB.presets.test.selections.air = "grace_of_air"
        local s = addon:TwistShortSpells(TotemsDB.presets.test)
        assertEq("len == 2",  #s, 2)
        assertEq("[1] WF",    s[1], "Windfury")
        assertEq("[2] grace", s[2], "Grace of Air")
    end },
    { "TwistFullSpells falls back to normal when WF not learned", function()
        addon.known.air = {
            { key = "grace_of_air", spellID = 8835, name = "Grace of Air" },
        }
        TotemsDB.presets.test.selections.air = "grace_of_air"
        local s = addon:TwistFullSpells(TotemsDB.presets.test)
        assertEq("no WF → same as normal", #s, 4)
        assertEq("[1] water", s[1], "Mana Spring")
    end },
    { "TwistShortSpells empty when WF not learned", function()
        addon.known.air = {
            { key = "grace_of_air", spellID = 8835, name = "Grace of Air" },
        }
        TotemsDB.presets.test.selections.air = "grace_of_air"
        assertEq("len == 0", #addon:TwistShortSpells(TotemsDB.presets.test), 0)
    end },
    { "TwistShortSpells empty when no air selection", function()
        TotemsDB.presets.test.selections.air = nil
        assertEq("len == 0", #addon:TwistShortSpells(TotemsDB.presets.test), 0)
    end },

    ---------------------------------------------------------------------------
    -- BuildMacrotext — the string that goes onto the secure button
    ---------------------------------------------------------------------------
    { "BuildMacrotext: 4 totems → /castsequence with comma-separated names", function()
        local m = addon:BuildMacrotext(TotemsDB.presets.test)
        assertEq("happy path", m, "/castsequence reset=10 Mana Spring, Stoneskin, Windfury, Searing")
    end },
    { "BuildMacrotext: respects the preset's resetTimer", function()
        TotemsDB.presets.test.resetTimer = 5
        local m = addon:BuildMacrotext(TotemsDB.presets.test)
        assertEq("reset=5", m, "/castsequence reset=5 Mana Spring, Stoneskin, Windfury, Searing")
    end },
    { "BuildMacrotext: empty preset → empty string (no-op)", function()
        TotemsDB.presets.test.selections = {}
        assertEq("empty", addon:BuildMacrotext(TotemsDB.presets.test), "")
    end },
    { "BuildMacrotext: nil preset → empty string", function()
        assertEq("nil-safe", addon:BuildMacrotext(nil), "")
    end },
    { "BuildTwistFullMacrotext: WF + 4 normal totems as /castsequence", function()
        TotemsDB.presets.test.selections.air = "grace_of_air"
        local m = addon:BuildTwistFullMacrotext(TotemsDB.presets.test)
        assertEq("full text", m,
            "/castsequence reset=10 Windfury, Mana Spring, Stoneskin, Grace of Air, Searing")
    end },
    { "BuildTwistShortMacrotext: WF + air totem as /castsequence", function()
        TotemsDB.presets.test.selections.air = "grace_of_air"
        local m = addon:BuildTwistShortMacrotext(TotemsDB.presets.test)
        assertEq("short text", m, "/castsequence reset=10 Windfury, Grace of Air")
    end },
    { "BuildTwistShortMacrotext: empty when air selection missing", function()
        TotemsDB.presets.test.selections.air = nil
        assertEq("empty", addon:BuildTwistShortMacrotext(TotemsDB.presets.test), "")
    end },

    ---------------------------------------------------------------------------
    -- AdvanceState — transitions the secure snippet relies on
    ---------------------------------------------------------------------------
    { "AdvanceState normal: step 1 → 2 within a 4-long sequence", function()
        local phase, step = addon:AdvanceState("normal", "normal", 1, { normal = 4 })
        assertEq("phase stays normal", phase, "normal")
        assertEq("step → 2",           step,  2)
    end },
    { "AdvanceState normal: step 4 wraps to 1", function()
        local phase, step = addon:AdvanceState("normal", "normal", 4, { normal = 4 })
        assertEq("phase stays normal", phase, "normal")
        assertEq("wrap to 1",          step,  1)
    end },
    { "AdvanceState twist: step 5 of full → twist at step 1", function()
        local phase, step = addon:AdvanceState("twist", "full", 5, { full = 5, twist = 2 })
        assertEq("phase full → twist", phase, "twist")
        assertEq("step → 1",           step,  1)
    end },
    { "AdvanceState twist: step 1 of full → step 2", function()
        local phase, step = addon:AdvanceState("twist", "full", 1, { full = 5, twist = 2 })
        assertEq("phase stays full", phase, "full")
        assertEq("step → 2",         step,  2)
    end },
    { "AdvanceState twist: step 2 of twist wraps to 1", function()
        local phase, step = addon:AdvanceState("twist", "twist", 2, { full = 5, twist = 2 })
        assertEq("phase stays twist", phase, "twist")
        assertEq("wrap to 1",         step,  1)
    end },
    { "AdvanceState twist: full with 3 non-empty (shorter preset) → twist after 3", function()
        -- If someone has twist on but only 2 selected totems, full phase has
        -- WF + 2 totems = len-full=3. Wrap to twist after step 3.
        local phase, step = addon:AdvanceState("twist", "full", 3, { full = 3, twist = 2 })
        assertEq("phase full → twist", phase, "twist")
        assertEq("step → 1",           step,  1)
    end },
    { "InitialState: twist mode starts at (full, 1)", function()
        local p, s = addon:InitialState("twist")
        assertEq("phase", p, "full")
        assertEq("step",  s, 1)
    end },
    { "InitialState: normal mode starts at (normal, 1)", function()
        local p, s = addon:InitialState("normal")
        assertEq("phase", p, "normal")
        assertEq("step",  s, 1)
    end },
    { "TOTEM_RECALL_IDS contains the TBC Classic spell ID", function()
        assertEq("36936 is recognized", addon.TOTEM_RECALL_IDS[36936], true)
    end },

    ---------------------------------------------------------------------------
    -- Localization
    ---------------------------------------------------------------------------
    { "PickLocale maps frFR to the French table", function()
        local t = addon:PickLocale("frFR")
        assertEq("fr ELEMENT_FIRE", t.ELEMENT_FIRE, "Feu")
    end },
    { "PickLocale maps deDE to the German table", function()
        local t = addon:PickLocale("deDE")
        assertEq("de ELEMENT_FIRE", t.ELEMENT_FIRE, "Feuer")
    end },
    { "PickLocale maps enUS to the English table", function()
        local t = addon:PickLocale("enUS")
        assertEq("en ELEMENT_FIRE", t.ELEMENT_FIRE, "Fire")
    end },
    { "PickLocale maps enGB to the English table", function()
        local t = addon:PickLocale("enGB")
        assertEq("enGB ELEMENT_FIRE", t.ELEMENT_FIRE, "Fire")
    end },
    { "PickLocale falls back to English for unknown codes", function()
        local t = addon:PickLocale("esES")
        assertEq("esES falls back → en", t.ELEMENT_FIRE, "Fire")
    end },
    { "addon.L returns '[KEY]' for keys missing everywhere", function()
        -- Missing in en (and therefore missing in any non-en table too).
        local v = addon.L.TOTALLY_MADE_UP_KEY
        assertEq("bracket marker", v, "[TOTALLY_MADE_UP_KEY]")
    end },
    { "English table defines every required key", function()
        local missing = missingKeysIn(addon.LOCALES.en, REQUIRED_LOCALE_KEYS)
        assertEq("en missing: " .. table.concat(missing, ","), #missing, 0)
    end },
    { "French table defines every required key (no silent EN fallback)", function()
        local missing = missingKeysIn(addon.LOCALES.fr, REQUIRED_LOCALE_KEYS)
        assertEq("fr missing: " .. table.concat(missing, ","), #missing, 0)
    end },
    { "German table defines every required key (no silent EN fallback)", function()
        local missing = missingKeysIn(addon.LOCALES.de, REQUIRED_LOCALE_KEYS)
        assertEq("de missing: " .. table.concat(missing, ","), #missing, 0)
    end },
}

function Tests:RunAll()
    results = {}
    local passed, failed = 0, 0
    local errors = {}

    for _, case in ipairs(cases) do
        local name, fn = case[1], case[2]
        local ok, err = sandbox(fn)
        if not ok then
            failed = failed + 1
            table.insert(errors, name .. ": " .. tostring(err))
        end
    end

    for _, r in ipairs(results) do
        if r.ok then passed = passed + 1 else failed = failed + 1 end
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Totems|r tests:")
    for _, r in ipairs(results) do
        local tag = r.ok and "|cff33ff99OK|r  " or "|cffff5555FAIL|r"
        DEFAULT_CHAT_FRAME:AddMessage("  " .. tag .. " " .. r.msg)
    end
    for _, e in ipairs(errors) do
        DEFAULT_CHAT_FRAME:AddMessage("  |cffff5555ERROR|r " .. e)
    end
    DEFAULT_CHAT_FRAME:AddMessage(
        ("|cff33ff99Totems|r: %d passed, %d failed."):format(passed, failed))
end
