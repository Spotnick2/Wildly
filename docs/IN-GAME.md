# In-game checks

What has been checked in the real client, by build. The full in-game checklist is in `AGENTS.md`
(Validation). Until a pass covers all of it, record each partial check here, including what it does
**not** cover.

## 70959: Druid smoke check (2026-11-18)

The in-game half of the 70959 bump (#57, PR #59), which the Codex review on #59 asked for.

- **Client:** 1.60.1.70959, enUS.
- **Character:** Drucida-Komakino (SPOTNICK3), a Druid with Mark of the Wild and Thorns, no Gift of
  the Wild.
- **Addon:** the released Wildly v1.1.0, LibGroupBuffs r34, LibGlass r11. Buffy was loaded too, on
  the same r34.

| Check | Result | Evidence |
|---|---|---|
| Loads as a Druid | ✅ | Login line "Loaded. Auto-opens when you join a group." Script errors weren't checked: BugSack was loaded without BugGrabber. |
| `/wildly help` and the spell report | ✅ | `locale enUS, game build 70959, Wildly v1.1.0, library r34`. Mark of the Wild and Thorns resolve. Gift of the Wild is "not learned", correct for this Druid. |
| Settings written on 70959 | ✅ (written only) | After `/reload`, both save files carry `svLoadCheck.build = "70959"`, per-character and account-wide. That proves Wildly **wrote** them on this build, nothing more. Under `AGENTS.md`'s SavedVariables rules, a `/reload` and a read of the file can't show settings load back. And in r34 `loads = true` is a latch carried forward from earlier sessions, so it isn't new evidence. **Persistence across a full exit was not checked on 70959.** |
| Window reads a live buff | ✅ | `learnedDurations = { build = "70959", ["Mark of the Wild"] = 3600, ["Thorns"] = 600 }`, written by Wildly's own engine. |
| Mark row casts | ✅ | The owner left-clicked the Mark row, solo, out of combat, on themselves. |

**One trap found along the way:** the first attempt cast Mark through Buffy while Wildly's window
was closed. Solo with "Show when solo" off, Wildly never reads auras, so it learned nothing. The
`learnedDurations` above came after `/wildly show` and a click on Wildly's own row. To check
Wildly's buff read, open **its** window first.

**Not covered:** SavedVariables persistence across a full exit and relaunch, combat (aura secrecy, the cached timers), party and raid, right-click, the
popover, the Thorns modes, Gift of the Wild and its reagent, the options panel, and the first
`PLAYER_LOGIN` roster count. The full checklist in `AGENTS.md` is still open.
