# Wildly Forever

**Wildly** is a lightweight buff manager for druids, inspired by **PallyPower**. It tracks
*Mark of the Wild* (and *Gift of the Wild*) and *Thorns* across your party or raid and lets you
rebuff with a single click.

This is the **World of Warcraft: Forever** edition (client 1.60.1, Interface `16001`).

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
  has none), tanks only, yourself, every player, or nobody. Pets never get Thorns.
* **Per-member popover.** Mouse over a row for the full list with range indicators and per-person
  click casting.
* **Group-aware.** It follows party and raid changes, subgroups, and pets.
* **Reagent tracking.** The Wild Berries or Wild Thornroot count, for the Gift of the Wild rank you
  know.

---

## Usage

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

**Row colours:** green = everyone has it · yellow = some missing · red = nobody has it ·
grey `?` = buff state cannot be read right now (the client hides aura data during combat, so
Wildly keeps counting down from the last reading instead of guessing).

---

## Installation

### CurseForge (recommended)

Install through the CurseForge app and enable it in game.

### Manual

Download the release zip and extract it so the folder lands at:

```
World of Warcraft/_classic_beta_/Interface/AddOns/Wildly/
```

---

## Beta notes

Forever is in beta and the level cap is still low, so some of Wildly is waiting for content to
catch up:

* **Gift of the Wild is not learnable yet.** Every row works single-target until it is, and switches
  over automatically once you learn it. Its reagent appears in the footer at the same time.
* **Thorns and tanks.** Wildly counts someone as a tank if they have set the tank role, or are the
  raid's main tank. Forever has no dungeon finder, so roles may never be set in a party. That is
  why the default mode puts Thorns on you when the group has no tank.
* **Buff durations differ from both TBC and Vanilla** and are still being tuned. Wildly learns the
  real duration from your own buffs rather than assuming one, and forgets what it learned whenever
  the client build changes.
* **Your settings reset every time you reload.** This is a client bug and it affects every addon:
  Forever writes addon settings to disk correctly and then never reads them back at login. So the
  window position, the lock and every option start fresh each session. No addon can work around
  it. It waits on Blizzard's fix, which has been reported, and Wildly says so in chat once a game
  update fixes it.

---

## Feedback

Open an issue on GitHub or leave a comment on CurseForge. This first Forever release has not been
played by its author on a druid yet, so reports of anything odd are especially welcome. Typing
`/console scriptErrors 1` in game shows Lua errors that the client otherwise hides.

## Author

**Spotnick**

## License

MIT - see [LICENSE](LICENSE).
