# Wildly tests

Unit tests that run under **Lua 5.1** (the interpreter WoW uses) with no game client. Plain
scripts, no external dependencies. Same shape as Priestly's.

## Running

All tests:

```powershell
pwsh tests/run.ps1
```

A single test, from the repo root so the relative paths resolve:

```powershell
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_bridge.lua
```

Use the Lua **5.1** interpreter, not a newer Lua that may be first on `PATH`. `run.ps1` defaults to
`C:\Program Files (x86)\Lua\5.1\lua.exe` (override with `-Lua <path>`) and runs `luac -p` over the
files `Wildly.toc` loads and the library first. That check is required: `run.ps1` fails if it cannot
find `luac.exe` next to `lua.exe` (override with `-Luac <path>`).

**The tests need LibGroupBuffs-1.0 checked out next to this repository** (`../LibGroupBuffs`).
`run.ps1` takes `-Library <path>` instead and prints which checkout and revision it used next to
the tag a release pins. A single test run by hand reads the `LIBGROUPBUFFS` environment variable,
or the sibling checkout. There is no vendored copy to fall back to, on purpose.

## How it works

- **`wow_stubs.lua`** — a minimal WoW: Forever API mock, copied from LibGroupBuffs' own stub (every
  difference marked `Wildly:`):
  frames that record secure attributes and refuse protected calls in combat, a `C_Timer` that
  collects callbacks, `C_UnitAuras` with a secrecy switch, known spells, and units with GUIDs and
  surnames. Drive it through the global `WoW` table. `dofile("tests/wow_stubs.lua")` **first** in
  every test.
- **`harness.lua`** — `check` / `eq`, `readFile`, `tocFiles()`, `loadLibrary()` (the library
  through its own XML) and `loadAddon()` (the library, then Wildly's files in TOC order, skipping
  `H.NOT_YET_PORTED` - the files still on TBC code).
- **`libfiles.lua`** — the one reader of the library's XML, shared by the harness, `run.ps1`,
  `Tools/deploy.ps1` and CI.

## Test files

| File | What it pins down |
|---|---|
| `test_manifest.lua` | The TOC: interface 16001, per-character `WildlyDB` plus the account-wide `WildlySVCheck`, load order, and that the TOC path, `.pkgmeta` externals, pinned tag, `NEEDS_MINOR` and `.gitignore` agree. |
| `test_bridge.lua` | `Wildly.API` / `.Settings` / `.Engine` / `.UI` are the library's own tables; rejected events are printed in chat; a missing library is refused, and so is one whose `lib.Status` answers `incomplete` or `too-old` (or that is too old to have `Status`), each with a message a player sees. Also scans every ported file: each `API.*` it uses exists, no library function is copied into a local, and events go only through `Wildly.RegisterEvents`. |
| `test_availability.lua` | Wildly's DEFS on the engine: which buffs get a row for what the druid knows, what each click casts (Gift when known, Thorns on both buttons), the config toggles layered over availability, localized names. |
| `test_clicks.lua` | The secure attributes after a rebuild: Mark vs Gift, Thorns on both buttons, targets following who is missing it (a Gift counts), clearing rather than casting on a corpse, PreClick re-aiming, popover rows, both mouse edges, no `typerelease`, and hints that say what a click does. |
| `test_frames.lua` | Executes every handler, event and slash command the host installs, and checks what they produce where it matters: login, hover poll, drag and lock, closing in combat (and being told), `/wildly help` describing the live mapping, `reset` while locked, `pos`, and the reagent tooltip. |
| `test_host.lua` | What is Wildly's own: the Gift reagent by rank (Wild Berries, Wild Thornroot, nothing for an unknown rank), its count colours, the spec icon, and the orange colours reaching the drawn window. |
| `test_thorns.lua` | The Thorns member filter, mode by mode: self found as `raidN` in a raid, tanks by role or the raid's main tank matched by roster index (two raiders sharing a first name), pets never, `default` switching between tanks and self; and the row, its target and its popover all following the filtered list, with Mark untouched. |
| `test_visibility.lua` | When the window opens itself: at login in a group or solo mode, never on another class, a deliberate close surviving reloads, roster churn and ready checks, joining a group reopening it, a combat-time show honoured at combat end, the solo checkbox, and the toggle. |
| `test_config.lua` | `WildlyDB` defaults, the five Thorns modes (an unknown one is repaired), buff toggles (`disabled` Thorns drops the row), learned durations per spell name and client build, and the window's settings accessors. |
| `test_config_seam.lua` | The one write path: `Wildly_SetConfig` reports through the hook, the library's `config_scan.lua` finds no direct `WildlyDB` write in any ported file, the owner regions are pinned, and the SavedVariables-fix and new-build checks fire (or stay quiet) on the right logins. |
| `test_options.lua` | Builds the options panel and clicks everything in it, with spies in place of the hooks `Wildly.lua` defines: each checkbox, both radio groups and the slider save through the setter and ask the window to rebuild; the panel builds when no text has been measured, and opens from `Wildly_OpenConfig`. |
| `test_libfiles.lua` | The library's file list, read from its XML, and that `libfiles.lua` does not mistake a test for its own script mode. |
| `test_stub.lua` | The stub entries Wildly added (`strsplit`, `UnitIsUnit`, `GetRaidRosterInfo`, `UnitGroupRolesAssigned`) keep the client's shape. |

## The stub is an allowlist, and it must model absences

`wow_stubs.lua` fails the run on the read of any global it does not define, so it is the list of
APIs verified present on this client. Never add a global because a test failed: confirm it in the
build-matched API dump (`C:/Projects/References/forever-api-<build>.md`) and stub it with the
client's exact signature, or list it as known-absent and make the addon cope.
