# Research — Station laser phase

How shipped games make a telegraphed, sweeping boss beam fair. Every row below was read from
the source named; nothing here is inferred from a search-result snippet alone. Two sources
(`gamedeveloper.com` boss-design article, `shmups.wiki` Boghog guide) were fetched and turned
out to contain **nothing** on lasers or telegraphs — recorded so the next cycle does not
re-fetch them. `ultrakill.fandom.com` returned HTTP 402 to WebFetch and was recovered with
`./scripts/fetch-page.sh`.

## Findings

| # | Finding | Tradeoff it implies | Typical values | Source |
|---|---|---|---|---|
| 1 | **Danmakufu's "delay laser" is the genre-standard beam telegraph**: a hitbox-less preview of the exact beam, spawned N frames before the real one. The tutorial's worked example is a Master Spark — a screen-covering beam — with the delay laser created **120 frames** before the laser spawns, and the spark itself lasting **120 frames**. The tutorial also warns the preview must be **≥ 20 px wide** ("anything under 18 has a high chance of having an invisible or near-invisible delay laser, which is always a bad thing"). | A 2 s telegraph is what a *screen-covering* beam costs. Spend that on every beam in a 40–50 s fight (finding 4) and the fight is mostly waiting. So: long telegraph for the big sweep, and only for the big sweep. Separately, a telegraph thinner than the beam is worse than no telegraph — the player learns to ignore it. | telegraph **120 f = 2.0 s**; active **120 f = 2.0 s**; preview width ≥ 20 px | [Sparen's Danmakufu ph3 tutorials, Lesson 9](https://sparen.github.io/ph3tutorials/ph3u1l9.html) |
| 2 | **Reaction-time floor.** Simple visual cue → **200–300 ms** response; ~**15 frames** at 60 fps as a working baseline for a typical player; asking for more than **~20 frames** of total response is called out as an unreasonable demand. | This is the *floor*, not the target. It assumes one cue and a player already looking at it. A telegraph set near the floor is defensible on paper and reads as a cheap shot in play, because during a boss phase the player is also tracking bullets, their own ship and the boss. The gap between the 0.25–0.35 s floor and finding 1's 2.0 s is the readability budget. | 200–300 ms; 15 frames baseline; 20 frames ceiling | [Retro Game Deconstruction Zone — Reaction Time and Game Design](https://www.retrogamedeconstructionzone.com/2020/05/reaction-time-and-game-design.html) |
| 3 | **ULTRAKILL's Mindflayer is a shipped sweeping-beam boss attack, documented frame-exactly.** The beam has **constant angular velocity** and the whole attack lasts **1 second**. It aims at the player's position *at the frame of firing* and its path meets that original position at **0.25 s** — i.e. it leads the player. A **thin coloured indicator line marks where the beam will start**, and the wiki states outright that the indicator is *not* accurate to where the beam will be: its job is to tell you "whether the beam will initiate in the direction of or opposite to the player's velocity". A 2021 patch line reads "Mindflayer beam **warning flash changed to blue**" — the warning colour was a shipped bug worth patching. | A sweeping beam does not need a telegraph that predicts its whole path; it needs one that tells the player **which way to run**. That is much cheaper to build and more readable. But it only works if the warning is visually distinct from the beam — a studio shipped, then patched, exactly this. | sweep **1.0 s**, constant ω; lead time **0.25 s**; indicator = start ray only | [ULTRAKILL Wiki — Mindflayer](https://ultrakill.fandom.com/wiki/Mindflayer) (via `fetch-page.sh`) |
| 4 | **Boss-fight time budget, from a developer of several bullet-hell shmups.** "A stage 1 boss shouldn't exceed **40 to 50 seconds**." Cave-style bosses hold one attack for "**no more than five to ten seconds**" before switching; Touhou-likes use "one phase, one attack" and instead make the single attack denser. The cardinal rule given is *force the player to stay alert* — the failure mode is the player "spinning his wheels, constantly doing the same thing over and over". | Our station is a **Level-1 mini-boss**, so ~45 s is the whole fight, turret phase included. The laser phase is therefore a **10–20 s slice**, and inside it the beam must re-fire on a **5–10 s cycle** or it becomes filler. A single 2 s telegraph + 2 s beam + gap lands almost exactly on that cycle; a 3 s telegraph (what the level's static laser columns use) does not fit twice. | stage-1 boss ≤ 40–50 s; attack switch every 5–10 s | [Giest118's Guide to Making Good Bullet Hell Bosses](https://shmups.system11.org/viewtopic.php?t=44816) |
| 5 | **Do not randomise attack order or trajectories.** Same source: "General guidelines when using randomness: Keep attack densities consistent · Do not have it play a part in the scoring mechanics at all · **Don't decide attack orders based on randomness**." His worked failure case is a boss picking from four attacks at random — "at least one player will report that the boss used its hardest attack over and over"; the developer "can't get it to use its attacks equally no matter what". His recommended alternative to RNG is deriving variation from the **player's own position** or a sine over a counter, which looks random but has a known value range. | The backlog says the station "fires beams at **varying** positions", and the obvious implementation is `randf()`. That is the documented mistake: it makes the phase's difficulty non-reproducible *and* makes a GUT test unable to assert anything about beam placement. A fixed angle sequence gives varied-looking beams, identical difficulty every run, and a testable phase. | fixed sequence; vary by player position, not RNG | [Giest118's Guide](https://shmups.system11.org/viewtopic.php?t=44816) |
| 6 | **A rotating beam is read as one threat zone, not threaded.** For "rotating bullets (Compile), oscillating bullets, or curving bullets" the advice is to "visualize them as large swathes of bullets/fat lasers/large moving circles, and their entire trajectory treated as one large threat zone that should be avoided". Alongside this, the standing genre rule that even the most chaotic patterns must leave gaps to weave through. | The player will not try to cross a sweeping beam — they will leave the arc entirely. So the design constraint is **the swept region must not be the whole screen**: with enough simultaneous rotating beams there is no correct play, only luck. This caps beam count from the player's side, independently of framerate or clutter. | — | [shmups.wiki — Help:Dodging strategy](https://shmups.wiki/library/Help:Dodging_strategy) |
| 7 | **Simultaneous patterns must be visually distinguishable**, and danmaku games need "exceptionally good visibility to guarantee a fair, non-frustrating player experience"; separate simultaneous patterns should use different-looking bullets. | If the laser phase runs at the same time as bullet-hell fire (sub-item 4), the beams and the bullets have to look nothing alike. Our `LaserRay` is a 56 px lit core with its own charge-up animation, which already differs from any pooled bullet — but this is a real constraint on sub-item 4, not a free pass. | — | [Boghog's bullet hell shmup 101](https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101) |

## Sources that turned out to be empty

| Source | Why it was tried | What it actually had |
|---|---|---|
| [gamedeveloper.com — Video Game Boss Design For Shmups](https://www.gamedeveloper.com/design/video-game-boss-design-for-shmups) | Top hit for boss design | Five general principles (difficulty, variety, length, pay-off, character). **No** telegraph, laser or timing content. Do not re-fetch. |
| [Boghog's bullet hell shmup 101](https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101) | Named in earlier plans | Mentions lasers only as a *player* focus-shot weapon. Useful only for finding 7. |
| [SLYNYRD Pixelblog 32 — Shmup Design Part 2](https://www.slynyrd.com/blog/2021/2/15/pixelblog-32-shmup-design-part-2) | Shmup design series | Author states explicitly: "we still have no UI, or bosses". Bosses were deferred to a Part 3. Do not re-fetch. |
| [bugnet.io — How to Design Enemy Attack Telegraphs](https://bugnet.io/blog/how-to-design-enemy-attack-telegraphs) | Telegraph-specific | Philosophy only, zero numbers. |

## Answers to the open questions from `1-context.md`

**Q1 — What telegraph duration for a sweeping boss laser?**
**~2.0 s from first warning pixel to lethal.** Finding 1 gives 2.0 s for a screen-covering beam;
finding 2 puts the floor at ~0.3 s and warns that the floor is not the target. The level's
existing static laser columns use `warn_duration = 3.0`, which finding 4 rules out for a beam
that must re-fire on a 5–10 s cycle.

Converting to our `LaserRay` API — **corrected after review round 1, which measured this on a
live instance:** `start()` plays `laser_init` **and** starts the `warn_duration` timer in the same
call (`laser_ray.gd:155-161`), so the 0.2 s init frame runs *inside* the warn window rather than
before it. Time-to-lethal is therefore `warn_duration + ~0.56 s (laser_increase)`, not
`0.2 + warn + 0.56`. Measured: warn 0.0 → 697 ms, 0.5 → 1062 ms, 1.2 → 1766 ms, 3.0 → 3567 ms.

So **`warn_duration = 1.4` ⇒ ≈ 1.96 s to lethal**, which is the Danmakufu figure.
`active_duration = 2.0` matches the 120-frame spark. The `laser_increase` charge-up counts toward
the telegraph budget because a widening beam is exactly finding 1's "slowly building up the
width". Dissolve is a further **0.84 s** (7 frames × 0.12 s, `laser_ray.tscn:153-155`), giving a
measured full beam lifetime of ≈ 4.7 s at these values.
**Q2 — How fast should the sweep be?**
*Derived, not sourced — label this a judgement call.* No source gives degrees/second; finding 3
gives only "constant angular velocity", which is itself the useful part (no easing, no
acceleration — a constant rate is what makes a sweep predictable). The rate follows from our own
numbers: the player's top speed is **400 px/s** (`move_state.gd:21`, `max_move_speed`). Beam
tangential speed at radius `r` is `ω·r`. At the ~400 px the player will typically sit from the
station, **ω = 0.5 rad/s (≈ 29°/s)** puts the beam edge at 200 px/s — half the player's top
speed, so outrunning it sideways is comfortable and staying ahead of it is a decision rather
than a reflex. A full revolution takes 12.6 s; one 2.0 s active window sweeps ~57°, a readable
arc rather than a screen wipe.

**Q3 — One-hit kill, or chip damage?**
**Keep the one-hit kill.** `LaserRay._KILL_DAMAGE` is 9999 and is shared with the race hazards
and the level's own laser columns, so changing it is a shared-code change outside this sub-item.
Genre-wise this is normal — danmaku players usually have 1 HP and finding 6's companion rule is
that all damage is *avoidable*, not that it is small. Our player additionally has shield charges
that absorb a hit of any size (`player_base.gd:105-119`), so a shielded player survives one
beam. The fairness budget is spent on the telegraph (Q1), not on the damage number.

**Q4 — How many simultaneous beams?**
**Two, opposed.** Finding 6 says the player treats a rotating beam as a no-go region, so the
count is bounded by "the swept arc must not be the whole screen". Two beams 180° apart sweep the
full plane in half a revolution while leaving, at any instant, two large clear quadrants — the
gap the genre rule requires. Four beams at 90° halve those quadrants and, with a 2 s window at
ω = 0.5 rad/s, leave the player nowhere to stand that is not about to be swept. Finding 4's
"stay alert" is also better served by *sequencing* two beams through a fixed angle list
(finding 5) than by putting four on screen at once.
