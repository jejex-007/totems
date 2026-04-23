# Totems — user guide

## What it does

Totems replaces a fixed
`/castsequence reset=10 T1,T2,T3,T4` macro with a small in-game
config window. You pick one totem per element
(Air / Fire / Earth / Water) from the totems your shaman has
actually learned, reorder the 4 columns however you want, save
named presets, and bind a single key to cast the next totem in
the sequence.

## Install

1. Copy the `Totems/` folder into
   `World of Warcraft/_anniversary_/Interface/AddOns/`
   (the TBC Anniversary client uses the `_anniversary_`
   subfolder).
2. Start (or reload) the game.
3. Type `/totems` to open the config.
4. Open *Key Bindings → AddOns → Totems* and assign a key to
   "Cast next totem in sequence".

## Using the config

- **Columns** — one per element. Each column shows only the
  totems of that element that your shaman has actually learned.
- **Click a totem** to select it (click again to unselect). At
  most one selected totem per element; it's the one that goes
  into the cast sequence.
- **`<` / `>` above a column** — move that column (and therefore
  its position in the cast sequence) one slot left or right. The
  sequence runs left → right.
- **Reset (s)** — how many seconds of no-press reset the
  sequence back to the first totem. Default 10. Stored per
  preset.
- **Preset dropdown** — switch between named 4-totem presets.
  - `New` clones the current preset under a new name you type.
  - `Delete` removes the active preset (you can't delete
    `Default`).

## Cast in-game

Each press of your bound key casts the next totem in the active
preset's sequence. After the 4th totem, the next press starts
again from the first. If you don't press for *reset* seconds,
the counter resets early.

## Troubleshooting

- **A totem I know isn't in the list** — run `/totems debug` in
  chat; if it prints the missing totem's spell ID, report that
  ID back so it can be added to the database.
- **Can't bind a key** — check *Key Bindings → AddOns → Totems*
  is present. If not, `/reload` the UI.
- **Macrotext not updating** — updates are deferred during
  combat. Leave combat and try again.
- **Nothing happens when I press the key** — make sure every
  element column has a selected totem, or the sequence will be
  empty.
