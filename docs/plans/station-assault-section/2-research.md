# Research — boss-gated progression in autoscrolling shmups

Scope: the three open questions from `1-context.md`. Searches were run with WebSearch on
2026-09-01. Where the genre has no prescriptive answer, that is said plainly rather than
invented — see *Question 2* below.

## Findings

| Finding | Tradeoff | Typical values | Source |
|---|---|---|---|
| **1. The boss *is* the gate.** Almost every scrolling shmup since the early 80s ends a level (or a level segment) with a boss, and a level that ends without one "would feel as if something were missing — a challenge or test to prove one's worth to continue to the next section." Progression gating on a boss is the genre default, not an exotic choice. | Hard gating is only safe if the player can always eventually win. A boss the player *cannot* kill (underpowered ship, a bug that makes a part invulnerable) becomes a permanent softlock, which is why the genre pairs the gate with finding 2 rather than leaving it open-ended. | — | [Video Game Boss Design For Shmups](https://www.gamedeveloper.com/design/video-game-boss-design-for-shmups) |
| **2. Boss timers exist to stop *milking*, and they end the encounter by removing the boss.** "Boss battles in many Shoot 'em Ups are timed, usually to prevent you from infinitely milking a boss… After the time limit runs out, the boss usually escapes or self-destructs, allowing you to proceed to the next level anyway, though often you will be penalized by getting reduced end-of-stage bonuses." Multi-phase fights sometimes time out **per phase**, advancing the boss to its next phase. | The timeout is an *escape hatch with a cost*, never a silent skip. Critically, the boss is **removed** on timeout — the fight genuinely ends. A timeout that advances the level while leaving the boss alive is not a pattern any shipped game uses; it is the bug `1-context.md` found in `level_director.gd:106-107`. The cost of the escape hatch is that "unskippable" becomes "unskippable in practice, not in principle". | G-Darius: **180 s** per normal boss, **540 s** for the final boss. | [TV Tropes — Time-Limit Boss](https://tvtropes.org/pmwiki/pmwiki.php/Main/TimeLimitBoss), [Tropedia — Time Limit Boss](https://tropedia.fandom.com/wiki/Time_Limit_Boss), [Shmups Wiki glossary](https://shmups.wiki/library/Help:Glossary), [G-Darius — Shmups Wiki](https://shmups.wiki/library/G-Darius) |
| **3. Corollary: the existing 10 s cap is off by more than an order of magnitude.** The shortest boss timer this search found in a shipped game is G-Darius's 180 s. `LevelDirector._wait_enemies_cleared()` gives up after 10 s — and worse, the clock starts on `WaveManager.waves_complete`, which fires when the last wave *triggers*, not when the fight ends. | Whatever number the plan picks, it is a *safety net*, not a balance knob: it should be long enough that a competent player never sees it. Raising it globally would also change `cloud_descent`, whose 10 s is correctly sized for "wait for stragglers to fly off" — so the value has to become per-section. | 10 s today; genre floor ≈ 180 s. | derived from finding 2 + `assault/scenes/systems/level_director/level_director.gd:104-107` |
| **4. There is a standard "boss arrives" beat, and it is a *warning*, not a cutscene.** Originated by Darius (1987) — "WARNING! A HUGE BATTLESHIP IS APPROACHING FAST" — and since used by Ikaruga, DonPachi and many others: screen flashes red, alarm sound, stage music fades or cuts, warning text. It can be visual only or audio only; both is the full form. | It costs 2–4 s of dead time in which the player cannot fight, which is exactly the point (it re-frames the pacing) but is wasted if the boss is already on screen when it plays. It also needs a signal to fire on — so the *hook* is cheap to reserve now even if the presentation lands in a later sub-item. | — (no consistent duration reported) | [shmups.system11 — origin of "Warning" alerts](https://shmups.system11.org/viewtopic.php?t=68297), [Guinness — first game to feature boss warnings](https://www.guinnessworldrecords.com/world-records/first-game-to-feature-boss-warnings), [TV Tropes — Boss Warning Siren](https://tvtropes.org/pmwiki/pmwiki.php/Main/BossWarningSiren) |
| **5. Boss length should be proportional to the level, and mid-bosses must stay under the end boss.** The fight's difficulty should rise across it — "the end of the boss battle should be more intense than the beginning", Cave bosses "spit out everything they're made of immediately before being killed off." | Level 1's other sections run 30 s / 30 s / 110 s / ENEMIES_CLEARED. A mini-boss proportional to that is a **30–60 s** fight, not a three-minute one — so the 180 s genre timer is a very slack safety net here, which is what we want. But it also means the section's own pacing budget is tight: sub-items 3–5 (laser phase, reinforcements, death handoff) all have to fit inside roughly a minute. | Level 1 sections: 30 s, 30 s, 110 s. | [Video Game Boss Design For Shmups](https://www.gamedeveloper.com/design/video-game-boss-design-for-shmups), `assault/scenes/levels/edelia/1/level_1_director.gd:1-8` |
| **6. The "fly around a giant stationary structure" boss is a known form.** Horizontal shmups have had multi-screen ship/creature bosses since R-Type stage 3 (May 1987), where the fight is a trip around the structure facing hazards from its top, bottom and rear. | It validates a **stationary** boss the player orbits — which is what a space station is, and what `ArenaCamera`'s pinned `global_position` makes easy. The tradeoff is that a static target with no approach beat reads as scenery: the encounter needs the arrival framing of finding 4 to land as a boss rather than as an obstacle. | — | [racketboy forum — shmup boss battle around giant ship](https://racketboy.com/forum/viewtopic.php?f=44&t=53833), [Video Game Boss Design For Shmups](https://www.gamedeveloper.com/design/video-game-boss-design-for-shmups) |

## Answers to the open questions

**Q1 — How do shipped shmups gate progress on a boss? Is a hard timeout ever the right default?**
Gating is the genre default (finding 1). A timeout is standard *as an anti-milking escape hatch*
(finding 2), and its defining property is that it **ends the fight by removing the boss**, usually
with a score penalty. So the current behaviour — advance the level, leave the boss parented to
`enemy_container` forever — matches nothing in the genre and is simply the bug. Two defensible
shapes for this project, for the plan to choose between:

- **(a) Per-section timeout export**, defaulting to the current `10.0` so `cloud_descent` is
  bit-identical, with `station_assault` set generously (genre floor is 180 s; the fight is designed
  for 30–60 s per finding 5). On expiry, keep today's `push_warning` + advance.
- **(b) (a) plus a defined expiry action** — free whatever is left in `enemy_container` before
  advancing, so the boss cannot survive into `planet_approach`. This is what the genre actually
  does. It is a behaviour change to `cloud_descent`'s timeout path too, so it needs a test that
  pins the non-timeout path unchanged.

**Q2 — Where on screen does a stationary mini-boss sit?**
**No prescriptive answer found.** Searches for mid-boss screen placement and player dodge-space
returned only general beginner guides with nothing quantitative, and the one community guide that
looked promising (Giest118's bullet-hell boss guide on shmups.system11) returns HTTP 403 to
WebFetch. No number is invented here. What research *does* support is finding 6: a stationary
structure the player orbits is an established form. The plan should therefore derive placement
from this project's own geometry — 640×360 design space, `ArenaCamera.WORLD_SCALE = 2.0`, the
station authored at ~4× the 64×64 player — rather than from a borrowed constant, and state the
arithmetic so the reviewer can check it.

**Q3 — Is there a standard "boss arrives" beat worth reserving a hook for?**
Yes — finding 4. The presentation (flash, siren, music cut, text) belongs to a later sub-item, but
the *signal* it hangs off is nearly free to add now while `LevelDirector` is already being edited,
and retrofitting it later means touching the director a second time. Reserving it is cheap;
building it now is scope creep.

## Sources

- [Video Game Boss Design For Shmups — Game Developer](https://www.gamedeveloper.com/design/video-game-boss-design-for-shmups)
- [TV Tropes — Time-Limit Boss](https://tvtropes.org/pmwiki/pmwiki.php/Main/TimeLimitBoss)
- [Tropedia — Time Limit Boss](https://tropedia.fandom.com/wiki/Time_Limit_Boss)
- [Shmups Wiki — Help:Glossary](https://shmups.wiki/library/Help:Glossary)
- [Shmups Wiki — G-Darius](https://shmups.wiki/library/G-Darius)
- [shmups.system11.org — The origin of "Warning" alerts before boss?](https://shmups.system11.org/viewtopic.php?t=68297)
- [Guinness World Records — First game to feature boss warnings](https://www.guinnessworldrecords.com/world-records/first-game-to-feature-boss-warnings)
- [TV Tropes — Boss Warning Siren](https://tvtropes.org/pmwiki/pmwiki.php/Main/BossWarningSiren)
- [racketboy forum — Shmup boss battle around giant ship](https://racketboy.com/forum/viewtopic.php?f=44&t=53833)

**Not retrievable:** [Giest118's Guide to Making Good Bullet Hell Bosses](https://shmups.system11.org/viewtopic.php?t=44816) — HTTP 403.
