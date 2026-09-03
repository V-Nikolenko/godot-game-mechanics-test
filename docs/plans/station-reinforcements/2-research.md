# Research — reinforcements during a shmup boss fight

Five findings, each fetched and read (two needed `scripts/fetch-page.sh` — `shmups.system11.org`
403s automated clients).

| # | Finding | Tradeoff | Typical values | Source |
|---|---|---|---|---|
| 1 | **Adds are the classic way a boss "overshadows itself".** The Flunky-Boss critique is consistent across writeups and player threads: minions "soak up damage and distract you from the boss's attacks"; because the fight is balanced *around* the minions, the boss itself has to be made weaker and less interesting; and **"constant spawns throughout the fight contribute majorly to minions overshadowing the boss"**, whereas bosses that summon only during specific phases do not. | Continuous drip = more pressure but the boss stops being the thing you are fighting. Phase-gated bursts keep the boss the subject, at the cost of stretches with no adds. | "only summon large groups during specific phases" | [TV Tropes — Flunky Boss](https://tvtropes.org/pmwiki/pmwiki.php/Main/FlunkyBoss) (via search summary; page itself would not fetch — see *Unreachable* below), corroborated by [Valdis Story thread](https://steamcommunity.com/app/252030/discussions/0/618460171323042751/) and [Remnant thread](https://steamcommunity.com/app/617290/discussions/0/1633040337766690116/) |
| 2 | **Popcorn is the right role for adds, and popcorn is a *layer* over a core, not a replacement for it.** "You can augment your core layer by throwing in a bunch of weak popcorn enemies… serving as little obstacles clustered on the path to the player's destination… The more the waves overlap the more chaotic the game can become as the shots of popcorns will block off parts of the screen." Also: "Enemies, especially popcorn enemies, should not have much more HP than is needed to fulfil their function." | Overlap is what creates flow — but it is also exactly what destroys readability next to a dense boss pattern. Overlap is a dial, not a free win. | popcorn = lowest HP tier | [Boghog's bullet hell shmup 101](https://shmups.wiki/library/Boghog%27s_bullet_hell_shmup_101) (fetched, §Level Design / Layered Design) |
| 3 | **The Toaplan pattern: spawn each enemy on the opposite side of the screen from the previous one**, to force movement and create rhythm. Screen is read as 5-7 lanes, and **"the edges of the screen don't have lanes to prevent awkward traps"** — "avoid putting enemies too close to the borders of the play area, it can create some nasty traps for the player." Separately: **"Spawning two or more higher HP enemies at the exact same time creates confusion… Spawning them one-by-one with slight delays creates an obvious route"** (a rule about *high-HP* enemies; popcorn pairs are fine simultaneous). | Strict alternation is legible and controllable, but predictable — it is memorisable, which is what the genre wants for a stage-1 boss. Border lanes add pressure but produce unfair traps. | 5-7 lanes; no lanes at the very edges | [Boghog's bullet hell shmup 101](https://shmups.wiki/library/Boghog%27s_bullet_hell_shmup_101) (fetched, §Level Design) |
| 4 | **Boss length and attack cadence.** "A stage 1 boss shouldn't exceed 40 to 50 seconds." The cardinal rule is *force the player to stay alert*, achieved by switching attacks frequently — DoDonPachi's first boss "us[es] one attack for no more than five to ten seconds". | A 5-10 s event cadence keeps the fight alert; going faster makes it unreadable, slower makes it "spinning your wheels". Adds are one more event competing for slots in that same budget. | stage-1 boss ≤ 40-50 s; attack switch every 5-10 s | [Giest118's Guide to Making Good Bullet Hell Bosses](https://shmups.system11.org/viewtopic.php?t=44816) (fetched via `fetch-page.sh`, direct = HTTP 403) |
| 5 | **Off-screen spawn margin is a measurable quantity, not a vibe.** "Define a 2d bounding box that you're going to spawn mobs into and place it above (or in your case to the right) your viewport **and high enough where the largest spawned mob is still not visible even if you spawn it at the nearest part of your bounding box**." Also, on spawning near the player: pick "the spawn point furthest away from the player… spawning enemies right beside the player is no fun and looks weird". | A bigger margin guarantees the pop-in is never seen, but adds dead flight time before the enemy is a threat, and lengthens the lifetime you must budget for. | margin ≥ half the largest sprite + the camera's maximum pan | [Unity Discussions — handling off-screen enemies in a SHMUP](https://discussions.unity.com/t/what-is-the-best-way-to-handle-off-screen-enemies-in-a-shmup/67069) (fetched) |

## What these turn into, for *this* codebase

- **F1 → reinforcements run in phase 1 only** (turrets alive) and stop on `armor_broken`. Phase 2
  is already the station's own show: `StationLaserPhase` beams every 6.5 s plus `StationGunnery`
  core rings every 2.0 s. Adding a third source there is precisely the "constant spawns overshadow
  the boss" failure, and it would also fight the 48-bullet pool for screen space.
- **F2 → the squads are popcorn**: `interceptor` (low-medium HP), `kamikaze_drone` (very low),
  `fighter` / `light_assault_ship` (60 HP). No new enemy types, per the EPIC constraint. No gunship —
  it is a 200 HP self-managed-AI enemy that would become a second boss. **Not `ram_ship` either**:
  review round 1 found `ram_ship.gd:19` narrows its HurtBox mask to 33, which excludes the player
  bullet's layer 64 (`bullet.tscn:44`), so it is not popcorn at all — it is unkillable by the
  primary weapon. See `3-plan.md`'s rejected alternative 5.
- **F3 → a fixed, cycling squad order that alternates sides**: left → right → bottom → top. Fixed,
  never `randf()` — the laser phase already established that random attack ordering cannot be
  balanced or tested. Side lanes at design y = 20 / 80 (i.e. the vertical middle), not hugging the
  top or bottom border. Two popcorn ships per squad spawn simultaneously; F3's "one-by-one" rule
  applies to high-HP enemies, which these are not.
- **F4 → first squad at 8 s, then every 10 s.** 8 s of boss-only opening (F1: adds at the very
  start steal the boss's introduction), then the top of the 5-10 s event band, so the squad is an
  event that punctuates the 1.8 s turret cadence rather than blurring into it. Over a phase 1 of
  ~25-35 s inside a 40-50 s stage-1 fight that is 2-3 squads, 4-6 ships.
- **F5 → concrete margins.** `ArenaCamera`: `SCREEN_W 1280`, `SCREEN_H 720`, `H_LIMIT 100`,
  `V_LIMIT 380`, `WORLD_SCALE 2.0`, and `global_position` pinned at (640, 360) with all panning
  done through `offset`. Largest reinforcement sprite is the **interceptor**: its `Sprite2D`
  (`interceptor.tscn:58-60`) carries **no `scale`**, so it renders at its texture size, 64x74 —
  half-extent **37**. (The `1.8` on `interceptor.tscn:63` belongs to the sibling `CollisionShape2D`
  over a radius-14 circle, i.e. the collider, not the sprite; review round 1 caught the misreading
  that put this figure at 67. The `light_assault_ship` sprite is 64x64 and the `kamikaze_drone`
  32x32, both smaller.)
  Horizontal: need > 640 + 100 + 37 = 777 world px from centre → **design x = ±440** (880 world,
  103 px of headroom; ±420 would also have cleared it — ±440 is the round number, not a minimum).
  Vertical: a strict F5 margin would need 360 + 380 + 37 = 777 world px too, but every spawn in the
  shipped game resolves against `cam.global_position` (the *fixed* centre) and not the panned view —
  deliberately, per `arena_camera.gd:8-12`. Matching that convention is worth more than the last
  380 px of margin, so the budget is 360 + 37 = **397** and
  **design y = ±290** (580 world, 183 px of headroom) and the residual is recorded as a
  project-wide pre-existing property, not something 4b fixes.

## Unreachable sources

- `tvtropes.org/pmwiki/pmwiki.php/Main/FlunkyBoss` — `fetch-page.sh` produced no output file
  (direct and reader proxy both failed). Finding 1 therefore rests on the search engine's
  extracted summary **plus** two player threads that were returned with it. It is used only for a
  qualitative design direction (phase-gate the adds), never for a number.
