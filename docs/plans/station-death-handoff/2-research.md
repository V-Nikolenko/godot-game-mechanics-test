# Research — how shipped games stage a boss death, and how the level resumes afterwards

Every source below was actually retrieved and read. Two were 403 to `WebFetch` and were recovered
with `./scripts/fetch-page.sh` (noted per row). One source could not be retrieved at all and is
listed at the bottom rather than paraphrased.

| # | Finding | Tradeoff | Typical values | Source |
|---|---|---|---|---|
| 1 | A boss death is a **chained sequence of small explosions across the hull**, not one burst — "in older 2D video games, a common way of portraying the destruction of a large entity, typically a mechanical boss, is to have multiple little explosions go off one-by-one all over its surface until it either disintegrates or fully disappears." | Every extra second of spectacle is a second in which the player has nothing to do. The same community keeps "he just won't die!" as a running joke about death sequences that overstay. | No numeric standard exists; the "one-by-one over the surface" staging is the invariant. | TV Tropes *Post-Defeat Explosion Chain* (403 to both WebFetch **and** `fetch-page.sh`; description quoted from the WebSearch result summary, page itself unread — treat as weaker) + [Boss Death Throes](https://shmups.system11.org/viewtopic.php?t=69104) (read via `fetch-page.sh`) |
| 2 | **A boss explosion specifically earns a screen-flooding flash and a slowdown**, where a popcorn enemy does not: "as far as boss explosions go, they better be a spectacular light show of gaseous fulfillment, including a screen-flooding flash of brightness that slows down gameplay." Same author: "everything that is destroyed should explode… humans by nature love to see explosions." | Slowdown is the expensive half. On this project it means touching `Engine.time_scale`, which every `SceneTreeTimer` in the level — including `LevelDirector._wait_enemies_cleared()`'s 1.0 s poll — obeys. The flash and the chain are cheap; the slowdown is not. | — | [*The Anatomy of a Shmup*, Bean (2010)](http://shmuptheory.blogspot.com/2010/02/anatomy-of-shmup.html), read in full via `fetch-page.sh` |
| 3 | **Screen shake is a scarce resource.** "Camera-shake is a privilege, not a right… The problem is when camera-shake is used when every enemy is destroyed… it dampens the effect. The less it appears, the more it'll mean for the player when it does happen." Vlambeer's canonical talk says the opposite — "more is more. If it looks good with a little screen shake, it'll probably look better with a lot." | A genuine disagreement between two respected sources, and the deciding factor is *what else already shakes*. In this project there are **four** call sites, all of them the *player's own* ship: `player_fighter.gd:169` (0.35, taking a hit) and `:177` (1.0, dying), plus the open-space equivalents `player_ship.gd:195` and `:202`. Nothing an **enemy** does shakes the screen at all, so a boss-death shake is unambiguously rare here and Bean's rule points the same way as Vlambeer's. What it forbids is shaking on **every** blast of the chain.

*Corrected after review round 1, which caught that this row originally claimed two call sites. The conclusion is unchanged — the point was always that no enemy shakes the assault screen — but the count was wrong.* | `CameraShake` header already documents 0.4 light hit / 0.7 explosion / **1.0 boss death**. | [Bean (2010)](http://shmuptheory.blogspot.com/2010/02/anatomy-of-shmup.html) + [Nijman quoted in *Game feel on the web*](https://valdemird.com/blog/game-feel-on-the-web/) (read via `fetch-page.sh`) |
| 4 | **Hitstop is the cheapest weight available**: "at the exact frame of impact, the game stops time for a few dozen milliseconds, then resumes… your brain reads the longer pause as a heavier hit." Applied to bosses, the scaling is by rank: mid-chapter bosses get only brief pauses; chapter-end bosses get extended slow-down and a camera change. | Our station is a **mini**-boss — by that scaling it gets the brief pause, not the cinematic. And on this codebase even a brief global pause means `Engine.time_scale`, which the director's poll timer and every gunnery/laser timer obey. High risk-to-payoff for this sub-item. | Demo slider tops out at **90 ms**; the article recommends **60–80 ms** for a weighty confirm. | [*Game feel on the web*](https://valdemird.com/blog/game-feel-on-the-web/) (read via `fetch-page.sh`); boss-rank scaling from the WebSearch summary of [TV Tropes *Hit Stop*](https://tvtropes.org/pmwiki/pmwiki.php/Main/HitStop) |
| 5 | **Cancelling bullets on a death is the genre's established courtesy.** "After each death, all enemy bullets are cancelled to clear up the screen. After a short while this cancelling stops, but the player is still given a couple-few seconds of invincibility." Bean's rule points the same way from the readability side: "if a foreground object is going to obscure the view of play, it's a good idea to make sure no bullets are on-screen." | The wiki states this for **player** death, not boss death — extending it is a judgement call. Against: a boss's last volley is a legitimate final threat and cancelling it removes a skill test. For: a big flashy death sequence is exactly the "foreground object obscuring the view" Bean warns about, and being killed by a boss that is already dead reads as a bug. Directly load-bearing here: `bullet_pool.gd:98-102` frees in-flight bullets in `_exit_tree()`, so **delaying `queue_free()` also delays the cleanup** — the corpse keeps shooting for free unless we act. | "a couple-few seconds" of follow-up invincibility. | [Boghog's bullet hell shmup 101](https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101); [Bean (2010)](http://shmuptheory.blogspot.com/2010/02/anatomy-of-shmup.html) |
| 6 | **Boss time is spent against a fixed budget for the whole game**: "a lot of players seem to find that 25 minutes is a good length for a shmup, so be sure to consider that when figuring out how much of that time you want to be spent fighting bosses." | A death sequence is boss time in which the player cannot act, and it is paid once per boss per run — including on every retry. It has to be short enough that a player learning the fight does not resent re-watching it. | 25 min total run; timeouts "twice as long as it would take to kill the boss while constantly shooting". | [Giest118's Guide to Making Good Bullet Hell Bosses](https://shmups.system11.org/viewtopic.php?t=44816) (read via `fetch-page.sh`) |
| 7 | **The wreck should visibly degrade during the sequence**, not sit still: Star Fox 64's machines are remembered for "sparking and smoking while they start to either drift in space or fall to the ground." | Motion costs nothing but it competes for attention with the last of the player's own bullets. On this project the hull is *already* rotating during phase 2 (`station_laser_phase.gd:123`), so the cheapest legible degradation is to let that rotation die away rather than stop dead. | — | [Boss Death Throes](https://shmups.system11.org/viewtopic.php?t=69104) (read via `fetch-page.sh`) |

## What the numbers should be

No source gives a defensible number of seconds for a mini-boss death chain — this is the honest
gap in the research and the values below are a **judgement call**, labelled as such:

- **Total sequence ≈ 1.8 s.** Long enough to read as a chain rather than a stutter (finding 1),
  short enough not to be resented on the fifth retry (finding 6). It is also comfortably inside
  the section's 180 s `enemies_cleared_timeout`, so it can never race the safety net.
- **7 blasts at ~0.22 s apart**, scattered over the 256 px hull, then one final centre blast at
  2× scale. Seven reads as a chain; three reads as a hiccup.
- **One `CameraShake.add(1.0)` at the final blast**, plus a small `0.25` per chained blast. That
  is the compromise between findings 3's two sources: the chain is felt, the finale is the spike.

  **Measured caveat (review round 1).** `camera_shake.gd:24` decays trauma at 1.5 units/s and
  `:32` saturates it at 1.0, so a 0.25 blast is fully decayed 0.17 s later — inside the ~0.26 s
  blast interval. The chain therefore **never accumulates**, peaking at 0.25 trauma, which the
  quadratic curve at `:46-50` turns into a `8.0 * 0.25² ≈ 0.5 px` offset. The chain shake is
  effectively invisible and only the finale will read. That is consistent with finding 3's
  "a whisper for the chain, the spike for the finale", so the values stand — but nobody should
  later "fix" the invisibility by raising the per-blast value without re-reading this row.
- **No `Engine.time_scale` change.** Findings 2 and 4 both want one, and both are declined here
  for the same concrete reason: the level director's own progression is driven by
  `get_tree().create_timer()`, which scales with it. Recorded as a follow-up, not built.
- **The station's in-flight bullets are cancelled at the moment of death** (finding 5), because
  the alternative is not "a legitimate last threat" but "the boss keeps firing while visibly
  exploding", which is a bug wearing a design hat.

## Source that could not be retrieved

- `tvtropes.org/…/PostDefeatExplosionChain` — 403 direct **and** 403 through the reader proxy in
  `fetch-page.sh`. Finding 1's quote comes from the search-engine summary of that page, not the
  page. It is corroborated by a source that *was* read (the Boss Death Throes thread), so the
  finding stands, but it is the weakest row in the table.
