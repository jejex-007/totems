local ADDON, addon = ...

-- Localization layer. Must load BEFORE Core.lua and UI.lua so `addon.L`
-- is populated by the time those files reference it.
--
-- The active locale is picked from `GetLocale()` at load time and mapped to
-- one of our supported tables (en / fr / de). Unknown locales fall back to
-- English. Missing keys in a non-English table also fall back to English
-- via the metatable. A missing key in English itself is surfaced as
-- `[KEY_NAME]` so it's easy to spot in-game.

addon.LOCALES = {}

-------------------------------------------------------------------------------
-- English (default + fallback)
-------------------------------------------------------------------------------
addon.LOCALES.en = {
    ELEMENT_AIR         = "Air",
    ELEMENT_FIRE        = "Fire",
    ELEMENT_EARTH       = "Earth",
    ELEMENT_WATER       = "Water",

    LABEL_RESET_SEC     = "Reset (s)",
    LABEL_PRESET        = "Preset",
    LABEL_HIDDEN_BUTTON = "Hidden",
    LABEL_TWIST_CHECK   = "Totem twisting (WF)",

    TT_LOCK             = "Lock position",
    TT_UNLOCK           = "Unlock position",
    TT_CONFIGURE        = "Open config",
    TT_SHARE            = "Share sequence in chat",
    TT_SHARE_HINT       = "(prefixed with /raid or /p in a group)",
    TT_TWIST_RESET      = "Reset twist",
    TT_TWIST_RESET_HINT = "Restarts: WF + full sequence.",
    TT_TWIST_INFO       = "On cast key: WF + full sequence.\n"
                       .. "Then alternates WF / air totem until reset.",
    TT_TWIST_BADGE      = "Twist active",
    TT_TWIST_BADGE_HINT = "Windfury is cast between each totem.",
    TT_SLOT_CLICK       = "Click: change totem",
    TT_SLOT_SHIFT       = "Shift-click: share in chat",
    TT_SLOT_DRAG        = "Drag: reorder the sequence",
    TT_SLOT_RIGHTCLICK  = "Right-click: open config",
    TT_HIDE_SHIFTCLICK  = "Shift-click: hide",

    MENU_NONE           = "(none)",
    MENU_NO_HIDDEN      = "(no hidden totems)",
    MENU_NEW_PRESET     = "New…",
    MENU_RENAME_PRESET  = "Rename %s…",
    MENU_DELETE_PRESET  = "Delete %s",

    POPUP_NEW_TITLE     = "Name for the new preset?",
    POPUP_RENAME_TITLE  = "New name for preset '%s'?",
    POPUP_DELETE_TITLE  = "Delete preset '%s'?",
    POPUP_DELETE_OK     = "Delete",
    POPUP_CANCEL        = "Cancel",
    POPUP_OK            = "OK",

    CHAT_LOADED         = "%s loaded. /totems to configure. "
                       .. "Bind a key under Key Bindings > AddOns > Totems.",
    CHAT_DISABLED_CLASS = "%s is only usable by shamans and has been "
                       .. "disabled on this character. You can uninstall "
                       .. "the addon for any non-shaman class.",
    CHAT_NO_COMBAT      = "%s: config not available in combat.",
    CHAT_DEBUG_SCAN     = "%s: scanning spellbook for unmapped totems...",
    CHAT_DEBUG_UNMAPPED = "  unmapped: id=%d  name=%s",
    CHAT_DEBUG_DONE     = "%s: done (%d unmapped).",

    BINDING_HEADER      = "Totems",
    BINDING_CAST        = "Cast next totem in sequence",
    BINDING_RESET_TWIST = "Reset twist sequence",
}

-------------------------------------------------------------------------------
-- French
-------------------------------------------------------------------------------
addon.LOCALES.fr = {
    ELEMENT_AIR         = "Air",
    ELEMENT_FIRE        = "Feu",
    ELEMENT_EARTH       = "Terre",
    ELEMENT_WATER       = "Eau",

    LABEL_RESET_SEC     = "Reset (s)",
    LABEL_PRESET        = "Preset",
    LABEL_HIDDEN_BUTTON = "Masqués",
    LABEL_TWIST_CHECK   = "Totem twisting (WF)",

    TT_LOCK             = "Verrouiller la position",
    TT_UNLOCK           = "Déverrouiller la position",
    TT_CONFIGURE        = "Configurer la séquence",
    TT_SHARE            = "Partager la séquence dans le chat",
    TT_SHARE_HINT       = "(préfixe /raid ou /p si en groupe)",
    TT_TWIST_RESET      = "Reset twist",
    TT_TWIST_RESET_HINT = "Redémarre : WF + séquence complète.",
    TT_TWIST_INFO       = "À la touche cast : WF + séquence complète.\n"
                       .. "Puis alterne WF / totem d'air jusqu'au reset.",
    TT_TWIST_BADGE      = "Twist actif",
    TT_TWIST_BADGE_HINT = "Windfury est castée entre chaque totem.",
    TT_SLOT_CLICK       = "Clic : changer le totem",
    TT_SLOT_SHIFT       = "Shift-clic : partager dans le chat",
    TT_SLOT_DRAG        = "Glisser : réordonner la séquence",
    TT_SLOT_RIGHTCLICK  = "Clic droit : ouvrir la config",
    TT_HIDE_SHIFTCLICK  = "Shift-clic : masquer",

    MENU_NONE           = "(aucun)",
    MENU_NO_HIDDEN      = "(aucun totem masqué)",
    MENU_NEW_PRESET     = "Nouveau…",
    MENU_RENAME_PRESET  = "Renommer %s…",
    MENU_DELETE_PRESET  = "Supprimer %s",

    POPUP_NEW_TITLE     = "Nom du nouveau preset ?",
    POPUP_RENAME_TITLE  = "Nouveau nom pour le preset '%s' ?",
    POPUP_DELETE_TITLE  = "Supprimer le preset '%s' ?",
    POPUP_DELETE_OK     = "Supprimer",
    POPUP_CANCEL        = "Annuler",
    POPUP_OK            = "OK",

    CHAT_LOADED         = "%s chargé. /totems pour configurer. "
                       .. "Assignez une touche dans Options > Raccourcis > AddOns > Totems.",
    CHAT_DISABLED_CLASS = "%s est utilisable uniquement par les chamans et "
                       .. "a été désactivé sur ce personnage. Vous pouvez "
                       .. "désinstaller l'addon pour toutes les classes "
                       .. "autres que chaman.",
    CHAT_NO_COMBAT      = "%s : la configuration n'est pas disponible en combat.",
    CHAT_DEBUG_SCAN     = "%s : scan du grimoire pour totems non mappés...",
    CHAT_DEBUG_UNMAPPED = "  non mappé : id=%d  nom=%s",
    CHAT_DEBUG_DONE     = "%s : terminé (%d non mappés).",

    BINDING_HEADER      = "Totems",
    BINDING_CAST        = "Lancer le prochain totem de la séquence",
    BINDING_RESET_TWIST = "Réinitialiser la séquence twist",
}

-------------------------------------------------------------------------------
-- German
-------------------------------------------------------------------------------
addon.LOCALES.de = {
    ELEMENT_AIR         = "Luft",
    ELEMENT_FIRE        = "Feuer",
    ELEMENT_EARTH       = "Erde",
    ELEMENT_WATER       = "Wasser",

    LABEL_RESET_SEC     = "Reset (s)",
    LABEL_PRESET        = "Preset",
    LABEL_HIDDEN_BUTTON = "Versteckt",
    LABEL_TWIST_CHECK   = "Totem-Twisting (WF)",

    TT_LOCK             = "Position sperren",
    TT_UNLOCK           = "Position entsperren",
    TT_CONFIGURE        = "Konfiguration öffnen",
    TT_SHARE            = "Sequenz im Chat teilen",
    TT_SHARE_HINT       = "(Präfix /raid oder /p in der Gruppe)",
    TT_TWIST_RESET      = "Twist zurücksetzen",
    TT_TWIST_RESET_HINT = "Startet neu: WF + volle Sequenz.",
    TT_TWIST_INFO       = "Cast-Taste: WF + volle Sequenz.\n"
                       .. "Dann wechselt WF / Luft-Totem bis zum Reset.",
    TT_TWIST_BADGE      = "Twist aktiv",
    TT_TWIST_BADGE_HINT = "Windzorn wird zwischen jedem Totem gewirkt.",
    TT_SLOT_CLICK       = "Klick: Totem ändern",
    TT_SLOT_SHIFT       = "Shift-Klick: im Chat teilen",
    TT_SLOT_DRAG        = "Ziehen: Sequenz neu ordnen",
    TT_SLOT_RIGHTCLICK  = "Rechtsklick: Konfiguration öffnen",
    TT_HIDE_SHIFTCLICK  = "Shift-Klick: verstecken",

    MENU_NONE           = "(kein)",
    MENU_NO_HIDDEN      = "(keine versteckten Totems)",
    MENU_NEW_PRESET     = "Neu…",
    MENU_RENAME_PRESET  = "%s umbenennen…",
    MENU_DELETE_PRESET  = "%s löschen",

    POPUP_NEW_TITLE     = "Name für das neue Preset?",
    POPUP_RENAME_TITLE  = "Neuer Name für Preset '%s'?",
    POPUP_DELETE_TITLE  = "Preset '%s' löschen?",
    POPUP_DELETE_OK     = "Löschen",
    POPUP_CANCEL        = "Abbrechen",
    POPUP_OK            = "OK",

    CHAT_LOADED         = "%s geladen. /totems zum Konfigurieren. "
                       .. "Taste zuweisen unter Tastenbelegung > Addons > Totems.",
    CHAT_DISABLED_CLASS = "%s ist nur für Schamanen nutzbar und wurde auf "
                       .. "diesem Charakter deaktiviert. Sie können das "
                       .. "Addon für Nicht-Schamanen-Klassen deinstallieren.",
    CHAT_NO_COMBAT      = "%s: Konfiguration im Kampf nicht verfügbar.",
    CHAT_DEBUG_SCAN     = "%s: durchsuche Zauberbuch nach nicht zugeordneten Totems...",
    CHAT_DEBUG_UNMAPPED = "  nicht zugeordnet: id=%d  name=%s",
    CHAT_DEBUG_DONE     = "%s: fertig (%d nicht zugeordnet).",

    BINDING_HEADER      = "Totems",
    BINDING_CAST        = "Nächstes Totem der Sequenz setzen",
    BINDING_RESET_TWIST = "Twist-Sequenz zurücksetzen",
}

-------------------------------------------------------------------------------
-- Locale resolution
-------------------------------------------------------------------------------

-- Map Blizzard locale codes to our short tags. Anything not listed falls
-- back to English.
local LOCALE_MAP = {
    frFR = "fr",
    deDE = "de",
    enUS = "en",
    enGB = "en",
}

function addon:PickLocale(localeCode)
    -- Exposed as a function so tests can pass explicit codes.
    localeCode = localeCode or (GetLocale and GetLocale()) or "enUS"
    local tag = LOCALE_MAP[localeCode] or "en"
    return self.LOCALES[tag], tag
end

local picked, pickedTag = addon:PickLocale()
addon.LOCALE_TAG = pickedTag

-- Non-English tables fall back to English for missing keys. English itself
-- falls back to a "[KEY]" marker so a missing entry is visible in-game.
if picked ~= addon.LOCALES.en then
    setmetatable(picked, { __index = addon.LOCALES.en })
end
addon.L = setmetatable({}, {
    __index = function(_, k)
        local v = picked[k]
        if v ~= nil then return v end
        return "[" .. tostring(k) .. "]"
    end,
})
