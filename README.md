# Wildly Forever

**Wildly** is a lightweight buff manager for druids, inspired by **PallyPower**. It tracks
*Mark of the Wild* (and *Gift of the Wild*) and *Thorns* across your party or raid and lets you
rebuff with a single click.

This is the **World of Warcraft: Forever** edition (client 1.60.1, Interface `16001`).

![Wildly buff window in a group](https://raw.githubusercontent.com/Spotnick2/Wildly/main/docs/screenshots/wildly-screen1.png)

*Example from an earlier build; the current window has additional controls.*

> **Playing TBC Classic Anniversary?** Install **v0.1.1**, the last release for that client. It
> stays available on CurseForge for the Anniversary game version. The Anniversary line is no longer
> being developed.

Wildly shares its engine and window with **Priestly** through the
[LibGroupBuffs](https://github.com/Spotnick2/LibGroupBuffs) library, so a fix to one reaches both.

---

## Features

* **One row per group, per buff**, colour-coded by how many people are missing it, with the lowest
  remaining timer on the bar.
* **One-click buffing.** Left-click casts Gift of the Wild on the group, right-click buffs the first
  person missing it. No targeting.
* **Works before you have Gift of the Wild.** While you only know Mark of the Wild, left-click
  simply buffs whoever needs it. Nothing is wired to a spell you do not have.
* **Thorns where it belongs.** Choose who the Thorns row covers: the group's tanks (or you, if it
  has none), tanks only, yourself, everyone, or nobody. Everyone includes pets when
  **Track pets** is enabled; self and tank modes cover players only.
* **Per-member popover.** Mouse over a row for the full list with range indicators and per-person
  click casting.
* **Group-aware.** It follows party and raid changes, subgroups, and pets.
* **Reagent tracking.** The Wild Berries or Wild Thornroot count, for the Gift of the Wild rank you
  know.
* **Window controls.** Minimize without closing, lock its position, adjust opacity and choose
  which side the member popover opens on.

---

## Usage

Use the header **-** to minimize to the title bar and **+** to restore. Requests in
combat wait until combat ends. Minimized state lasts for this session; `/reload`
or logging in expands the window again. **X** closes the window.

In the popover, **? beside the class icon** means spell range is unknown.
**? instead of a timer** means the buff cannot be read and there is no cached reading.

```
/wildly          toggle the window
/wildly show     force open
/wildly hide     close
/wildly config   open the options panel
/wildly reset    reset the window position
/wildly pos      why the window is where it is
/wildly help     full command and click reference
```

The window opens on its own when you join a group. Wildly does nothing on other classes.
Settings and window position persist between sessions.

**Row colours:** green = everyone has it · yellow = some missing · red = nobody has it ·
grey `?` = buff state cannot be read right now (the client hides aura data during combat, so
Wildly keeps counting down from the last reading instead of guessing).

---

## Installation

### CurseForge (recommended)

Install through the CurseForge app and enable it in game.

### GitHub and Wago

Download from [GitHub Releases](https://github.com/Spotnick2/Wildly/releases/latest)
or [Wago Addons](https://addons.wago.io/addons/wildly). Both include the required libraries.
The GitHub release includes `release.json` for compatible addon managers.

### Manual

Download the release zip and extract it so the folder lands at:

```
World of Warcraft/_classic_beta_/Interface/AddOns/Wildly/
```

---

## Good to know

**Pet eligibility:** hunter and warlock pets are excluded from Mark of the Wild
tracking and targeting. Thorns includes tracked pets in Everyone mode.

Wildly uses single-target Mark of the Wild until you learn Gift of the Wild. It learns buff
durations from live auras and relearns them when the client build changes. In the default Thorns
mode, if no group member has a tank role or raid main-tank assignment, Wildly tracks Thorns on you.

Forever can hide aura data during combat. Wildly uses its last observation and shows `?` if no
reliable reading is available. Window movement, closing and minimize/restore requests made during
combat take effect after combat ends.

---

## Feedback

Open an [issue on GitHub](https://github.com/Spotnick2/Wildly/issues) or leave a comment on
CurseForge. Include the addon version,
client build, locale, and whether the problem happened in combat. Typing
`/console scriptErrors 1` in game shows Lua errors that the client otherwise hides.

## Author

**Spotnick**

## License

MIT - see [LICENSE](LICENSE).
