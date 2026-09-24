# Wildly Changelog

## Unreleased

### Under the hood
- **Wildly now asks the shared LibGroupBuffs library whether it loaded properly,** instead of
  checking the library's internals itself, and needs version r12 of it (included in the download).
  Nothing should look different to you. If Wildly ever says in chat that it *cannot start*,
  reinstalling Wildly still fixes it.

## v1.0.0 - 2026-09-24

**Wildly now runs on World of Warcraft: Forever.** This is the first release for the Forever client
(1.60.1). Playing TBC Classic Anniversary? Stay on **v0.1.1**, the last release for that client; it
remains available on CurseForge.

### Known issues
- **Your settings reset every time you reload.** This is a client bug that affects every addon:
  Forever saves addon settings and never reads them back. It has been reported to Blizzard, and
  Wildly says so in chat once a game update fixes it.
- **Not yet played on a druid by its author.** Everything is covered by automated tests, and the
  same engine and window run Priestly in game today, but this build has not been through a
  hands-on pass. If something looks wrong, please report it, and type `/console scriptErrors 1` to
  see errors the client otherwise hides.

### Changed
- **Built on the same engine and window as Priestly** (the LibGroupBuffs library), so fixes found in
  either addon reach both. The window looks and works like Priestly's, in Wildly's orange.
- **Left-click works before you know Gift of the Wild.** It buffs whoever needs Mark of the Wild,
  and switches to Gift on its own once you learn it. Nothing is ever wired to a spell you do not
  have.
- **Thorns follows its setting properly in raids.** "Yourself only" now finds you in a raid, and the
  main tank is found even when two raiders share a first name (Forever characters have surnames).
- **The default Thorns mode puts Thorns on you when your group has no tank.** Forever has no dungeon
  finder, so tank roles may never be set in a party; before, that left no Thorns row at all. "Tanks
  only" still covers tanks and nobody else.
- **Pets never get Thorns,** in any mode. They still get Mark of the Wild.
- **Reagents:** the footer shows Wild Berries or Wild Thornroot for the Gift of the Wild rank you
  know. Wild Quillvine is gone: it belongs to a rank above Forever's level cap.

### Added
- **During a fight, hovering a row lists who still needs the buff,** and says how current that is,
  because the game hides buffs in combat.
- **Buff state that cannot be read shows as `?`** instead of a false "missing".
- **Options:** lock the window's position, turn the click hints off, and choose which side the
  per-member popover opens on.
- **`/wildly pos`** explains where the window is and why.

### Fixed
- **Clicks work whether your client acts on key down or key up.** A setting in some interface
  addons used to make every row do nothing.
- **Closing the window in a fight** now says it closes when combat ends, and does, instead of
  failing silently.
- **Wildly stays out of the way on other classes:** no window, no options page, no chat messages.

## v0.1.0

Initial Wildly release (Druid fork based on Priestly architecture).

### Added

- Druid-only class gate (addon exits for non-Druid characters).
- Mark of the Wild / Gift of the Wild tracker row.
- Thorns tracker row with configurable eligibility modes:
  - Default (tanks in group/raid, self while solo)
  - Tanks only
  - Self only
  - Everyone
  - Disabled
- Group/single secure click-cast behavior adapted for Druid buffs.
- Popover target list behavior adapted for Druid buff maintenance.
- Gift reagent rank detection and footer reagent count display:
  - Wild Berries
  - Wild Thornroot
  - Wild Quillvine
- Druid-focused options panel:
  - Track Mark/Gift toggle
  - Thorns mode selector
  - Solo visibility, pet tracking, and frame opacity settings
- Druid accent styling (`#FF7C0A`) for core UI elements.
- Druid spec icon logic for Feral Bear, Feral Cat, Balance, and Restoration.

### Removed

- Priest-specific buff logic and Shadow Protection instance mode configuration.
- Priest-specific reagent handling (candles/feather) and related UI copy.
