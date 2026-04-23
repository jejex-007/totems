local ADDON, addon = ...
addon.UI = {}
local UI = addon.UI

-------------------------------------------------------------------------------
-- Layout constants
-------------------------------------------------------------------------------

local COLUMN_W    = 60
local COLUMN_PAD  = 8
local ICON_SIZE   = 44
local ROW_H       = ICON_SIZE + 4
local MAX_ROWS    = 7
local HEADER_H    = 22
local FOOTER_H    = 84  -- bottom area: twist checkbox + preset dropdown + reset timer

-- Throttle for mini/main `OnUpdate` handlers — chrome hover transitions,
-- WF icon show/hide decision, totem timer refresh. 0.1 s is imperceptible
-- to the eye and keeps the hot path cheap.
local UPDATE_THROTTLE = 0.1

-- Windfury refresh pulse (floating WF icon). `HZ` drives `math.sin(t*HZ)`
-- so at 5 Hz the alpha completes ~5 min/max cycles per second.
-- Alpha = BASE + AMPLITUDE * |sin| → ranges [BASE, BASE+AMPLITUDE] = [0.5, 1.0].
local WF_PULSE_HZ        = 5
local WF_PULSE_BASE      = 0.5
local WF_PULSE_AMPLITUDE = 0.5

-- Alpha values used on mini-panel slots.
local EMPTY_SLOT_ALPHA = 0.35    -- faded element-default icon when no totem selected
local SLOT_DRAG_ALPHA  = 0.4     -- active slot while the user is dragging to reorder

local mainFrame
local columnFrames  = {}  -- slot index 1..4 -> column frame
local presetDropdown
local resetBox

local miniFrame
local miniSlots = {}
local miniDropdown

-------------------------------------------------------------------------------
-- Main frame
-------------------------------------------------------------------------------

-- Shared per-frame persisted position helpers. Call sites:
--   * main config  → savePos(f, "pos")         / applyPos(f, "pos",       "CENTER", 0, 0)
--   * mini panel   → savePos(f, "miniPos")     / applyPos(f, "miniPos",   "CENTER", 0, -200)
--   * WF icon      → savePos(f, "wfIconPos")   / applyPos(f, "wfIconPos", "CENTER", 0,  100)
-- All positions live under `TotemsDB.ui.<dbKey>` as { point, relPoint, x, y }.
local function savePos(f, dbKey)
    local point, _, relPoint, x, y = f:GetPoint(1)
    if not point then return end
    TotemsDB.ui[dbKey] = { point = point, relPoint = relPoint, x = x, y = y }
end

local function applyPos(f, dbKey, defPoint, defX, defY)
    local pos = TotemsDB.ui and TotemsDB.ui[dbKey]
    f:ClearAllPoints()
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint(defPoint, UIParent, defPoint, defX or 0, defY or 0)
    end
end

-- Hover-reveal state transition for a frame's chrome (close / lock / gear
-- buttons that start invisible and fade in while the mouse is over the
-- frame or any chrome child). Checking the parent alone flickers when the
-- cursor enters a child that extends past the parent rect (e.g. a close
-- button anchored at +1,+1), so we test parent + every chrome element.
-- Caller is responsible for throttling and storing the per-frame "hovered"
-- state on `frame.chromeHovered`.
local function updateChromeHover(frame, chrome)
    local over = frame:IsMouseOver()
    if not over then
        for _, c in ipairs(chrome) do
            if c:IsMouseOver() then over = true; break end
        end
    end
    if over ~= frame.chromeHovered then
        frame.chromeHovered = over
        local a = over and 1 or 0
        for _, c in ipairs(chrome) do c:SetAlpha(a) end
    end
end

-- Shared style: Blizzard's tiled tooltip background (subtle grain) + a thin
-- black 1px edge. Matches the look Details uses. Frames that call this must
-- inherit from `BackdropTemplate`.
local PANEL_BG   = "Interface\\Tooltips\\UI-Tooltip-Background"
local PANEL_EDGE = "Interface\\Buttons\\WHITE8x8"

-- Flat dark button matching our minimalist style (no Blizzard tan textures).
local function makeFlatButton(parent, w, h, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.5)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.25, 0.25, 0.30, 0.55)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetAllPoints()
    b.label:SetJustifyH("CENTER")
    b.label:SetJustifyV("MIDDLE")
    b.label:SetText(text or "")
    return b
end

-- Click-catcher for dropdown menus. TBC Classic's "MENU" dropdowns don't
-- auto-close on outside clicks — that's retail behavior. We simulate it
-- with an invisible fullscreen frame at strata HIGH: above the main panel
-- (MEDIUM) and its children, below Blizzard's `DropDownList1`
-- (FULLSCREEN_DIALOG). When a Totems dropdown opens the catcher is shown;
-- clicking anywhere on it closes the dropdown, and `DropDownList1`'s own
-- OnHide drops the catcher on any other close path (item select, ESC, or
-- re-click of the owner button).
local dropdownCatcher

local function openDropdown(level, value, menuFrame, anchor, x, y)
    ToggleDropDownMenu(level, value, menuFrame, anchor, x, y)
    if not dropdownCatcher then
        dropdownCatcher = CreateFrame("Frame", nil, UIParent)
        dropdownCatcher:SetAllPoints(UIParent)
        dropdownCatcher:SetFrameStrata("HIGH")
        dropdownCatcher:EnableMouse(true)
        dropdownCatcher:SetScript("OnMouseDown", function(self)
            CloseDropDownMenus()
            self:Hide()
        end)
        DropDownList1:HookScript("OnHide", function()
            if dropdownCatcher then dropdownCatcher:Hide() end
        end)
    end
    if DropDownList1:IsShown() then
        dropdownCatcher:Show()
    else
        dropdownCatcher:Hide()
    end
end

-- Flat dropdown selector: dark button with centered text and a golden
-- expand-arrow on the right. Click the button to trigger `onClick` (which
-- should call `openDropdown` with a menu host).
local function makeFlatDropdown(parent, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.45)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetPoint("LEFT",  b, "LEFT",   8, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -22, 0)
    b.text:SetJustifyH("CENTER")
    b.arrow = b:CreateTexture(nil, "OVERLAY")
    b.arrow:SetSize(14, 14)
    b.arrow:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.18, 0.18, 0.22, 0.55)
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0, 0, 0, 0.45)
    end)
    return b
end

local function stylePanel(f)
    if f.totemsBg then f.totemsBg:Hide(); f.totemsBg = nil end
    if not f.totemsStyled then
        f:SetBackdrop({
            bgFile   = PANEL_BG,
            edgeFile = PANEL_EDGE,
            edgeSize = 1,
            tileSize = 16,
            tile     = true,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        f:SetBackdropColor(0.08, 0.08, 0.10, 0.92)
        f:SetBackdropBorderColor(0, 0, 0, 0.7)
        f.totemsStyled = true
    end
end

local TITLE_H = 22   -- shared title strip height for both panels

local function createMainFrame()
    local width  = 4 * COLUMN_W + 5 * COLUMN_PAD
    local height = TITLE_H + MAX_ROWS * ROW_H + 24 + FOOTER_H
    local f = CreateFrame("Frame", "TotemsConfigFrame", UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not (TotemsDB.ui and TotemsDB.ui.locked) then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePos(self, "pos")
    end)
    f:SetClampedToScreen(true)

    -- Subtle title centered at the top. Color is set per spec in UI:Restyle.
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -4)
    f.title:SetText("Totems")

    applyPos(f, "pos", "CENTER", 0, 0)
    f:Hide()

    -- ESC closes the frame via Blizzard's UIParent close-on-escape list.
    tinsert(UISpecialFrames, "TotemsConfigFrame")

    return f
end

-------------------------------------------------------------------------------
-- Column (one per sequence slot; its element changes when the user reorders)
-------------------------------------------------------------------------------

local function createColumn(parent, slotIndex)
    local col = CreateFrame("Frame", nil, parent)
    col:SetSize(COLUMN_W, HEADER_H + MAX_ROWS * ROW_H + 4)
    col.slotIndex = slotIndex
    col.totemBtns = {}

    -- Header: label + left/right swap buttons.
    col.header = CreateFrame("Frame", nil, col)
    col.header:SetHeight(HEADER_H)
    col.header:SetPoint("TOPLEFT")
    col.header:SetPoint("TOPRIGHT")

    col.label = col.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    col.label:SetPoint("CENTER", col.header, "CENTER", 0, 0)

    col.leftBtn = makeFlatButton(col.header, 18, 16, "<")
    col.leftBtn:SetPoint("LEFT", col.header, "LEFT", 0, 0)
    col.leftBtn:SetScript("OnClick", function() UI:Swap(col.slotIndex, col.slotIndex - 1) end)

    col.rightBtn = makeFlatButton(col.header, 18, 16, ">")
    col.rightBtn:SetPoint("RIGHT", col.header, "RIGHT", 0, 0)
    col.rightBtn:SetScript("OnClick", function() UI:Swap(col.slotIndex, col.slotIndex + 1) end)

    -- Body: vertical list of learned totems for this element. Selection is
    -- conveyed by the green border on the chosen icon — no dedicated footer.
    col.body = CreateFrame("Frame", nil, col)
    col.body:SetPoint("TOP", col.header, "BOTTOM", 0, -4)
    col.body:SetSize(COLUMN_W, MAX_ROWS * ROW_H)

    return col
end

local function makeTotemBtn(col, index)
    local b = CreateFrame("Button", nil, col.body)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    -- Selection halo: drawn on BACKGROUND so the icon covers the middle; only
    -- a 3px colored frame around the icon remains visible when selected.
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT",     b, "TOPLEFT",     -3, 3)
    b.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
    b.border:SetColorTexture(1, 1, 1, 1)  -- recolored per-render
    b.border:Hide()
    b:SetScript("OnEnter", function(self)
        if not self.spellID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:AddLine(addon.L.TT_HIDE_SHIFTCLICK, 1, 1, 0)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if IsShiftKeyDown() then
            UI:ToggleHidden(col._element, self.totemKey)
        else
            UI:OnTotemClicked(col._element, self.totemKey)
        end
    end)
    col.totemBtns[index] = b
    return b
end

function UI:PopulateColumn(col, element)
    col._element = element
    col.label:SetText(addon.ELEMENT_LABEL[element] or element)

    local known = addon.known[element] or {}
    local hidden = (TotemsDB.ui and TotemsDB.ui.hidden and TotemsDB.ui.hidden[element]) or {}
    local list = {}
    for _, entry in ipairs(known) do
        if not hidden[entry.key] then table.insert(list, entry) end
    end
    local preset = addon:ActivePreset()
    local selectedKey = preset.selections[element]

    for i = 1, MAX_ROWS do
        local entry = list[i]
        local b = col.totemBtns[i] or makeTotemBtn(col, i)
        if entry then
            b:Show()
            b:ClearAllPoints()
            b:SetPoint("TOP", col.body, "TOP", 0, -(i - 1) * ROW_H)
            b.icon:SetTexture(entry.texture)
            b.spellID  = entry.spellID
            b.totemKey = entry.key
            if entry.key == selectedKey then
                local c = addon:SpecColor()
                b.icon:SetVertexColor(1, 1, 1)
                b.border:SetColorTexture(c.r, c.g, c.b, 1)
                b.border:Show()
            else
                b.icon:SetVertexColor(0.55, 0.55, 0.55)
                b.border:Hide()
            end
        else
            b:Hide()
        end
    end
end

-------------------------------------------------------------------------------
-- Interactions
-------------------------------------------------------------------------------

function UI:SetLocked(v)
    TotemsDB.ui.locked = v and true or false
    if UI.updateMainLockIcon then UI.updateMainLockIcon() end
    if UI.updateMiniLockIcon then UI.updateMiniLockIcon() end
end

function UI:OnTotemClicked(element, key)
    local preset = addon:ActivePreset()
    if preset.selections[element] == key then
        preset.selections[element] = nil
    else
        preset.selections[element] = key
    end
    addon:ApplyMacrotext()
    self:Refresh()
end

function UI:ToggleHidden(element, key)
    TotemsDB.ui.hidden = TotemsDB.ui.hidden or {}
    TotemsDB.ui.hidden[element] = TotemsDB.ui.hidden[element] or {}
    local set = TotemsDB.ui.hidden[element]
    if set[key] then
        set[key] = nil
    else
        set[key] = true
        local preset = addon:ActivePreset()
        if preset and preset.selections[element] == key then
            preset.selections[element] = nil
            addon:ApplyMacrotext()
        end
    end
    self:Refresh()
end

function UI:ShowHiddenMenu(anchor)
    -- Toggle: if our menu is already open, close it instead of reopening.
    -- Re-calling UIDropDownMenu_Initialize resets the dropdown state, which
    -- would make ToggleDropDownMenu unconditionally open (never close).
    if DropDownList1 and DropDownList1:IsShown()
        and UIDROPDOWNMENU_OPEN_MENU == UI.hiddenMenuFrame then
        CloseDropDownMenus()
        return
    end

    local menuList = {}
    for _, element in ipairs(addon.ELEMENTS) do
        local set = TotemsDB.ui.hidden and TotemsDB.ui.hidden[element]
        if set then
            for key, _ in pairs(set) do
                local entry = addon:FindTotem(element, key)
                local label = (entry and entry.name) or key
                table.insert(menuList, {
                    text    = addon.ELEMENT_LABEL[element] .. " : " .. label,
                    element = element,
                    key     = key,
                })
            end
        end
    end

    UIDropDownMenu_Initialize(UI.hiddenMenuFrame, function()
        local info
        if #menuList == 0 then
            info = UIDropDownMenu_CreateInfo()
            info.text = addon.L.MENU_NO_HIDDEN
            info.notCheckable = true
            info.disabled = true
            UIDropDownMenu_AddButton(info)
            return
        end
        for _, item in ipairs(menuList) do
            info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.notCheckable = true
            info.func = function()
                TotemsDB.ui.hidden[item.element][item.key] = nil
                UI:Refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")

    openDropdown(1, nil, UI.hiddenMenuFrame, anchor, 0, 0)
end

function UI:Swap(i, j)
    if i < 1 or j < 1 or i > 4 or j > 4 or i == j then return end
    local preset = addon:ActivePreset()
    preset.order[i], preset.order[j] = preset.order[j], preset.order[i]
    addon:ApplyMacrotext()
    self:Refresh()
end

-------------------------------------------------------------------------------
-- Preset dropdown + controls
-------------------------------------------------------------------------------

local function dropdownInit(self)
    local info
    -- Alphabetically-sorted list so the dropdown order is stable and
    -- doesn't depend on Lua's `pairs` iteration order.
    local names = {}
    for name, _ in pairs(TotemsDB.presets) do table.insert(names, name) end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    for _, name in ipairs(names) do
        info = UIDropDownMenu_CreateInfo()
        info.text     = name
        info.checked  = (name == TotemsDB.active)
        info.arg1     = name
        info.func     = function(_, arg1)
            TotemsDB.active = arg1
            addon:ApplyMacrotext()
            UI:Refresh()
        end
        UIDropDownMenu_AddButton(info)
    end

    info = UIDropDownMenu_CreateInfo()
    info.text         = addon.L.MENU_NEW_PRESET
    info.notCheckable = true
    info.func         = function() UI:PromptNewPreset() end
    UIDropDownMenu_AddButton(info)

    if TotemsDB.active ~= "Default" then
        info = UIDropDownMenu_CreateInfo()
        info.text         = addon.L.MENU_RENAME_PRESET:format(TotemsDB.active)
        info.notCheckable = true
        info.func         = function() UI:PromptRenamePreset() end
        UIDropDownMenu_AddButton(info)

        info = UIDropDownMenu_CreateInfo()
        info.text         = addon.L.MENU_DELETE_PRESET:format(TotemsDB.active)
        info.notCheckable = true
        info.colorCode    = "|cffff5555"
        info.func         = function() UI:DeleteActivePreset() end
        UIDropDownMenu_AddButton(info)
    end
end

-- Menu host for the main panel's preset selector (reused by the flat button).
local mainPresetMenu

local function buildPresetDropdown(parent)
    mainPresetMenu = mainPresetMenu
        or CreateFrame("Frame", "TotemsMainPresetMenu", UIParent, "UIDropDownMenuTemplate")
    local dd = makeFlatDropdown(parent, 140, 22, function(self)
        UIDropDownMenu_Initialize(mainPresetMenu, dropdownInit, "MENU")
        openDropdown(1, nil, mainPresetMenu, self, 0, 0)
    end)
    return dd
end

function UI:PromptNewPreset()
    StaticPopupDialogs["TOTEMS_NEW_PRESET"] = StaticPopupDialogs["TOTEMS_NEW_PRESET"] or {
        text         = addon.L.POPUP_NEW_TITLE,
        button1      = addon.L.POPUP_OK,
        button2      = addon.L.POPUP_CANCEL,
        hasEditBox   = true,
        OnAccept     = function(self)
            local eb = self.editBox or (self.GetName and _G[self:GetName() .. "EditBox"])
            local name = eb and eb:GetText() or ""
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" or TotemsDB.presets[name] then return end
            local src = addon:ActivePreset()
            TotemsDB.presets[name] = {
                order      = { src.order[1], src.order[2], src.order[3], src.order[4] },
                selections = {
                    air   = src.selections.air,
                    fire  = src.selections.fire,
                    earth = src.selections.earth,
                    water = src.selections.water,
                },
                resetTimer = src.resetTimer,
                twist      = src.twist or false,
            }
            TotemsDB.active = name
            addon:ApplyMacrotext()
            UI:Refresh()
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            if parent and parent.button1 then parent.button1:Click() end
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TOTEMS_NEW_PRESET")
end

function UI:PromptRenamePreset()
    if TotemsDB.active == "Default" then return end
    local oldName = TotemsDB.active
    StaticPopupDialogs["TOTEMS_RENAME_PRESET"] = StaticPopupDialogs["TOTEMS_RENAME_PRESET"] or {
        text         = addon.L.POPUP_RENAME_TITLE,
        button1      = addon.L.POPUP_OK,
        button2      = addon.L.POPUP_CANCEL,
        hasEditBox   = true,
        OnShow       = function(self, data)
            if self.editBox then self.editBox:SetText(data or "") end
        end,
        OnAccept     = function(self, data)
            local eb = self.editBox or (self.GetName and _G[self:GetName() .. "EditBox"])
            local name = eb and eb:GetText() or ""
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" or name == data or TotemsDB.presets[name] then return end
            TotemsDB.presets[name] = TotemsDB.presets[data]
            TotemsDB.presets[data] = nil
            TotemsDB.active        = name
            addon:ApplyMacrotext()
            UI:Refresh()
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            if parent and parent.button1 then parent.button1:Click() end
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TOTEMS_RENAME_PRESET", oldName, nil, oldName)
end

function UI:DeleteActivePreset()
    if TotemsDB.active == "Default" then return end
    local name = TotemsDB.active
    StaticPopupDialogs["TOTEMS_DELETE_PRESET"] = StaticPopupDialogs["TOTEMS_DELETE_PRESET"] or {
        text         = addon.L.POPUP_DELETE_TITLE,
        button1      = addon.L.POPUP_DELETE_OK,
        button2      = addon.L.POPUP_CANCEL,
        OnAccept     = function(_, data)
            if not data or data == "Default" or not TotemsDB.presets[data] then return end
            TotemsDB.presets[data] = nil
            if TotemsDB.active == data then TotemsDB.active = "Default" end
            addon:ApplyMacrotext()
            UI:Refresh()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TOTEMS_DELETE_PRESET", name, nil, name)
end

-------------------------------------------------------------------------------
-- Init / Refresh / Toggle
-------------------------------------------------------------------------------

function UI:Init()
    if mainFrame then return end
    mainFrame = createMainFrame()

    -- Hover-revealed chrome (same pattern as the mini): close + Masqués in
    -- top-right, lock padlock in bottom-right. Everything starts at alpha 0
    -- and fades in while the mouse is over the panel or any chrome button.
    UI.hiddenMenuFrame = CreateFrame("Frame", "TotemsHiddenMenuFrame", UIParent, "UIDropDownMenuTemplate")
    local chrome = {}
    UI.mainChrome = chrome

    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 1, 1)
    closeBtn:SetAlpha(0)
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)
    table.insert(chrome, closeBtn)

    -- Masqués stays always visible — it is a frequently-used functional
    -- control, not meta/chrome.
    local hiddenBtn = makeFlatButton(mainFrame, 80, 20, addon.L.LABEL_HIDDEN_BUTTON)
    hiddenBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -26, -2)
    hiddenBtn:SetScript("OnClick", function(self) UI:ShowHiddenMenu(self) end)

    local mainLock = CreateFrame("Button", nil, mainFrame)
    mainLock:SetSize(22, 22)
    mainLock:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 4)
    mainLock:SetAlpha(0)
    local function updateMainLockIcon()
        local locked = TotemsDB.ui and TotemsDB.ui.locked
        mainLock:SetNormalTexture(locked
            and "Interface\\Buttons\\LockButton-Locked-Up"
            or  "Interface\\Buttons\\LockButton-Unlocked-Up")
    end
    mainLock:SetScript("OnClick", function()
        UI:SetLocked(not (TotemsDB.ui and TotemsDB.ui.locked))
    end)
    mainLock:SetScript("OnEnter", function(self)
        local locked = TotemsDB.ui and TotemsDB.ui.locked
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(locked and addon.L.TT_UNLOCK or addon.L.TT_LOCK, 1, 1, 1)
        GameTooltip:Show()
    end)
    mainLock:SetScript("OnLeave", function() GameTooltip:Hide() end)
    updateMainLockIcon()
    UI.mainLock           = mainLock
    UI.updateMainLockIcon = updateMainLockIcon
    table.insert(chrome, mainLock)

    mainFrame:SetScript("OnUpdate", function(self, elapsed)
        self.chromeAccum = (self.chromeAccum or 0) + elapsed
        if self.chromeAccum < UPDATE_THROTTLE then return end
        self.chromeAccum = 0
        updateChromeHover(self, chrome)
    end)

    for i = 1, 4 do
        local col = createColumn(mainFrame, i)
        col:SetPoint("TOPLEFT", mainFrame, "TOPLEFT",
            COLUMN_PAD + (i - 1) * (COLUMN_W + COLUMN_PAD),
            -28)
        columnFrames[i] = col
    end

    -- Reset timer input (bottom-left) — flat dark style.
    resetBox = CreateFrame("EditBox", nil, mainFrame)
    resetBox:SetSize(40, 22)
    resetBox:SetPoint("BOTTOMLEFT", 20, 8)
    resetBox:SetAutoFocus(false)
    resetBox:SetNumeric(true)
    resetBox:SetMaxLetters(3)
    resetBox:SetFontObject("GameFontHighlight")
    resetBox:SetJustifyH("CENTER")
    resetBox:SetTextInsets(4, 4, 2, 2)
    resetBox.bg = resetBox:CreateTexture(nil, "BACKGROUND")
    resetBox.bg:SetAllPoints()
    resetBox.bg:SetColorTexture(0, 0, 0, 0.5)
    local function commitReset(self)
        local v = tonumber(self:GetText()) or addon.DEFAULT_RESET_TIMER
        if v < 1 then v = 1 end
        addon:ActivePreset().resetTimer = v
        self:SetText(tostring(v))
        self:ClearFocus()
        addon:ApplyMacrotext()
    end
    resetBox:SetScript("OnEnterPressed", commitReset)
    resetBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); UI:Refresh() end)
    resetBox:SetScript("OnEditFocusLost", commitReset)

    local resetLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetLabel:SetText(addon.L.LABEL_RESET_SEC)
    resetLabel:SetPoint("BOTTOM", resetBox, "TOP", 0, 2)

    -- Preset dropdown (bottom-center).
    presetDropdown = buildPresetDropdown(mainFrame)
    presetDropdown:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 8)

    local presetLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    presetLabel:SetText(addon.L.LABEL_PRESET)
    presetLabel:SetPoint("BOTTOM", presetDropdown, "TOP", 0, 2)

    -- Totem twisting toggle (per-preset). Disabled when the active preset's
    -- air selection is Windfury, when Windfury isn't learned, or when no
    -- air totem is selected at all.
    local twistBox = CreateFrame("CheckButton", nil, mainFrame, "UICheckButtonTemplate")
    twistBox:SetSize(22, 22)
    twistBox:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 14, 48)
    twistBox.label = twistBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    twistBox.label:SetPoint("LEFT", twistBox, "RIGHT", 2, 1)
    twistBox.label:SetText(addon.L.LABEL_TWIST_CHECK)
    twistBox:SetScript("OnClick", function(self)
        local preset = addon:ActivePreset()
        if not preset then return end
        preset.twist = self:GetChecked() and true or false
        addon:ApplyMacrotext()
        UI:Refresh()
    end)
    twistBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(addon.L.LABEL_TWIST_CHECK, 1, 1, 1)
        GameTooltip:AddLine(addon.L.TT_TWIST_INFO, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    twistBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.twistBox = twistBox

    UI:Restyle()
end

function UI:Refresh()
    if mainFrame and mainFrame:IsShown() then
        local preset = addon:ActivePreset()
        for i = 1, 4 do
            self:PopulateColumn(columnFrames[i], preset.order[i])
        end
        if presetDropdown then
            presetDropdown.text:SetText(TotemsDB.active)
        end
        if resetBox then resetBox:SetText(tostring(preset.resetTimer or addon.DEFAULT_RESET_TIMER)) end
        if UI.twistBox then
            -- Disable the checkbox when Windfury is the active air pick or
            -- isn't learned — twisting doesn't apply in those cases.
            local disabled = preset.selections.air == "windfury"
                          or not addon:WFEntry()
                          or not addon:FindTotem("air", preset.selections.air)
            if disabled then
                UI.twistBox:Disable()
                UI.twistBox:SetChecked(false)
                UI.twistBox.label:SetTextColor(0.5, 0.5, 0.5)
            else
                UI.twistBox:Enable()
                UI.twistBox:SetChecked(preset.twist or false)
                UI.twistBox.label:SetTextColor(1, 1, 1)
            end
        end
    end
    self:RefreshMini()
end

function UI:Toggle()
    if InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage(addon.L.CHAT_NO_COMBAT:format(addon.BRAND))
        return
    end
    self:Init()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        self:Refresh()
    end
end

function UI:OnCombatStart()
    if mainFrame and mainFrame:IsShown() then mainFrame:Hide() end
end

function UI:Restyle()
    local color = addon:SpecColor()
    if mainFrame then
        stylePanel(mainFrame)
        if mainFrame.title then
            mainFrame.title:SetTextColor(color.r, color.g, color.b)
        end
    end
    if miniFrame then
        stylePanel(miniFrame)
    end
end

-------------------------------------------------------------------------------
-- Mini panel (always-visible compact view: 4 icons + preset dropdown)
-------------------------------------------------------------------------------

local MINI_ICON    = 36
local MINI_PAD     = 4
local MINI_ROW_W   = 4 * MINI_ICON + 3 * MINI_PAD          -- width of icon row
local MINI_W       = 220                                   -- enough for dropdown
local MINI_H       = MINI_ICON + MINI_PAD * 2 + 30         -- icons + dropdown
local MINI_LEFTPAD = (MINI_W - MINI_ROW_W) / 2             -- center the icons

-- Floating Windfury refresh indicator: shown when twist is applicable AND
-- >= WF_REFRESH_THRESHOLD seconds elapsed since the last WF cast, OR when
-- the main config is open (for positioning). Pulses on warning, solid
-- during positioning. Standalone frame so players can park it anywhere on
-- screen; lives in TotemsDB.ui.wfIconPos and obeys the existing lock.
local WF_ICON_SIZE = 56
local wfIconFrame

function UI:InitMini()
    if miniFrame then return end

    miniFrame = CreateFrame("Frame", "TotemsMiniFrame", UIParent, "BackdropTemplate")
    miniFrame:SetSize(MINI_W, MINI_H)
    miniFrame:SetFrameStrata("MEDIUM")
    miniFrame:SetMovable(true)
    miniFrame:EnableMouse(true)
    miniFrame:RegisterForDrag("LeftButton")
    miniFrame:SetScript("OnDragStart", function(self)
        if not (TotemsDB.ui and TotemsDB.ui.locked) then self:StartMoving() end
    end)
    miniFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePos(self, "miniPos")
    end)
    miniFrame:SetClampedToScreen(true)
    miniFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then UI:Toggle() end
    end)

    -- Shared styled backdrop (applied via UI:Restyle).

    -- Floating WF icon panel: the single Windfury refresh affordance.
    -- Shown when twist is active AND >= WF_REFRESH_THRESHOLD since the last
    -- WF cast, OR when the main config is open (positioning mode). Pulses
    -- on warning, solid on positioning. A mini-anchored red border used to
    -- serve the peripheral-vision role but was redundant with the icon
    -- once players could park it anywhere on screen.
    wfIconFrame = CreateFrame("Frame", "TotemsWFIconFrame", UIParent)
    wfIconFrame:SetSize(WF_ICON_SIZE, WF_ICON_SIZE)
    wfIconFrame:SetFrameStrata("MEDIUM")
    wfIconFrame:SetMovable(true)
    wfIconFrame:EnableMouse(true)
    wfIconFrame:RegisterForDrag("LeftButton")
    wfIconFrame:SetScript("OnDragStart", function(self)
        if not (TotemsDB.ui and TotemsDB.ui.locked) then self:StartMoving() end
    end)
    wfIconFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePos(self, "wfIconPos")
    end)
    wfIconFrame:SetClampedToScreen(true)
    wfIconFrame.icon = wfIconFrame:CreateTexture(nil, "ARTWORK")
    wfIconFrame.icon:SetAllPoints(wfIconFrame)
    wfIconFrame:Hide()
    applyPos(wfIconFrame, "wfIconPos", "CENTER", 0, 100)
    UI.wfIconFrame = wfIconFrame

    -- Hover-revealed chrome: gear (top-left), close (top-right), lock
    -- (bottom-right). Each starts at alpha 0; an OnUpdate checks whether the
    -- mouse is over the mini or any of its children and sets alpha 0/1.
    local chrome = {}
    UI.miniChrome = chrome

    local gearBtn = CreateFrame("Button", nil, miniFrame)
    gearBtn:SetSize(14, 14)
    gearBtn:SetPoint("TOPLEFT", miniFrame, "TOPLEFT", 3, -3)
    gearBtn:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    gearBtn:SetPushedTexture("Interface\\Buttons\\UI-OptionsButton")
    gearBtn:SetAlpha(0)
    gearBtn:SetScript("OnClick", function() UI:Toggle() end)
    gearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(addon.L.TT_CONFIGURE, 1, 1, 1)
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(chrome, gearBtn)

    local closeBtn = CreateFrame("Button", nil, miniFrame, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", miniFrame, "TOPRIGHT", 1, 1)
    closeBtn:SetAlpha(0)
    closeBtn:SetScript("OnClick", function()
        miniFrame:Hide()
        TotemsDB.ui.miniShown = false
    end)
    table.insert(chrome, closeBtn)

    local shareBtn = CreateFrame("Button", nil, miniFrame)
    shareBtn:SetSize(20, 20)
    shareBtn:SetPoint("BOTTOMLEFT", miniFrame, "BOTTOMLEFT", 4, 4)
    shareBtn:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-MOTD-Up")
    shareBtn:SetAlpha(0)
    shareBtn:SetScript("OnClick", function() UI:LinkToChat() end)
    shareBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(addon.L.TT_SHARE, 1, 1, 1)
        GameTooltip:AddLine(addon.L.TT_SHARE_HINT, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    shareBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(chrome, shareBtn)

    -- Secure Reset button (for totem twisting): resets the twist state
    -- machine back to the full-sequence phase. Clickable in combat because
    -- the snippet runs in a secure context initiated by user input.
    local twistResetBtn = CreateFrame("Button", nil, miniFrame, "SecureHandlerClickTemplate")
    twistResetBtn:SetSize(20, 20)
    twistResetBtn:SetPoint("BOTTOMLEFT", miniFrame, "BOTTOMLEFT", 28, 4)
    twistResetBtn:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    twistResetBtn:SetAlpha(0)
    twistResetBtn:RegisterForClicks("AnyDown")
    -- InitMini is called after createSecureButton in the PLAYER_LOGIN flow,
    -- so addon.castBtn is always set here. Letting SetFrameRef error loudly
    -- on a nil (instead of silently skipping) surfaces any future init-order
    -- regression immediately rather than as a silent broken reset button.
    twistResetBtn:SetFrameRef("castBtn", addon.castBtn)
    twistResetBtn:SetAttribute("_onclick", addon.RESET_TWIST_SNIPPET)
    -- Clear the WF warning counter too (insecure post-click hook, runs after
    -- the secure attribute mutation). Keeps the red border in sync with the
    -- freshly-reset twist cycle.
    twistResetBtn:HookScript("OnClick", function() addon.lastWFCastTime = 0 end)
    twistResetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(addon.L.TT_TWIST_RESET, 1, 1, 1)
        GameTooltip:AddLine(addon.L.TT_TWIST_RESET_HINT, 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    twistResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.twistResetBtn = twistResetBtn
    table.insert(chrome, twistResetBtn)

    local lockBtn = CreateFrame("Button", nil, miniFrame)
    lockBtn:SetSize(22, 22)
    lockBtn:SetPoint("BOTTOMRIGHT", miniFrame, "BOTTOMRIGHT", -4, 4)
    lockBtn:SetAlpha(0)
    local function updateLockIcon()
        local locked = TotemsDB.ui and TotemsDB.ui.locked
        lockBtn:SetNormalTexture(locked
            and "Interface\\Buttons\\LockButton-Locked-Up"
            or  "Interface\\Buttons\\LockButton-Unlocked-Up")
    end
    lockBtn:SetScript("OnClick", function()
        UI:SetLocked(not (TotemsDB.ui and TotemsDB.ui.locked))
    end)
    lockBtn:SetScript("OnEnter", function(self)
        local locked = TotemsDB.ui and TotemsDB.ui.locked
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(locked and addon.L.TT_UNLOCK or addon.L.TT_LOCK, 1, 1, 1)
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    updateLockIcon()
    UI.miniLock          = lockBtn
    UI.updateMiniLockIcon = updateLockIcon
    table.insert(chrome, lockBtn)

    -- OnUpdate does two things:
    --  * Every frame: pulse `wfIconFrame` alpha while the refresh warning
    --    is active (smooth sine). The `warningActive` flag is maintained
    --    by the throttled block below so we don't re-run the timer math
    --    every frame.
    --  * Throttled 0.1s: chrome hover + wfIconFrame show/hide decision.
    -- MouseIsOver on parent alone would flicker when the cursor enters a
    -- child that extends beyond the parent rect (like the close button at
    -- +1,+1). We check parent + all chrome buttons.
    miniFrame:SetScript("OnUpdate", function(self, elapsed)
        if self.warningActive and wfIconFrame:IsShown() then
            wfIconFrame:SetAlpha(WF_PULSE_BASE + WF_PULSE_AMPLITUDE * math.abs(math.sin(GetTime() * WF_PULSE_HZ)))
        end

        self.chromeAccum = (self.chromeAccum or 0) + elapsed
        if self.chromeAccum < UPDATE_THROTTLE then return end
        self.chromeAccum = 0

        updateChromeHover(self, chrome)

        -- Totem timers: read the 4 active totem slots from the Blizzard
        -- API (`GetTotemInfo`) and match each active totem back to our
        -- mini slot by ICON (robust vs localized names). When the active
        -- totem matches our preset slot's current selection, show a
        -- countdown; otherwise hide the timer.
        local activeByIcon = nil
        for ti = 1, 4 do
            local haveTotem, _, startTime, duration, icon = GetTotemInfo(ti)
            if haveTotem and duration and duration > 0 and icon then
                activeByIcon = activeByIcon or {}
                activeByIcon[icon] = startTime + duration
            end
        end
        local now = GetTime()
        local activePreset = addon:ActivePreset()
        for i = 1, 4 do
            local element = activePreset and activePreset.order[i]
            local entry   = element and addon:FindTotem(element, activePreset.selections[element])
            local slot    = miniSlots[i]
            local expires = entry and activeByIcon and activeByIcon[entry.texture]
            if expires then
                local remaining = expires - now
                if remaining > 0 then
                    slot.timer:SetText(tostring(math.ceil(remaining)))
                    slot.timer:Show()
                else
                    slot.timer:Hide()
                end
            else
                slot.timer:Hide()
            end
        end

        -- WF icon: visible on warning OR when the main config is open (so
        -- the player can reposition it once the mini is unlocked). Pulses
        -- on warning, solid on positioning.
        local preset      = addon:ActivePreset()
        local canTwist    = preset and addon:TwistApplicable(preset)
        local shouldWarn  = canTwist
            and (addon.lastWFCastTime or 0) > 0
            and (GetTime() - addon.lastWFCastTime) >= addon.WF_REFRESH_THRESHOLD
        local positioning = canTwist and mainFrame and mainFrame:IsShown()
        local wantIcon    = shouldWarn or positioning
        self.warningActive = shouldWarn

        if wantIcon then
            -- Refresh the icon texture lazily so a newly-learned WF rank
            -- (post-respec / ding) propagates without a /reload.
            local wf = addon:WFEntry()
            if wf then wfIconFrame.icon:SetTexture(wf.texture) end
            if not wfIconFrame:IsShown() then wfIconFrame:Show() end
            if not shouldWarn then wfIconFrame:SetAlpha(1.0) end
        elseif wfIconFrame:IsShown() then
            wfIconFrame:Hide()
        end
    end)

    UI.miniSlotMenuFrame = CreateFrame("Frame", "TotemsMiniSlotMenu", UIParent, "UIDropDownMenuTemplate")

    for i = 1, 4 do
        local slot = CreateFrame("Button", nil, miniFrame)
        slot:SetSize(MINI_ICON, MINI_ICON)
        slot:SetPoint("TOPLEFT", miniFrame, "TOPLEFT",
            MINI_LEFTPAD + (i - 1) * (MINI_ICON + MINI_PAD), -MINI_PAD)
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:RegisterForDrag("LeftButton")
        -- "Next to cast" halo: 3px warm-yellow frame on BACKGROUND so the icon
        -- covers the middle. Hidden by default; RefreshMini toggles it.
        slot.nextHL = slot:CreateTexture(nil, "BACKGROUND")
        slot.nextHL:SetPoint("TOPLEFT",     slot, "TOPLEFT",     -3, 3)
        slot.nextHL:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 3, -3)
        slot.nextHL:SetColorTexture(1, 0.85, 0.2, 1)
        slot.nextHL:Hide()
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints()
        -- Remaining-duration text, shown only while the matching totem is
        -- active (`GetTotemInfo` drives it). Arial Narrow 18pt
        -- THICKOUTLINE white — classic cooldown-timer style; readable
        -- over any icon.
        slot.timer = slot:CreateFontString(nil, "OVERLAY")
        slot.timer:SetFont("Fonts\\ARIALN.TTF", 18, "THICKOUTLINE")
        slot.timer:SetPoint("CENTER", slot, "CENTER", 0, 0)
        slot.timer:SetTextColor(1, 1, 1)
        slot.timer:Hide()
        slot.slotIndex = i
        slot:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                UI:Toggle()
            elseif IsShiftKeyDown() then
                UI:LinkTotemToChat(self.slotIndex)
            else
                UI:ShowMiniSlotMenu(self.slotIndex, self)
            end
        end)
        slot:SetScript("OnDragStart", function(self)
            UI.draggingMiniSlot = self.slotIndex
            self:SetAlpha(SLOT_DRAG_ALPHA)
        end)
        slot:SetScript("OnDragStop", function(self)
            self:SetAlpha(1)
            local src = UI.draggingMiniSlot
            UI.draggingMiniSlot = nil
            if not src then return end
            for j = 1, 4 do
                local other = miniSlots[j]
                if other and other ~= self and other:IsMouseOver() then
                    UI:Swap(src, j)
                    return
                end
            end
        end)
        slot:SetScript("OnEnter", function(self)
            local preset = addon:ActivePreset()
            local entry  = addon:FindTotem(preset.order[self.slotIndex],
                                           preset.selections[preset.order[self.slotIndex]])
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if entry then GameTooltip:SetSpellByID(entry.spellID) end
            GameTooltip:AddLine(addon.L.TT_SLOT_CLICK,      1, 1, 0)
            GameTooltip:AddLine(addon.L.TT_SLOT_SHIFT,      1, 1, 0)
            GameTooltip:AddLine(addon.L.TT_SLOT_DRAG,       1, 1, 0)
            GameTooltip:AddLine(addon.L.TT_SLOT_RIGHTCLICK, 1, 1, 0)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        miniSlots[i] = slot
    end

    UI.miniPresetMenu = CreateFrame("Frame", "TotemsMiniPresetMenu", UIParent, "UIDropDownMenuTemplate")
    miniDropdown = makeFlatDropdown(miniFrame, MINI_W - 110, 22, function(self)
        UIDropDownMenu_Initialize(UI.miniPresetMenu, dropdownInit, "MENU")
        openDropdown(1, nil, UI.miniPresetMenu, self, 0, 0)
    end)
    miniDropdown:SetPoint("BOTTOM", miniFrame, "BOTTOM", 0, 6)

    applyPos(miniFrame, "miniPos", "CENTER", 0, -200)
    if TotemsDB.ui and TotemsDB.ui.miniShown == false then
        miniFrame:Hide()
    else
        miniFrame:Show()
    end
    self:Restyle()
    self:RefreshMini()
end

function UI:RefreshMini()
    if not miniFrame then return end
    local preset = addon:ActivePreset()
    local nextSlot = addon:NextCastSlot()
    for i = 1, 4 do
        local element = preset.order[i]
        local entry   = addon:FindTotem(element, preset.selections[element])
        local slot    = miniSlots[i]
        if entry then
            slot.icon:SetTexture(entry.texture)
            slot.icon:SetAlpha(1)
        else
            -- No totem selected (or the one in the preset isn't learned):
            -- show a faded element-default icon so the slot reads as
            -- "empty — element X" rather than a black square.
            slot.icon:SetTexture(addon.ELEMENT_ICON[element])
            slot.icon:SetAlpha(EMPTY_SLOT_ALPHA)
        end
        slot.icon:Show()
        if i == nextSlot then
            slot.nextHL:Show()
        else
            slot.nextHL:Hide()
        end
    end
    if miniDropdown then
        miniDropdown.text:SetText(TotemsDB.active)
    end
    -- The twist reset button is only meaningful when the active preset has
    -- twisting enabled AND it actually applies (air ≠ WF, WF learned).
    if UI.twistResetBtn then
        if addon:TwistApplicable(preset) then
            UI.twistResetBtn:Show()
        else
            UI.twistResetBtn:Hide()
        end
    end
end

function UI:ShowMiniSlotMenu(slotIndex, anchor)
    local preset  = addon:ActivePreset()
    local element = preset.order[slotIndex]
    local known   = addon.known[element] or {}
    local hidden  = (TotemsDB.ui.hidden and TotemsDB.ui.hidden[element]) or {}

    UIDropDownMenu_Initialize(UI.miniSlotMenuFrame, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text         = addon.L.MENU_NONE
        info.checked      = (preset.selections[element] == nil)
        info.notCheckable = false
        info.func         = function()
            preset.selections[element] = nil
            addon:ApplyMacrotext()
            UI:Refresh()
        end
        UIDropDownMenu_AddButton(info)

        for _, entry in ipairs(known) do
            if not hidden[entry.key] then
                info = UIDropDownMenu_CreateInfo()
                info.text    = entry.name
                info.icon    = entry.texture
                info.checked = (preset.selections[element] == entry.key)
                info.func    = function()
                    preset.selections[element] = entry.key
                    addon:ApplyMacrotext()
                    UI:Refresh()
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end, "MENU")

    openDropdown(1, nil, UI.miniSlotMenuFrame, anchor, 0, 0)
end

-- Share the active preset's sequence in chat so other shamans in the group
-- can see what we're running and pick different totems. If a chat edit box
-- is already open, insert into it (respects whatever channel the user picked).
-- Otherwise open a new chat line, auto-prefixed with /raid or /p when in a
-- group so the message goes to the right audience by default.
-- Insert `text` at the cursor if a chat edit box is open, otherwise open a
-- new chat line prefixed for the current group state.
local function insertOrOpenChat(text)
    local edit = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if edit and edit:IsShown() then
        edit:Insert(text)
        return
    end
    local prefix = ""
    if IsInRaid() then
        prefix = "/raid "
    elseif IsInGroup() then
        prefix = "/p "
    end
    ChatFrame_OpenChat(prefix .. text)
end

function UI:LinkTotemToChat(slotIndex)
    local preset = addon:ActivePreset()
    if not preset then return end
    local element = preset.order[slotIndex]
    if not element then return end
    local entry = addon:FindTotem(element, preset.selections[element])
    if not entry then return end
    local link = GetSpellLink(entry.spellID)
    if link then insertOrOpenChat(link) end
end

function UI:LinkToChat()
    local preset = addon:ActivePreset()
    if not preset then return end
    local parts = {}
    for _, element in ipairs(preset.order) do
        local entry = addon:FindTotem(element, preset.selections[element])
        if entry then
            local link = GetSpellLink(entry.spellID)
            if link then table.insert(parts, link) end
        end
    end
    if #parts == 0 then return end
    insertOrOpenChat(table.concat(parts, " "))
end

function UI:ToggleMini()
    if not miniFrame then self:InitMini() end
    if miniFrame:IsShown() then
        miniFrame:Hide()
        TotemsDB.ui.miniShown = false
    else
        miniFrame:Show()
        TotemsDB.ui.miniShown = true
        self:RefreshMini()
    end
end
