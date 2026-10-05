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
files `Wildly.toc` loads and LibGroupBuffs' first. That check is required: `run.ps1` fails if it
cannot find `luac.exe` next to `lua.exe` (override with `-Luac <path>`).

**The tests need both embedded libraries checked out next to this repository**:
`../LibGroupBuffs` and `../LibGlass`. `run.ps1` takes `-Library <path>` and `-LibGlass <path>`
instead (or `LIBGLASS` from the environment), prints which checkout and revision it used, and warns
when one is not at its `.pkgmeta` pin. A single test run by hand reads the `LIBGROUPBUFFS` and
`LIBGLASS` environment variables, or the sibling checkouts. There is no vendored copy to fall back
to, on purpose.

To test exactly what a release ships, whatever branch the sibling checkouts are on, clone both
pins into a fresh folder (it must not exist yet) and point the run there:

```bash
bash tests/fetch_external.sh Libs/LibGroupBuffs-1.0 "$TMP/LibGroupBuffs"   # needs lua5.1, or $LUA
bash tests/fetch_external.sh Libs/LibGlass-1.0 "$TMP/LibGlass"
pwsh tests/run.ps1 -Library "$TMP/LibGroupBuffs" -LibGlass "$TMP/LibGlass"
```

## How it works

- **`wow_stubs.lua`** — Wildly's thin layer over the **shared** stub in
  `../LibGroupBuffs/tests/wow_stubs.lua`. The client surface lives there, one
  copy for Priestly, Wildly and Magely, so every absence and refusal measured
  on this client is measured once. What stays local is this addon's own: its
  default class and the globals it owns. **Add a new global here; look for an
  API's stub in the library.** The shared stub gives you
  frames that record secure attributes and refuse protected calls in combat, a `C_Timer` that
  collects callbacks, `C_UnitAuras` with a secrecy switch, known spells, and units with GUIDs and
  surnames. Drive it through the global `WoW` table. `dofile("tests/wow_stubs.lua")` **first** in
  every test.
- **`harness.lua`** — `check` / `eq`, `readFile`, `tocFiles()`, `libraryRoot()` /
  `libGlassRoot()`, `libraryScripts()`, `loadLibrary()` (LibGlass, then LibGroupBuffs, each through
  its own XML, every file called with `("Wildly", ns)` as the client does) and `loadAddon()` (the
  libraries, then Wildly's files in TOC order, skipping `H.NOT_YET_PORTED` - the files still on TBC
  code).
- **`libfiles.lua`** — the one reader of the libraries' XML, shared by the harness, `run.ps1`,
  `Tools/deploy.ps1` and CI. `L.resolve(root, nil, glassRoot)` also requires every texture
  LibGroupBuffs draws to exist in LibGlass's `Media/`; `L.glass(root)` (`--glass` as a script)
  lists LibGlass's shipped files.
- **`pkgmeta.lua`** — the one reader of `.pkgmeta`'s externals, **by path**, the way the packager
  reads them (an inline comment stays in the value). Used by `test_manifest.lua`, `run.ps1`,
  `deploy.ps1` and CI.
- **`fetch_external.sh <path> <dest>`** — clones one external at its pin, `tag:` or `commit:`,
  and proves the checkout is that commit. CI runs it once per library.
- **`pins.ps1`** — "is this checkout at its pin?", dot-sourced by `run.ps1` and `deploy.ps1`.

## Test files

| File | What it pins down |
|---|---|
| `test_manifest.lua` | The TOC: interface 16001, per-character `WildlyDB` plus the account-wide `WildlySVCheck`, load order (LibGlass, LibGroupBuffs, then Wildly's three files), and that the TOC paths, both `.pkgmeta` externals read by path, their pins (a tag, or a full commit whose MINOR is read with `git show`), `NEEDS_MINOR` (r28 or newer) and `.gitignore` agree; both libraries' ignore lists mirrored here; no shipped Lua file holding a whole packager keyword. |
| `test_bridge.lua` | `Wildly.GB` is the instance `lib:New` made, asked with the floor, and `Wildly.API` its API; no r25-style copies are left. The one reporter: rejected events recorded even with no chat frame, their label red by the line's shape, `settingsLoaded` green, an unknown kind still said, a nil report silent. `New` against the **real** library put into each state - ok, unfinished, LibGlass missing or half-loaded, both at once, a crash, a host mistake, below the floor, a refusal code Wildly does not know, a `Refusal` that throws, and no `Refusal` at all - checking what the player is told, and that `New`'s own text reaches only developers. The real load order: r25's six files and r27's one, loaded first by another addon, are upgraded and accepted without a word. Also scans every ported file: each `API.*` it uses exists, no library function is copied into a local, and events go only through `Wildly.RegisterEvents`. |
| `test_availability.lua` | Wildly's DEFS on the engine: which buffs get a row for what the druid knows, what each click casts (Gift when known, Thorns on both buttons), the config toggles layered over availability, localized names. |
| `test_clicks.lua` | The secure attributes after a rebuild: Mark vs Gift, Thorns on both buttons, targets following who is missing it (a Gift counts), clearing rather than casting on a corpse, PreClick re-aiming, popover rows, both mouse edges, no `typerelease`, and hints that say what a click does. |
| `test_frames.lua` | Executes every handler, event and slash command the host installs, and checks what they produce where it matters: login, hover poll, drag and lock, closing in combat (and being told, in other words for the window's own automatic close), `/wildly help` describing the live mapping, `reset` while locked, `pos`, and the reagent tooltip. |
| `test_host.lua` | What is Wildly's own: the Gift reagent by rank (Wild Berries, Wild Thornroot, nothing for an unknown rank), its count colours, the spec icon, and the orange colours reaching the drawn window. |
| `test_thorns.lua` | The Thorns member filter, mode by mode: self found as `raidN` in a raid, tanks by role or the raid's main tank matched by roster index (two raiders sharing a first name), pets never, `default` switching between tanks and self; and the row, its target and its popover all following the filtered list, with Mark untouched. |
| `test_visibility.lua` | When the window opens itself: at login in a group or solo mode, never on another class, a deliberate close surviving reloads, roster churn and ready checks, joining a group reopening it, a combat-time show honoured at combat end, the solo checkbox, and the toggle. |
| `test_config.lua` | `WildlyDB` defaults, the five Thorns modes (an unknown one is repaired), buff toggles (`disabled` Thorns drops the row), learned durations per spell name and client build, and the window's settings accessors. |
| `test_config_seam.lua` | The one write path: `Wildly_SetConfig` reports through the hook, the library's `config_scan.lua` finds no direct `WildlyDB` write in any ported file, the owner regions are pinned, and the SavedVariables-fix and new-build checks fire (or stay quiet) on the right logins. |
| `test_options.lua` | Builds the options panel and clicks everything in it, with spies in place of the hooks `Wildly.lua` defines: each checkbox, both radio groups and the slider save through the setter and ask the window to rebuild; the panel builds when no text has been measured, and opens from `Wildly_OpenConfig`. |
| `test_libfiles.lua` | Both libraries' file lists, read from their XML: LibGroupBuffs is LibStub plus one runtime file and ships no textures; LibGlass ships its LICENSE and textures; a texture LibGroupBuffs draws that the LibGlass checkout lacks is an error. And that `libfiles.lua` does not mistake a test for its own script mode. |
| `test_stub.lua` | The stub entries Wildly added (`strsplit`, `UnitIsUnit`, `GetRaidRosterInfo`, `UnitGroupRolesAssigned`) keep the client's shape. |

## The stub is an allowlist, and it must model absences

The shared stub fails the run on the read of any global it does not define, so it is the list of
APIs verified present on this client. This addon's own globals are added on top with
`WoW.allowGlobal`, in the local layer.

Anything the addon reads **guarded** — `if Wildly_OpenConfig then`, which exists because
`WildlyConfig.lua` can fail to load while `Wildly.lua` carries on — has to be allowed as nil there,
or the guard throws inside the stub and the branch it protects can never be tested.
`tests/test_bridge.lua` scans the source for those guards and checks them against the list, so the
two cannot drift. Never add a global because a test failed: confirm it in the
build-matched API dump (`C:/Projects/References/forever-api-<build>.md`) and stub it with the
client's exact signature, or list it as known-absent and make the addon cope.
