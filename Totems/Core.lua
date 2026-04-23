local ADDON, addon = ...

-------------------------------------------------------------------------------
-- Static configuration
-------------------------------------------------------------------------------

addon.ELEMENTS = { "air", "fire", "earth", "water" }

-- Localized labels rebuilt here so accessing addon.ELEMENT_LABEL still works
-- as before. All string content lives in Locales.lua.
addon.ELEMENT_LABEL = {
    air   = addon.L.ELEMENT_AIR,
    fire  = addon.L.ELEMENT_FIRE,
    earth = addon.L.ELEMENT_EARTH,
    water = addon.L.ELEMENT_WATER,
}

-- Default icon per element, used as a faded placeholder on mini-panel slots
-- that have no totem selected. These are generic element icons (NOT totem
-- icons) so an empty slot can't be confused with a real totem.
addon.ELEMENT_ICON = {
    air   = "Interface\\Icons\\Spell_Nature_LightningShield",
    fire  = "Interface\\Icons\\Spell_Fire_Fire",
    earth = "Interface\\Icons\\Spell_Nature_EarthShock",
    water = "Interface\\Icons\\Spell_Frost_FrostShock",
}

addon.BRAND = "|cff33ff99Totems|r"
local BRAND = addon.BRAND

-- Totems hidden by default from the picker. Players typically don't want
-- these in a rotating castsequence (elementals are long-cooldown summons,
-- Earthbind / Sentry / Mana Tide are situational). The user can unhide any
-- of them via the "Masqués" menu, and hide others with Shift-click.
addon.HIDDEN_DEFAULTS = {
    air   = { sentry       = true },
    earth = { earthbind    = true, earth_elem = true },
    fire  = { fire_elem    = true },
    water = { mana_tide    = true },
}

-- Spell IDs for Totem Recall (Rappel de totem). Casting this wipes every
-- summoned totem; when detected, we reset the twist state machine so the
-- next keypress starts a fresh "WF + 4 normal" sequence.
addon.TOTEM_RECALL_IDS = {
    [36936] = true,  -- TBC Classic
}

-- Panel accent color per shaman spec (the tab with the most points wins).
-- Falls back to the class blue when no points have been spent yet.
addon.SPEC_COLORS = {
    [1] = { r = 0.30, g = 0.60, b = 1.00 },  -- Elemental  — blue
    [2] = { r = 1.00, g = 0.50, b = 0.20 },  -- Enhancement — orange
    [3] = { r = 0.30, g = 0.85, b = 0.40 },  -- Restoration — green
    default = { r = 0.00, g = 0.44, b = 0.87 },
}

function addon:GetSpec()
    local best, bestPoints = nil, 0
    for i = 1, 3 do
        local _, _, pointsSpent = GetTalentTabInfo(i)
        pointsSpent = tonumber(pointsSpent) or 0
        if pointsSpent > bestPoints then
            bestPoints = pointsSpent
            best = i
        end
    end
    return best  -- nil = no talent points spent yet
end

function addon:SpecColor()
    return self.SPEC_COLORS[self:GetSpec()] or self.SPEC_COLORS.default
end

-- TBC Classic shaman totem spell IDs grouped by element.
-- Each entry lists all known rank IDs; the scan picks the highest rank the
-- player actually knows. If a totem is missing, `/totems debug` prints its
-- spell ID so it can be added here and reloaded.
addon.TOTEM_DB = {
    earth = {
        { key = "earthbind",  ranks = { 2484 } },
        { key = "stoneclaw",  ranks = { 5730, 6390, 6391, 6392, 10427, 10428, 25525 } },
        { key = "stoneskin",  ranks = { 8071, 8154, 8155, 10406, 10407, 10408, 25508, 25509 } },
        { key = "strength",   ranks = { 8075, 8160, 8161, 10442, 25361, 25528 } },
        { key = "tremor",     ranks = { 8143 } },
        { key = "earth_elem", ranks = { 2062 } },
    },
    fire = {
        { key = "searing",     ranks = { 3599, 6363, 6364, 6365, 10437, 10438, 25533 } },
        { key = "fire_nova",   ranks = { 1535, 8498, 8499, 11314, 11315, 25546, 25547 } },
        { key = "magma",       ranks = { 8190, 10585, 10586, 10587, 25552 } },
        { key = "flametongue", ranks = { 8227, 8249, 10526, 16387, 25557 } },
        { key = "frost_res",   ranks = { 8181, 10478, 10479, 25560 } },
        { key = "wrath",       ranks = { 30706 } },
        { key = "fire_elem",   ranks = { 2894 } },
    },
    water = {
        { key = "healing_stream", ranks = { 5394, 6375, 6377, 10462, 10463, 25567 } },
        { key = "mana_spring",    ranks = { 5675, 10495, 10496, 10497, 25570 } },
        { key = "mana_tide",      ranks = { 16190, 16191, 17359 } },
        { key = "poison_cleans",  ranks = { 8166 } },
        { key = "disease_cleans", ranks = { 8170 } },
        { key = "fire_res",       ranks = { 8184, 10537, 10538, 25563 } },
    },
    air = {
        { key = "windfury",     ranks = { 8512, 10613, 10614, 25585, 25587 } },
        { key = "grace_of_air", ranks = { 8835, 10626, 25359 } },
        { key = "tranquil_air", ranks = { 25908 } },
        { key = "windwall",     ranks = { 15107, 15111, 15112, 25577 } },
        { key = "nature_res",   ranks = { 10595, 10600, 10601, 25573, 25574 } },
        { key = "grounding",    ranks = { 8177 } },
        { key = "wrath_of_air", ranks = { 3738 } },
        { key = "sentry",       ranks = { 6495 } },
    },
}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

addon.known          = {}    -- element -> array of { spellID, name, texture, key }
addon.pending        = false -- true if a macrotext update is queued for out-of-combat
addon.currentStep    = 1     -- next slot (in preset.order) the cast key will fire
addon.lastCastTime   = 0
addon.lastWFCastTime = 0     -- GetTime() of the last Windfury cast; 0 = never

-- Seconds after the last Windfury cast at which the mini panel starts
-- flashing a red warning edge (in twist mode). The idea is to signal
-- "refresh WF soon" before the totem's pulse window lapses.
addon.WF_REFRESH_THRESHOLD = 10

-- Default fallback when a preset's `resetTimer` is nil (new preset / legacy
-- SavedVariables). Matches the `/castsequence reset=N` semantics.
addon.DEFAULT_RESET_TIMER = 10

-- Event-debounce windows (seconds). `SPELLS_CHANGED` fires in bursts
-- at login / level-up / rank learn — coalesce. After a respec, the
-- spellbook is transiently half-empty; the 2 s second-scan catches the
-- settled state so we don't bake stale data into `addon.known`.
local SPELLS_CHANGED_DEBOUNCE = 0.3
local RESPEC_SCAN_DELAY       = 2

-- Off-screen offset used to park invisible secure buttons outside the
-- visible area while keeping them Shown (`Hide()` would drop protected
-- actions). Applied as `-OFFSCREEN_OFFSET, OFFSCREEN_OFFSET` so the
-- frame sits at the top-left corner of UIParent minus this distance.
local OFFSCREEN_OFFSET = 9999

local castBtn  -- SecureActionButton, created on PLAYER_LOGIN
local resetBtn -- SecureHandlerClickTemplate, target of TOTEMS_RESET_TWIST binding

-- Shared snippet (secure). Called from the mini-panel Reset icon AND from
-- the Reset-twist keybind's invisible secure button. Both route here so the
-- attribute mutation is defined once and always in sync. Expects the caller
-- to have registered the cast button via `SetFrameRef("castBtn", castBtn)`.
addon.RESET_TWIST_SNIPPET = [[
    local cb = self:GetFrameRef("castBtn")
    if cb and cb:GetAttribute("twist-mode") ~= nil then
        cb:SetAttribute("twist-mode",  "full")
        cb:SetAttribute("twist-count", 0)
        cb:SetAttribute("macrotext",   cb:GetAttribute("macrotext-full") or "")
    end
]]

-------------------------------------------------------------------------------
-- Spellbook scan
-------------------------------------------------------------------------------

local function highestKnown(ranks)
    local found
    for i = 1, #ranks do
        if IsSpellKnown(ranks[i]) then found = ranks[i] end
    end
    return found
end

function addon:ScanKnownTotems()
    local known = {}
    for _, element in ipairs(self.ELEMENTS) do
        known[element] = {}
        for _, t in ipairs(self.TOTEM_DB[element]) do
            local id = highestKnown(t.ranks)
            if id then
                local name, _, icon = GetSpellInfo(id)
                if name then
                    table.insert(known[element], {
                        spellID = id,
                        name    = name,
                        texture = icon,
                        key     = t.key,
                    })
                end
            end
        end
    end
    self.known = known
end

function addon:FindTotem(element, key)
    if not element or not key then return nil end
    for _, entry in ipairs(self.known[element] or {}) do
        if entry.key == key then return entry end
    end
    return nil
end

-------------------------------------------------------------------------------
-- SavedVariables / presets
-------------------------------------------------------------------------------

local function defaultPreset()
    return {
        -- Left-to-right = castsequence order. Default matches KySeEtH's
        -- existing macro: Mana Spring (water), Stoneskin (earth),
        -- Windfury (air), Searing (fire).
        order      = { "water", "earth", "air", "fire" },
        selections = {
            water = "mana_spring",
            earth = "stoneskin",
            air   = "windfury",
            fire  = "searing",
        },
        resetTimer = 10,
        twist      = false,
    }
end

function addon:InitDB()
    TotemsDB = TotemsDB or {}
    TotemsDB.presets = TotemsDB.presets or {}
    if not TotemsDB.presets.Default then
        TotemsDB.presets.Default = defaultPreset()
    end
    TotemsDB.active = TotemsDB.active or "Default"
    if not TotemsDB.presets[TotemsDB.active] then
        TotemsDB.active = "Default"
    end
    -- Backfill `twist` on presets saved by earlier versions.
    for _, p in pairs(TotemsDB.presets) do
        if p.twist == nil then p.twist = false end
    end
    TotemsDB.ui = TotemsDB.ui or { locked = false, pos = nil }
    if TotemsDB.ui.miniShown == nil then TotemsDB.ui.miniShown = true end
    if not TotemsDB.ui.hidden then
        TotemsDB.ui.hidden = {}
        for element, set in pairs(self.HIDDEN_DEFAULTS) do
            TotemsDB.ui.hidden[element] = {}
            for key, _ in pairs(set) do
                TotemsDB.ui.hidden[element][key] = true
            end
        end
    end
end

function addon:ActivePreset()
    return TotemsDB.presets[TotemsDB.active]
end

-------------------------------------------------------------------------------
-- Secure button + macrotext
-------------------------------------------------------------------------------

-- Windfury Totem entry from the learned list, or nil if the player doesn't
-- have it yet.
function addon:WFEntry()
    for _, entry in ipairs(self.known.air or {}) do
        if entry.key == "windfury" then return entry end
    end
    return nil
end

-- Twisting only makes sense when the preset opts in AND the selected air
-- totem is something OTHER than Windfury AND Windfury is learned.
function addon:TwistApplicable(preset)
    if not preset or not preset.twist then return false end
    if preset.selections.air == "windfury" then return false end
    if not self:WFEntry() then return false end
    if not self:FindTotem("air", preset.selections.air) then return false end
    return true
end

-- Pure: build the ordered list of spell names for the "normal" (non-twisting)
-- sequence — just the selected totems in preset.order, skipping empty slots.
function addon:NormalSpells(preset)
    local names = {}
    if not preset then return names end
    for _, element in ipairs(preset.order) do
        local entry = self:FindTotem(element, preset.selections[element])
        if entry then table.insert(names, entry.name) end
    end
    return names
end

-- Pure: twist "full" phase = WF + the 4 normal totems (5 casts).
function addon:TwistFullSpells(preset)
    local wf = self:WFEntry()
    if not preset or not wf then return self:NormalSpells(preset) end
    local names = { wf.name }
    for _, element in ipairs(preset.order) do
        local entry = self:FindTotem(element, preset.selections[element])
        if entry then table.insert(names, entry.name) end
    end
    return names
end

-- Pure: twist "short" phase = WF and the selected air totem (2 casts, loops).
function addon:TwistShortSpells(preset)
    local wf = self:WFEntry()
    local airEntry = preset and self:FindTotem("air", preset.selections.air)
    if not wf or not airEntry then return {} end
    return { wf.name, airEntry.name }
end

-- Pure: compute the next (phase, step) given the current state and the
-- lengths of each phase. Drives both the Lua tests and, indirectly, the
-- secure snippet (which reimplements the same transitions).
function addon:AdvanceState(mode, phase, step, lens)
    local len = lens[phase] or 0
    local nextStep = step + 1
    if nextStep > len then
        if mode == "twist" and phase == "full" then
            return "twist", 1
        end
        return phase, 1  -- wrap within the current phase
    end
    return phase, nextStep
end

-- Pure: initial (phase, step) for a given mode.
function addon:InitialState(mode)
    if mode == "twist" then return "full", 1 end
    return "normal", 1
end

-- Dynamic `/castsequence` built from the active preset.
--
-- Three build variants:
-- - `BuildMacrotext`          : plain mode (preset.order → comma list).
-- - `BuildTwistFullMacrotext` : twist phase 1 (WF + normal list, 5 casts).
-- - `BuildTwistShortMacrotext`: twist phase 2 (WF + air totem, loops).
--
-- In twist mode we pre-compute both `macrotext-full` and `macrotext-short`
-- on the secure button. A postBody wrap script swaps the live `macrotext`
-- from full to short once the full phase has played through, giving the
-- keybind a single unified entry point that "does the right thing" on
-- each press without Lua-side state (secure-safe in combat).
local function sequenceText(reset, names)
    if not names or #names == 0 then return "" end
    return "/castsequence reset=" .. reset .. " " .. table.concat(names, ", ")
end

function addon:BuildMacrotext(preset)
    if not preset then return "" end
    return sequenceText(preset.resetTimer or addon.DEFAULT_RESET_TIMER, self:NormalSpells(preset))
end

function addon:BuildTwistFullMacrotext(preset)
    if not preset then return "" end
    return sequenceText(preset.resetTimer or addon.DEFAULT_RESET_TIMER, self:TwistFullSpells(preset))
end

function addon:BuildTwistShortMacrotext(preset)
    if not preset then return "" end
    return sequenceText(preset.resetTimer or addon.DEFAULT_RESET_TIMER, self:TwistShortSpells(preset))
end

function addon:ApplyMacrotext()
    if not castBtn then return end
    if InCombatLockdown() then
        self.pending = true
        return
    end
    local preset = self:ActivePreset()
    castBtn:SetAttribute("type", "macro")
    if self:TwistApplicable(preset) then
        local fullText  = self:BuildTwistFullMacrotext(preset)
        local shortText = self:BuildTwistShortMacrotext(preset)
        castBtn:SetAttribute("twist-mode",      "full")
        castBtn:SetAttribute("twist-count",     0)
        castBtn:SetAttribute("twist-full-len",  #self:TwistFullSpells(preset))
        castBtn:SetAttribute("macrotext-full",  fullText)
        castBtn:SetAttribute("macrotext-short", shortText)
        castBtn:SetAttribute("macrotext",       fullText)
    else
        castBtn:SetAttribute("twist-mode",      nil)
        castBtn:SetAttribute("twist-count",     nil)
        castBtn:SetAttribute("twist-full-len",  nil)
        castBtn:SetAttribute("macrotext-full",  nil)
        castBtn:SetAttribute("macrotext-short", nil)
        castBtn:SetAttribute("macrotext",       self:BuildMacrotext(preset))
    end
    self.pending = false
    self:ResetStep()
end

-- Non-secure cleanup after any twist reset (Lua path via Totem Recall,
-- secure path via the UI button, or secure path via the Reset-twist
-- keybind). The secure path has already mutated the protected attributes
-- via `addon.RESET_TWIST_SNIPPET`; the HookScript on each reset button
-- then calls this. The Lua path does its own attribute mutation and
-- calls this at the end. Clears the WF refresh timer and refreshes the
-- mini so the halo turns off immediately rather than waiting for the
-- next matching cast.
function addon:OnTwistReset()
    self.lastWFCastTime = 0
    if self.UI and self.UI.RefreshMini then self.UI:RefreshMini() end
end

-- Restore the twist state machine to the "full" phase (for the next pull).
-- Out of combat only — in combat, the user clicks the secure Reset button
-- in the mini chrome (its snippet mutates these same attributes safely).
function addon:ResetTwist()
    if not castBtn then return end
    if InCombatLockdown() then return end
    if castBtn:GetAttribute("twist-mode") == nil then return end
    castBtn:SetAttribute("twist-mode",  "full")
    castBtn:SetAttribute("twist-count", 0)
    castBtn:SetAttribute("macrotext",   self:BuildTwistFullMacrotext(self:ActivePreset()))
    self:OnTwistReset()
end

-- Number of non-empty slots in the active preset's sequence.
function addon:SequenceLength()
    local preset = self:ActivePreset()
    if not preset then return 0 end
    local n = 0
    for _, el in ipairs(preset.order) do
        if self:FindTotem(el, preset.selections[el]) then n = n + 1 end
    end
    return n
end

-- Which preset.order slot (1..4) is the Nth non-empty step?
function addon:SlotForStep(step)
    local preset = self:ActivePreset()
    if not preset then return nil end
    local n = 0
    for i = 1, 4 do
        local el = preset.order[i]
        if self:FindTotem(el, preset.selections[el]) then
            n = n + 1
            if n == step then return i end
        end
    end
    return nil
end

function addon:NextCastSlot()
    return self:SlotForStep(self.currentStep)
end

function addon:ResetStep()
    self.currentStep  = 1
    self.lastCastTime = 0
    if self.UI and self.UI.RefreshMini then self.UI:RefreshMini() end
end

-- Fired from UNIT_SPELLCAST_SUCCEEDED. Advances currentStep if the cast spell
-- matches the totem we were expecting next in the sequence.
function addon:OnSpellCast(spellID)
    if not spellID then return end

    -- Track WF casts for the twist refresh warning. Any WF rank qualifies,
    -- so we compare against the known WF entry rather than a fixed ID.
    -- A WF cast in twist mode ALSO changes the badge halo (full→short
    -- transition happens in the secure preBody on press N+1 and fires WF);
    -- refresh the mini UI here so the halo lights up immediately rather
    -- than waiting for the next preset-slot cast (air totem on press N+2).
    local wf = self:WFEntry()
    if wf and wf.spellID == spellID then
        self.lastWFCastTime = GetTime()
        if self.UI and self.UI.RefreshMini then self.UI:RefreshMini() end
    end

    local preset = self:ActivePreset()
    if not preset then return end
    local expectedSlot = self:NextCastSlot()
    if not expectedSlot then return end
    local el    = preset.order[expectedSlot]
    local entry = self:FindTotem(el, preset.selections[el])
    if not entry or entry.spellID ~= spellID then return end

    self.lastCastTime = GetTime()
    local len = self:SequenceLength()
    if len > 0 then
        self.currentStep = (self.currentStep % len) + 1
    end
    if self.UI and self.UI.RefreshMini then self.UI:RefreshMini() end

    -- Reset to step 1 if no subsequent cast lands within the reset window.
    local timer = preset.resetTimer or addon.DEFAULT_RESET_TIMER
    C_Timer.After(timer + 0.1, function()
        if (GetTime() - self.lastCastTime) >= timer then
            self:ResetStep()
        end
    end)
end

local function createSecureButton()
    -- Must be "shown" with non-trivial dimensions: TBC Classic's secure button
    -- handler rejects protected actions on hidden or 1x1 buttons. Kept
    -- off-screen and mouse-disabled so it's invisible and doesn't swallow
    -- clicks.
    -- Dual template: SecureActionButton for the cast dispatch (type/macrotext),
    -- SecureHandlerBase for the wrap-script snippet support needed by the
    -- twist state machine. On TBC Classic 2.5.x the action template alone
    -- accepts `SecureHandlerWrapScript` without error but the postBody never
    -- runs — the secure handler snippet machinery comes from the base
    -- template, not the action template.
    local b = CreateFrame("Button", "TotemsCastButton", UIParent,
        "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    b:SetSize(32, 32)
    b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -OFFSCREEN_OFFSET, OFFSCREEN_OFFSET)
    b:EnableMouse(false)
    -- "AnyDown" alone: single fire per keypress AND secure dispatch works.
    -- "AnyUp" alone silently drops the protected action (OnClick fires but no
    -- cast) on TBC Classic 2.5.5 — the engine evaluates the secure click on
    -- the "down" event. Adding up would double-advance `/castsequence`.
    b:RegisterForClicks("AnyDown")

    -- Twist state machine (secure). Logic lives in preBody because postBody
    -- is silently dropped on SecureActionButton clicks on TBC Classic 2.5.5
    -- (empirically verified — heartbeat never incremented from postBody even
    -- with SecureHandlerBaseTemplate). preBody runs BEFORE the cast dispatch
    -- so a macrotext swap affects the CURRENT click: the transition
    -- threshold is therefore `count > fullLen` (not `>=`), so the swap
    -- happens on the press AFTER the last full-phase cast — press N+1 uses
    -- the short macrotext starting at its position 1 (WF).
    SecureHandlerWrapScript(b, "OnClick", b, [[
        local mode = self:GetAttribute("twist-mode")
        if mode ~= "full" then return end
        local count = (self:GetAttribute("twist-count") or 0) + 1
        local fullLen = self:GetAttribute("twist-full-len") or 5
        if count > fullLen then
            self:SetAttribute("macrotext",   self:GetAttribute("macrotext-short"))
            self:SetAttribute("twist-mode",  "short")
            self:SetAttribute("twist-count", 0)
        else
            self:SetAttribute("twist-count", count)
        end
    ]], "")

    addon.castBtn = b  -- exposed so the UI can build a secure reset button
    return b
end

-- Invisible secure button that receives the `TOTEMS_RESET_TWIST` keybind.
-- Its `_onclick` runs the shared `RESET_TWIST_SNIPPET`, which mutates the
-- cast button's twist attributes. Safe in combat because the click is
-- initiated by a user hardware event and the snippet runs secure.
local function createResetButton()
    local r = CreateFrame("Button", "TotemsResetTwistButton", UIParent, "SecureHandlerClickTemplate")
    r:SetSize(32, 32)
    r:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -OFFSCREEN_OFFSET, OFFSCREEN_OFFSET)
    r:EnableMouse(false)
    r:RegisterForClicks("AnyDown")
    r:SetFrameRef("castBtn", castBtn)
    r:SetAttribute("_onclick", addon.RESET_TWIST_SNIPPET)
    -- Non-secure cleanup after the secure snippet runs: clears the WF
    -- refresh timer and refreshes the mini so the badge halo / WF warning
    -- update immediately instead of waiting for the next matching cast.
    r:HookScript("OnClick", function() addon:OnTwistReset() end)
    return r
end

-- Reroute the user's bindings (TOTEMS_CAST → cast button,
-- TOTEMS_RESET_TWIST → reset button). Calling :Click() from a Lua binding
-- handler gets tainted and the protected action is blocked;
-- SetOverrideBindingClick keeps the hardware-event trust all the way through.
function addon:ApplyKeybind()
    if not castBtn or not resetBtn then return end
    if InCombatLockdown() then
        self.pendingBind = true
        return
    end
    ClearOverrideBindings(castBtn)
    ClearOverrideBindings(resetBtn)
    local ck1, ck2 = GetBindingKey("TOTEMS_CAST")
    if ck1 then SetOverrideBindingClick(castBtn, true, ck1, "TotemsCastButton", "LeftButton") end
    if ck2 then SetOverrideBindingClick(castBtn, true, ck2, "TotemsCastButton", "LeftButton") end
    local rk1, rk2 = GetBindingKey("TOTEMS_RESET_TWIST")
    if rk1 then SetOverrideBindingClick(resetBtn, true, rk1, "TotemsResetTwistButton", "LeftButton") end
    if rk2 then SetOverrideBindingClick(resetBtn, true, rk2, "TotemsResetTwistButton", "LeftButton") end
    self.pendingBind = false
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

-- SPELLS_CHANGED fires in bursts (login, level-up, talent swap, rank learn).
-- Coalesce a rapid series into a single scan to avoid rebuilding the whole
-- `known` table 5–10 times back-to-back.
local scanScheduled = false
local function scheduleScan()
    if scanScheduled then return end
    scanScheduled = true
    C_Timer.After(SPELLS_CHANGED_DEBOUNCE, function()
        scanScheduled = false
        addon:ScanKnownTotems()
        addon:ApplyMacrotext()
        if addon.UI and addon.UI.Refresh then addon.UI:Refresh() end
    end)
end

-- On respec, the spellbook briefly reads as half-empty while the server
-- applies the new talents. A quick SPELLS_CHANGED scan during that window
-- bakes stale data into `addon.known` (totems like Windfury disappear from
-- the picker). Schedule a second scan ~2s later to catch the settled state.
local respecScanScheduled = false
local function scheduleRespecScan()
    if respecScanScheduled then return end
    respecScanScheduled = true
    C_Timer.After(RESPEC_SCAN_DELAY, function()
        respecScanScheduled = false
        addon:ScanKnownTotems()
        addon:ApplyMacrotext()
        if addon.UI and addon.UI.Refresh then addon.UI:Refresh() end
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("UPDATE_BINDINGS")
f:RegisterEvent("CHARACTER_POINTS_CHANGED")
f:RegisterEvent("PLAYER_TALENT_UPDATE")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:SetScript("OnEvent", function(self, event, arg1, _, arg3)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if class ~= "SHAMAN" then
            -- Shaman is the only class with totems. Disable ourselves for
            -- this character (per-character enable state) so we don't wake
            -- up on alts; do nothing else this session. The API lives in
            -- `C_AddOns` on TBC Classic Anniversary 2.5.5 (the flat global
            -- `DisableAddOn` was removed); fall back to the global for
            -- older clients where `C_AddOns` may not exist.
            local disableFn = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
            if disableFn then disableFn(ADDON) end
            DEFAULT_CHAT_FRAME:AddMessage(addon.L.CHAT_DISABLED_CLASS:format(BRAND))
            self:UnregisterAllEvents()
            return
        end
        addon:InitDB()
        castBtn = createSecureButton()
        resetBtn = createResetButton()
        addon:ScanKnownTotems()
        addon:ApplyMacrotext()
        addon:ApplyKeybind()
        if addon.UI and addon.UI.InitMini then addon.UI:InitMini() end
        if addon.UI and addon.UI.Restyle  then addon.UI:Restyle()  end
        DEFAULT_CHAT_FRAME:AddMessage(addon.L.CHAT_LOADED:format(BRAND))
    elseif event == "SPELLS_CHANGED" then
        scheduleScan()
    elseif event == "UPDATE_BINDINGS" then
        addon:ApplyKeybind()
    elseif event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        -- Rescan spellbook after the respec transient settles, then restyle
        -- with the new spec's accent color.
        scheduleRespecScan()
        if addon.UI and addon.UI.Restyle then addon.UI:Restyle() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- arg1 = unit, arg3 = spellID (arg2 = castGUID, ignored).
        if arg1 == "player" then
            if addon.TOTEM_RECALL_IDS[arg3] then
                -- Out-of-combat auto-reset. In combat the user clicks the
                -- secure Reset button in the mini chrome.
                addon:ResetTwist()
            end
            addon:OnSpellCast(arg3)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if addon.UI and addon.UI.OnCombatStart then addon.UI:OnCombatStart() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if addon.pending then addon:ApplyMacrotext() end
        if addon.pendingBind then addon:ApplyKeybind() end
    end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function debugUnmapped()
    local mapped = {}
    for _, element in ipairs(addon.ELEMENTS) do
        for _, t in ipairs(addon.TOTEM_DB[element]) do
            for _, id in ipairs(t.ranks) do mapped[id] = true end
        end
    end

    print(addon.L.CHAT_DEBUG_SCAN:format(BRAND))
    local found = 0
    local i = 1
    while true do
        local slotName = GetSpellBookItemName(i, BOOKTYPE_SPELL)
        if not slotName then break end
        local kind, spellID = GetSpellBookItemInfo(i, BOOKTYPE_SPELL)
        if kind == "SPELL" and spellID and slotName:lower():find("totem") and not mapped[spellID] then
            print(addon.L.CHAT_DEBUG_UNMAPPED:format(spellID, slotName))
            found = found + 1
        end
        i = i + 1
    end
    print(addon.L.CHAT_DEBUG_DONE:format(BRAND, found))
end

SLASH_TOTEMS1 = "/totems"
SlashCmdList.TOTEMS = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "debug" then
        debugUnmapped()
    elseif msg == "test" then
        if addon.Tests and addon.Tests.RunAll then addon.Tests:RunAll() end
    else
        if addon.UI and addon.UI.ToggleMini then addon.UI:ToggleMini() end
    end
end

-- Binding labels (shown in the Blizzard Key Bindings UI).
BINDING_HEADER_TOTEMS           = addon.L.BINDING_HEADER
BINDING_NAME_TOTEMS_CAST        = addon.L.BINDING_CAST
BINDING_NAME_TOTEMS_RESET_TWIST = addon.L.BINDING_RESET_TWIST
