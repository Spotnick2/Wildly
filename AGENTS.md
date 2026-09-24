# Wildly Agent Instructions

Trust these instructions. Search the codebase only when information here is incomplete, stale, or
appears incorrect.

## Review policy

Use `$wow-addon-review` as the shared source of truth for review routing, committed-diff scope,
client/API evidence handling, validation, finding format, and merge-readiness verdicts.

Repository-specific additions:

- Post every pull-request review and follow-up review on the PR, then link the posted review in the
  final response.
- Reviews run from `C:\Projects\Wildly`. PR numbers overlap with Priestly and LibGroupBuffs, so name
  the repository explicitly when reviewing from elsewhere (`gh pr diff 3 -R Spotnick2/Wildly`).
- Match `MEASURED_ON_BUILD` in `WildlyConfig.lua` to
  `C:/Projects/References/forever-api-<version>.<build>.md`. Runtime measurements for this client
  live in `C:\Projects\Priestly\docs\FOREVER-PROBE.md` (and Wildly's own `docs/` once it has
  measured something Druid-specific); addon-agnostic Forever findings live in
  `C:/Projects/References/PORTING-TBC-TO-FOREVER.md`.

## What This Repository Is

Wildly Forever is a World of Warcraft addon for **WoW: Forever 1.60.1** (Interface `16001`). It is
PallyPower-style Druid buff management for **Mark of the Wild / Gift of the Wild** and **Thorns**
across party and raid members.

Out of scope: general Druid utility (Innervate, Rebirth, cures, forms, HoTs). Keep it a buff
maintenance tool.

**TBC Classic Anniversary is no longer supported.** The last TBC code is the history before the
Forever port (Interface 20505). Do not add flavor branching for it.

Forever is *Vanilla content running on Blizzard's Retail (Mainline) codebase*: content assumptions
are Vanilla, API assumptions are Retail. Read `C:\Projects\References\PORTING-TBC-TO-FOREVER.md`
before touching an unfamiliar API.

Wildly is one of three thin hosts on **[LibGroupBuffs-1.0](https://github.com/Spotnick2/LibGroupBuffs)**
(with Priestly and Magely). **Priestly is the worked example**: `C:\Projects\Priestly`, especially
`Priestly.lua`, `PriestlyCompat.lua` and `PriestlyConfig.lua`. When in doubt about how a host
should do something, do what Priestly does, and copy its instructions rather than reinventing them.

There is no build system, compiler or package manager. CurseForge's packager handles releases.

## Port status

The port lands in slices, one issue and PR each:

1. **Foundation** — TOC, `WildlyCompat.lua`, `.pkgmeta` externals, tests, deploy, CI, this file.
2. **Config** — `WildlyConfig.lua` on the library's Settings write path, Priestly's panel shape.
3. **Host** — `Wildly.lua` becomes DEFS + engine + window + footer + events; the hand-built TBC
   window is deleted, not ported.
4. **Thorns** — the `membersFor` filter for its five modes.
5. **In-game pass and release.**

Slices 1 to 4 are done and **v1.0.0 is the first Forever release** (slice 5). The in-game pass
had no Druid available, so it was handed to players and testers, and the release notes say so:
**no Wildly build has been verified in game yet.** The unmeasured items below and the in-game
checklist under Validation are the open work. Record what is measured in `docs/`, and delete this
section once a pass has been done.

`H.NOT_YET_PORTED` in `tests/harness.lua` is empty. It stays, with the check in `test_bridge`, until
this section is deleted. Update this section as slices land, and delete it when the port is done.

## Repository Layout

- `Wildly.toc` — addon manifest: interface version, saved variables, load order.
- `WildlyCompat.lua` — the bridge to the shared library: checks every runtime file of the active
  copy loaded completely (`NEEDS_MINOR` floor + completion markers), exposes `Wildly.API`,
  `Wildly.Settings`, `Wildly.Engine`, `Wildly.UI`, and `Wildly.RegisterEvents`, which reports
  rejected events in chat. No API code lives here.
- `WildlyConfig.lua` — options panel, defaults, the Thorns mode, exported config helpers.
- `Wildly.lua` — `DEFS`, the Thorns member filter, the reagent footer items, the spec icon and
  colours, event handling, slash commands and the test seam. Everything else is LibGroupBuffs:
  - `Engine.lua` is the buff logic (aura cache, roster, stats, targeting, click mapping,
    `UNIT_AURA` filtering).
  - `UI.lua` is the window (rows, popover, secure buttons, dragging, ticker, what combat defers).
  A change to how buffs are read, targeted or drawn belongs in the library, not here.
- `tests/` — Lua 5.1 unit tests, no game client. See `tests/README.md`.
- `Tools/deploy.ps1` — deploy to the local Forever AddOns folder, library included.
- `.github/workflows/package-check.yml` — tests against the pinned library, a dry-run package, and
  a check that the zip embeds the library. Publishes nothing.
- `.pkgmeta`, `README.md`, `CHANGELOG.md`, `LICENSE` — packaging and user-facing material.

**One dependency: LibGroupBuffs-1.0.** It is never committed here — `Libs/` is git-ignored:

- **Release:** `.pkgmeta` `externals` embeds it at `Libs/LibGroupBuffs-1.0`, **pinned to a tag**
  (`r<MINOR>`), so a release cannot change underneath its own source.
- **Development:** check it out **next to this repository**, as `../LibGroupBuffs`. `tests/run.ps1`
  and `Tools/deploy.ps1` read it from there (or from `-Library`), print the revision they used, and
  fail loudly if it is missing. There is no vendored fallback.
- **CI** checks out the pinned tag, not the library's `main`.

`NEEDS_MINOR` in `WildlyCompat.lua` must equal the pinned tag; `tests/test_manifest.lua` checks the
TOC path, the externals key, the tag, the floor and the ignore rule all agree.

### A gap in a library seam

The seams were designed from Priestly alone, so Wildly will find gaps (r11's `popDivider`
appearance key was the first). **Never fork or patch the library from here.** Fix it in
`C:\Projects\LibGroupBuffs`, following that repository's `AGENTS.md`: issue, branch, PR, `MINOR`
raised in every runtime file, the previous tag's files added as test fixtures, Priestly's suite run
against the working copy, merge, tag `r<MINOR>`. Then bump the pin here: `tag:` in `.pkgmeta` and
`NEEDS_MINOR` in `WildlyCompat.lua`, in a Wildly PR.

## Architecture

Load order from `Wildly.toc`:

1. `Libs\LibGroupBuffs-1.0\LibGroupBuffs-1.0.xml` — LibStub, then Compat, Settings, Engine, UI.
2. `WildlyCompat.lua` — refuses a missing, broken or too-old library with a chat message (a
   too-old one is named as that, with both versions, since nothing crashed), else exposes it.
   Once ported, `WildlyConfig.lua` and `Wildly.lua` return early when `Wildly.API` is nil, so a
   broken library is one message, not a cascade.
3. `WildlyConfig.lua` — `WildlyDB` defaults, the settings object, the options panel and the
   `Wildly_*` config helpers.
4. `Wildly.lua` — the host.

`Wildly.lua` exposes, for the config: `Wildly_ScheduleRefresh`, `Wildly_ForceRebuild` (does
nothing in combat; the library rebuilds a visible window at combat end), `Wildly_OnSoloToggle`,
`Wildly_ApplyAlpha`. It decides when the window opens: at login for a Druid in a group (or solo
mode) unless `visible` is false, or later when the spells arrive; on joining a group, overriding a
close (but not the roster arriving just after login); never on other roster churn, a ready check or
a settings change over a close; nothing at all on another class, slash commands included (one
line saying so). The Gift rank and spec icon are read from the spellbook when spells change, never
per rebuild. Its test seam is
`Wildly._test`.

`WildlyConfig.lua` exposes: `Wildly_EnsureDefaults`, `Wildly_ShowSolo`, `Wildly_TrackPets`,
`Wildly_IsBuffEnabled` (`"thorns"` is false in the `disabled` mode), `Wildly_GetThornsMode`,
`Wildly_GetFrameAlpha`, `Wildly_FrameLocked`, `Wildly_ShowClickHints`, `Wildly_PopoverSide`,
`Wildly_LearnDuration` / `Wildly_GetLearnedDuration` (for the engine's duration seams),
`Wildly_OpenConfig`, the write path `Wildly_SetConfig(key, value)` and its hook
`Wildly_OnConfigChanged(key)` (empty today; the one place a migration or the SavedVariables fix
lands), and `Wildly_HandleEnteringWorld` / `Wildly_CheckClientBuild`, which its own event frame
calls. It calls, guarded, the hooks `Wildly.lua` defines: `Wildly_ForceRebuild`,
`Wildly_OnSoloToggle`, `Wildly_ApplyAlpha`. On any class but Druid its event frame does nothing:
no options page, no `WildlyDB`, no chat notices; the accessors all cope with `WildlyDB` being nil.
`EnsureDefaults` reports every key it seeds or repairs through `settings:Changed`, and reading a
learned duration never writes (a stale build's table is replaced only by the next learn).

Current `WildlyDB` keys: `trackMark`, `thornsMode`, `showSolo`, `trackPets`, `frameAlpha`,
`popoverSide`, `lockFrame`, `showClickHints` (all in `DEFAULTS`), `learnedDurations` (keyed by
**spell name**, reset when the client build changes), `visible` and `pos` (the window's own state,
never defaulted), and `svLoadCheck` (never in `DEFAULTS`). There is no TBC migration: this is a
separate install, and nothing loads back on this client anyway.

### Buff definitions

`DEFS` are ID-based, the library's format: `id`, `snglID`, optional `grpID`, enUS `sngl` / `grp`
fallbacks, `fallbackIcon`, a `duration` seed. Names are resolved from IDs at runtime by
`engine:RefreshSpells()`, never the reverse.

| id | snglID | grpID | Notes |
|---|---|---|---|
| `mark` | 1126 Mark of the Wild | 21849 Gift of the Wild | Left-click Gift when known, else Mark. |
| `thorns` | 467 Thorns | — | No group form, so both clicks cast Thorns. |

The TBC flags `always`, `needsKnown`, `optional` and `leftUsesSingle` are **gone**. Availability is
the engine's (a row exists only for a spell the Druid knows), and a def with no `grpID` casts the
single spell on both clicks, which is what `leftUsesSingle` did.

### Thorns and `membersFor`

Thorns is why the library has `membersFor(def, members)`. It returns the members one buff's row
covers; the UI calls it **once per row** and uses that list for the stats, target, popover and
clicks, so they cannot disagree. An empty list means no row. Modes, from `WildlyDB.thornsMode`:

| Mode | Members |
|---|---|
| `default` | the group's tanks; yourself if it has none (or you are solo) |
| `tanks` | tanks only |
| `self` | yourself only |
| `everyone` | every player (never pets) |
| `disabled` | no row: `isBuffEnabled("thorns")` is false |

`MembersFor` in `Wildly.lua` passes every other buff's list through untouched. A tank is
`UnitGroupRolesAssigned(unit) == "TANK"` or the raid's `MAINTANK`, collected once into a set of
unit tokens and forgotten on roster and role events (`PLAYER_ROLES_ASSIGNED`,
`ROLE_CHANGED_INFORM`). Whether the group "has tanks" is decided over the whole group, not per
subgroup. Pets are recognised by the engine's own tag - a member `class` of `PET` or `PET_<class>` -
and never covered.

Two traps the TBC code fell into, which the filter must not repeat:

- **"Is this me?" is `UnitIsUnit(m.unit, "player")`, never `m.unit == "player"`.** In a raid the
  roster names you `raidN`.
- **Never match a raid member by name.** Forever characters have surnames, and `UnitName` returns
  only the first name for anyone but the player. The main-tank role comes from
  `GetRaidRosterInfo(i)` and belongs to the unit `"raid"..i` — match by index.

Not yet measured, and needed before this ships:

- Whether the spec-icon spells resolve (Moonkin Form 24858, Swiftmend 18562, Leader of the Pack
  17007), and whether the spellbook's rank subtext for Gift of the Wild reads `Rank 1` / `Rank 2`,
  which is what picks the reagent (`API.GetSpellRank`).
- Whether `GetNumGroupMembers()` already counts the group at `PLAYER_LOGIN`. `Wildly.lua` treats a
  0-to-n roster change within `ROSTER_SETTLE_SECONDS` (5) of login as the roster arriving, not a
  join, so it cannot undo a close; the number is a guess until measured.
- Whether `UnitGroupRolesAssigned` returns anything but `"NONE"` on this client (there is no LFG).
  If not, a party has no tanks and `default` covers only you there. Also which of
  `PLAYER_ROLES_ASSIGNED` / `ROLE_CHANGED_INFORM` fires on a role change.
- `GetRaidRosterInfo`'s return shape. It is only in the dump's undocumented globals; the stub
  models the Retail tuple (role 10th). `UnitIsUnit` and `UnitGroupRolesAssigned` are declared in
  the dump.

### Reagents

`footerItems()` shows the Gift of the Wild reagent for the rank the Druid knows, read with
`API.GetSpellRank`: rank 1 **Wild Berries** (17021), rank 2 **Wild Thornroot** (17026). Wild
Quillvine (22148) is TBC's rank 3 at level 70 and cannot exist at Forever's cap of 60; it is
deliberately not listed, and an unrecognised rank shows no reagent rather than a guess.

### Appearance

Wildly's orange border, header line, popover border and divider (`#ff7c0a` family) and its spec
icon go through the UI's `appearance()` host callback. Never fork `UI.lua` for a colour: if a
colour has no key, that is a library gap (see above).

The talent-tab scan is gone on this client (`GetNumTalentTabs` / `GetTalentTabInfo` do not exist),
so the spec icon comes from known spells, by ID: Moonkin Form (24858) → Balance, Swiftmend
(18562) → Restoration, Leader of the Pack (17007) → Feral, else the Druid class icon. Tree of Life
and Mangle are TBC spells.

## SavedVariables

`WildlyDB` is **per character**; `WildlySVCheck` is account-wide and holds only the library's
`svLoadCheck` marker, so the addon can tell when account-wide storage is fixed. Same as Priestly.

**NO SavedVariables load back on this client — per-character included** (measured on build
1.60.1.69913; see Priestly's `AGENTS.md` and `docs/FOREVER-PROBE.md` section 11). Every session
starts from defaults. Write the addon so losing every setting at login is survivable.

- **Never verify persistence by reading the SV file or diffing it against `.bak`.** It always
  looks populated because `EnsureDefaults` rewrites every default each session. Count launches
  inside the addon, or check a key that defaults to nil (`pos`).
- **Never with `/reload` alone.** `/reload` keeps the client process alive and can only prove
  something is broken. Confirm with a **full exit and relaunch**.
- **Every write to `WildlyDB` or `WildlySVCheck` goes through the settings write path**
  (`Wildly_SetConfig`, built on the library's `Settings.New`), except inside
  `-- config-owner: begin/end` regions in `WildlyConfig.lua` (three: the saved-table accessors,
  `EnsureDefaults`, the learned-duration cache). `tests/test_config_seam.lua` scans every ported
  file with the library's `tests/config_scan.lua` and pins the region count. Owner code that
  writes through a local alias reports it with `settings:Changed(key)`: the scan cannot see an
  alias.
- **`svLoadCheck` must never be in `DEFAULTS`**: it detects Blizzard's fix by being written every
  session and never defaulted.

## WoW API And Lua Rules

- Target the **Retail/Mainline** API. `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` here.
- Keep `## Interface: 16001`. The format is `%d%02d%02d`, so 1.60.1 → 16001. `11601` is a
  transposed-digit bug you will see in the wild.
- **Never call a moved API directly.** Add it to LibGroupBuffs' `Compat.lua` and reach it through
  `Wildly.API`.
- **Never copy a library function into a local** (`local F = API.F`). `API` is shared with every
  addon that embeds the library and a newer copy upgrades it in place; a copy keeps the old
  version. Call through `API`, or wrap: `local function F(...) return API.F(...) end`. Call engine
  and ui methods (`engine:GroupStat(...)`), never a copy of them.
- Register events only through **`Wildly.RegisterEvents`**, never the library's
  `API.RegisterEvents*` or a bare `frame:RegisterEvent`. `RegisterEvent` throws on an unknown
  event name and may return `false`; the wrapper reports both in chat.
- **`C_Spell.GetSpellInfo(name)` only resolves spells the player KNOWS.** By ID it always works.
- **`UnitName(unit)` is a trap**: first name only for anyone but the player, with the surname where
  the realm used to be. Display with `API.UnitDisplayName`; key caches on `API.UnitKey` (GUID).
- **`GetInstanceInfo()` returns the continent outdoors** — gate on `instanceType ~= "none"`.
- **Auras are unreadable in combat for every unit**, and a secret value throws when compared or
  truth-tested. Never read an aura outside the engine (`API.ReadBuff`).
- `ReloadUI()` is protected — use `/reload`.
- Errors are off by default (`/console scriptErrors 1`) and stop being delivered after 100 in a
  session.
- Slash-command arguments can contain a two-word name: `^(%S+)%s+(.+)$`, never two `%S+`.
- Lua 5.1. `0` is truthy — `x or default` does not guard a numeric that can be 0.

## Content Rules (Vanilla, mid-beta)

- **Level cap is 60**, and the live beta is capped far lower. Never hardcode a cap.
- **Gift of the Wild may not be learnable yet.** Every row must work single-target only; the
  engine's `ClickSpells` falls back so the primary click is never dead.
- **Spell text and reach can differ from Vanilla.** Forever's Prayers buff the whole raid, not one
  party; whether Gift of the Wild does the same is **not yet measured**. Read the client's tooltip.
- **Durations are learned, not assumed.** `DEFS[].duration` is a seed; the engine learns the real
  value from live auras, keyed by spell name.

## Secure UI Rules

The window is LibGroupBuffs' `UI.lua`, which owns these rules; do not reimplement them here.

- **In combat the window touches nothing.** Both frames parent secure buttons, so the client
  silently refuses to hide, move, re-anchor or stop a drag on them. `ui:Close()` returns false and
  the host says the window closes when combat ends (`onCloseDeferred`); `ui:OnCombatEnd()` on
  `PLAYER_REGEN_ENABLED` does what was asked.
- Buttons register **both mouse edges** (`API.ClickEdges`), and **never set `typerelease`** — that
  would cast twice and burn two reagents.
- No `SecureHandler*`, `_onstate-*` or state drivers: `loadstring_untainted` is missing on this
  client.
- **Known limitation, do not try to fix it:** a roster change mid-combat can hand a wired `raid3`
  token to a different player until `PLAYER_REGEN_ENABLED`.

## Validation

Offline, on every change:

```powershell
pwsh tests\run.ps1        # luac -p + all unit tests; needs ../LibGroupBuffs and Lua 5.1's luac
```

The first line names the library checkout and revision the tests ran against, next to the tag a
release would ship. They differ while working on both; they must match before a release.

`tests/wow_stubs.lua` is an **allowlist**: reading any global it does not define fails the run. It
started as a copy of LibGroupBuffs' stub, and every difference is marked `Wildly:` so a library
fix can be carried over; `tests/test_stub.lua` pins those differences. Before stubbing a new global, confirm it exists in the
newest `C:/Projects/References/forever-api-<build>.md` and stub it with the client's exact
signature; never add one because a test failed. Strict globals do not cover **methods** — for
anything built on a widget method, execute it and assert what it produced.

In game — **nothing ships without this pass**:

```powershell
pwsh Tools\deploy.ps1
```
```
/console scriptErrors 1
/reload
```

- AddOn list: enabled **and not flagged out of date**.
- `/wildly help | config | show | hide | reset | pos`; drag the frame.
- Rows appear for what the Druid actually knows; no Gift wiring when Gift is not known.
- Left and right click cast, out of combat and in combat, on yourself and a party member.
- Thorns: each mode, solo, party and raid; in a raid, "self" finds you as `raidN`; a main tank with
  a surname is found. Record what `UnitGroupRolesAssigned` and `GetRaidRosterInfo` actually return.
- Enter combat: timers count from the cache; a member never seen shows `?`, not `MISS`.
- Roster churn: invite/leave, reshuffle subgroups, pets — state follows the player, not the slot.
- Footer: the right reagent for the known Gift rank, and its count.
- Options panel: every control.

## Workflow

1. **Open an issue first**, with enough context to review against.
2. **Branch** off `main`. Never commit to `main` directly.
3. **Open a PR** referencing the issue (`Closes #N`). CI runs the syntax check, the unit tests and a
   dry-run package build.
4. **Review before merge** using `$wow-addon-review`; post the result on the PR.
5. Squash-merge, then delete the branch.

## Releasing

CurseForge (project **1542496**) builds from a repository webhook when it sees a tag, and
publishes `CHANGELOG.md` as the release notes. **Do not add a release workflow**; it would publish
a second time (see Priestly's `AGENTS.md`, Packaging, for the history).

1. **Every tag needs a `CHANGELOG.md` entry, committed before the tag is pushed**, written for
   players.
2. The release type comes from the **tag name**: `alpha` → Alpha, `beta` → Beta, else Release.
   CurseForge offers only Release to most users; tag `beta` only to hold a build back.
3. **Check the published zip carries LibGroupBuffs, and nothing else.** CI proves the BigWigs
   packager embeds it, but releases are built by CurseForge's own packager from the tag webhook,
   which CI cannot run, and **the two do not behave the same**. Download the published file, run
   `lua tests/libfiles.lua <unzipped>/Wildly/Libs/LibGroupBuffs-1.0 ship`, then count the files in
   that folder: seven - the six that command lists (the XML and the five files it loads) plus
   `LICENSE`. A zip without them is an addon that does not start for everyone who updates.

   **CurseForge does not apply an external's own `.pkgmeta`.** Measured on Priestly's v2.0.6
   download: the library's `tests/`, `AGENTS.md`, `CLAUDE.md` and `README.md` all shipped, 46 files
   instead of 7. The entries under `Libs/LibGroupBuffs-1.0/` in *this* `.pkgmeta` are the guarantee,
   and `tests/test_manifest.lua` mirrors them from the library's own list.
4. Keep `@project-version@` in the TOC; `Tools/deploy.ps1` rewrites it to `dev` in the deployed
   copy only.
