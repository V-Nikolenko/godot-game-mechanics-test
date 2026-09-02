# Research — bullet-hell fire for a cores-and-turrets mini-boss

Five findings, each with the tradeoff it implies for *this* boss. Sources were read in full;
`shmups.system11.org` 403s `WebFetch` and was recovered with `./scripts/fetch-page.sh` through the
reader proxy, as the skill requires.

| # | Finding | Tradeoff | Typical values | Source |
|---|---|---|---|---|
| 1 | **Aimed and static patterns do different jobs and are meant to be layered.** Aimed patterns "apply pressure while allowing conscious manipulation by the player"; static ones "are good for creating obstacles". The standard boss construction is a static pattern that constrains space *plus* an aimed component that forces movement. Giest adds the corollary: an aimed component is also the cheap way to **guarantee no safe spot**, because a static pattern alone can always be stood still inside. | Aimed-only reads as pressure with no shape and is trivially walked away from at range; static-only is memorisable and safe-spottable. | — | [Sparen A2](https://sparen.github.io/ph3tutorials/ddsga2.html), [Boghog 101](https://shmups.wiki/library/Boghog%27s_bullet_hell_shmup_101), [Giest118](https://shmups.system11.org/viewtopic.php?t=44816) |
| 2 | **Chunk bullets; single strays read as unfair.** "Chunking patterns is vital for visibility… group bullets up into lines and other clear patterns, single stray bullets are hard to read and can often feel unfair." | A fan of 3 on a long interval is *more* readable than 1 bullet on a short interval at the same bullets/second, but it spikes instantaneous density, so the interval has to grow with the chunk. | — | [Boghog 101](https://shmups.wiki/library/Boghog%27s_bullet_hell_shmup_101) |
| 3 | **Bullets are meant to be slower than the player.** The genre benchmark is that the player outruns the bullets — roughly **70–90 % of bullets in Touhou are slower than the player ship**. Slow bullets are what make multiple simultaneous trajectories legible instead of a reflex lottery. | Slow bullets linger, so on-screen count climbs and pool size must follow; too slow and the player simply flies away from the whole attack. | 70–90 % of bullets slower than the player. Here the player tops out at **400 px/s** (`move_state.gd:21`) and shipped enemy bullets run **220–260 px/s** (interceptor 220, gunship 260) = 55–65 % of player speed. | [ResetEra summary of the Touhou benchmark](https://www.resetera.com/threads/bullet-hell-games-how-do-people-pay-attention-to-and-dodge-all-bullets.852198/), [Boghog 101](https://shmups.wiki/library/Boghog%27s_bullet_hell_shmup_101) |
| 4 | **Rings: ≥3 bullets, spacing 360/n, and the per-ring rotation must NOT divide evenly into that spacing.** "You typically need at least three bullets per ring." For a spiral, "every ring, the angle of the ring changes by a fixed amount", and Sparen explicitly adjusts that amount "so that the angle does not divide nicely into 360 degrees" — otherwise successive rings re-tread the same radial lanes and leave permanent **blind spots** (i.e. safe lanes). A demo uses 1.5°/ring. Giest's independent version of the same idea: keep density constant per wave and vary the *trajectory* by less than the bullet spacing. | A step that divides evenly is easy to reason about and produces a permanent safe lane; a step that does not is slightly harder to predict and is the one that actually covers the plane. Very small steps (1.5°) suit rings every 2 frames; a boss firing every ~2 s needs a much larger step or the precession is invisible. | ≥3 bullets/ring; spacing = 360/n; step chosen not to divide the spacing. | [Sparen A3](https://sparen.github.io/ph3tutorials/ddsga3.html), [Giest118](https://shmups.system11.org/viewtopic.php?t=44816) |
| 5 | **A stage-1 boss should be over in 40–50 s, and attacks should change every 5–10 s.** "A stage 1 boss shouldn't exceed 40 to 50 seconds." Cave bosses use "one attack for no more than five to ten seconds". Giest also names random *attack ordering* as an outright mistake ("Don't decide attack orders based on randomness") because it makes difficulty non-reproducible per player. | Frequent attack switching is the pacing tool, but every extra attack is code and test surface; a two-phase boss gets the switch for free from its phase change and does not need a third attack to feel alive. | Boss ≤ 40–50 s; attack switch every 5–10 s. Existing fight sizing in `_build_station_assault()` already targets 30–60 s. | [Giest118](https://shmups.system11.org/viewtopic.php?t=44816) |

### Also noted, and it shaped the ring parameters

Sparen A2, on rings: *"by definition, most of the bullets in a ring will never come near the
player."* A full ring from a station pinned near the top of the arena spends roughly half its
bullets flying away. The alternative — a downward arc — doubles the pressure per bullet but reads
as a nozzle rather than a fortress and swings off-screen once the hull starts rotating. Decided in
favour of the full ring (see `3-plan.md`, *Alternatives rejected*) with the tradeoff recorded here
rather than hidden.

Sparen A4 refuses to give a bullet-count threshold and says so plainly: *"Fewer Bullets != Lower
Difficulty"* — structure, timing and positioning dominate raw count. So the density numbers in the
plan are derived from **this game's** measured constants (player 400 px/s, arena bounds in
`enemy_bullet.gd`, shipped enemy bullet speeds), not from an external figure. That is labelled a
judgement call in the plan.

### Answers to the four open questions from `1-context.md`

1. **Turret fire rate / speed.** Chunk into a 3-bullet aimed fan (finding 2) on a long interval,
   bullets at ~60 % of player speed to sit inside the shipped 220–260 px/s band and the 70–90 %
   benchmark (finding 3).
2. **Ring shape.** Full ring, ≥3 bullets, evenly spaced, precessing by a step that does not divide
   the spacing (finding 4).
3. **Aimed vs fixed split.** Turrets aim (finding 1: pressure, and no safe spot in phase 1); the
   core's ring is fixed-angle (obstacle) and the *already shipped* sweeping lasers are the second
   static layer. Phase 2 therefore has no aimed component — acceptable only because the hull
   rotates, the ring precesses and the beams sweep, so no position is safe over time. Recorded as a
   risk in the plan.
4. **Escalation as turrets die.** No. Finding 5 says a stage-1 boss ends in 40–50 s and gets its
   variety from switching attacks; this boss switches attacks at the phase change. The 4→3→2→1 gun
   decay is the *reward* for the player's shooting and is the reason to shoot the turrets at all —
   cancelling it out by speeding up the survivors would delete the feedback loop that
   sub-item 1 built the whole armour rule to teach.
