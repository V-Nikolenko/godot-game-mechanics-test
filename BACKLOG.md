# BACKLOG

The autonomous agent reads this file top-down every 5 hours and takes the **topmost item it can
finish end to end**. This file is the steering wheel — vague items produce drifting work.

Reorder freely; the agent always starts from the top. Delete or tick items yourself — the agent
also ticks what it finishes and appends anything it discovers under *Discovered*.

Anything non-trivial goes through the **`feature-workflow`** skill: research → plan in
`docs/plans/` → independent subagent review → implement only after approval. So an item does not
need to specify *how* — the plan stage decides that, and you get to read it before the code lands.

## How to write an item

Three things, and only the first is mandatory:

1. **The player-facing outcome.** What should be different when someone plays the game? Write
   this, not the implementation. "Dashing should feel responsive when you tap it just after
   leaving a ledge" beats "add a coyote-time timer to `player.gd`".
2. **Where it lives**, if you know — module or file paths. Saves the agent a search and stops it
   guessing at the wrong module.
3. **What "done" looks like** — the observable condition you would check yourself.

Add **constraints** when you actually have them ("must not change existing wave timing",
"reuse the existing Overheat component"). Leave them out when you do not — an over-specified item
just locks in your first idea and wastes the research stage.

**Size it to one session.** If it needs more, say so and let the agent split it; it will add the
sub-items back here.

<details><summary>Good vs bad, same feature</summary>

> ❌ **Bad** — "Improve the dash."
> No outcome, no scope, no done condition. The agent will invent all three and probably build
> something you did not want.

> ❌ **Bad** — "In `player.gd` add `var coyote_timer := 0.15` and check it in `_physics_process`
> before allowing a dash, then update the state machine."
> Over-specified. You have made the design decisions from memory, skipped the research stage, and
> baked in a magic number. If your approach is wrong, the agent implements it wrong faithfully.

> ✅ **Good** — "Dashing off a ledge feels unresponsive: if you press dash a few frames after
> walking off, nothing happens and it reads as a dropped input. It should still dash. Affects the
> infiltration module's player controller. Done when a GUT test proves a dash input shortly after
> leaving ground still triggers, and normal mid-air dashing is unchanged."
> Outcome, location, done condition. The research stage will find the standard window, the plan
> will name the files, and the reviewer will check it against the existing state machine.

</details>

---

## Now

- [ ] **Bootstrap the test harness.** Install GUT into `addons/gut/`, create `tests/`, and write
      characterization tests for the eight autoloads and the `global/components/` set (Health,
      Hurtbox/Hitbox, Shield, Overheat, DamageReaction). Tests must pin down current behaviour,
      bugs included — no fixes this run. Done when `bash /agent/verify.sh` passes with a green
      suite. *(The agent does this automatically while `addons/gut/` is missing, ignoring
      everything below.)*

## Next

- [ ] **Fix the stale UID in `open_space/scenes/gui/hud.tscn:6`.** Its `ext_resource` for
      the pause menu declares `uid://bospm3nuos001`, but
      `global/ui/pause_menu/open_space_pause_menu.tscn` actually declares
      `uid://b10bam3tnq6vw`. Godot currently falls back to the text path and only warns, so
      nothing is broken — but the fallback disappears if that scene is ever moved. Fix the
      reference, then run the Godot MCP `update_project_uids` tool and check whether any
      other file has the same problem. Done when `godot --headless --import` is warning-free.

---

## EPIC — Level 1 space-station mini-boss

**Outcome:** Level 1 currently runs Deep Space → Asteroid Belt → Planet Approach → Cloud Descent.
Between the asteroid belt and the planet approach, the player should meet a **space station
mini-boss**: a bullet-hell encounter they cannot skip. Turrets first, then a rotating laser phase,
and only when the station is destroyed does the level continue to the planet.

**Reuse — do not rebuild these** (checked, they exist):

| Need | Already exists |
|---|---|
| "Cannot progress until boss dead" | `LevelSection.EndCondition.ENEMIES_CLEARED` (see `cloud_descent`, `level_1_director.gd:759`) |
| Telegraphed rotating lasers | `assault/scenes/hazards/laser_ray/laser_ray.tscn` — has `warn_duration`, `active_duration`, `loop`, `off_duration` |
| Per-turret destructibility | `global/components/health_component.gd` + `hurtbox_component.gd` + `hitbox_component.gd` |
| Damage feel / death | `damage_reaction.gd`, `hit_effect.gd`, `explosion_effect.gd`, `low_health_smoke.gd` |
| Reinforcement waves | `WaveManager` + `wave_builder.gd`; enemies in `assault/scenes/enemies/` (interceptor, kamikaze_drone, bomber, ram_ship, …) |
| Bullet-hell throughput | `global/components/bullet_pool.gd` — see `docs/BULLET_POOL.md` |

**Constraints (apply to every sub-item):**

- **Top-down, no perspective.** The station is viewed flat from directly above — no vanishing
  point, no angled faces. Turrets read as mounted on its surface.
- **Sprites come from PixelLab**, saved under `assault/assets/sprites/`. Station and turrets are
  separate sprites so turrets can be destroyed and swapped independently.
- **Scale:** the player fighter is 64×64. Target the station at roughly 4× that and turrets at
  about player size. **Do not hardcode a pre-multiplied pixel size** — this project authors in
  640×360 design space and scales by `ArenaCamera.WORLD_SCALE` (2.0). The plan must state exactly
  which space the sprite is authored in and where the scale is applied; getting this wrong makes
  the boss the wrong size on screen. Confirm PixelLab maximum output size during research.
- Reuse existing enemy scenes for reinforcements. Do not create new enemy types for this.

### Sub-items — do these in order, one per session

- [ ] **1. Station and turrets exist as a destructible entity.** Generate the station and turret
      sprites via PixelLab. Assemble the station scene with N turrets as child entities, each
      individually damageable. The station core takes no damage while any turret is alive.
      *Done when:* a GUT test destroys turrets one at a time and proves the core is invulnerable
      until the last turret dies, then becomes damageable.

- [ ] **2. The encounter blocks level progress.** Add a new `LevelSection` (suggested name
      `station_assault`) to `level_1_director.gd`, between `asteroid_belt` and `planet_approach`,
      using `ENEMIES_CLEARED`. Add the matching `phases/phase_station_assault.tres`.
      *Done when:* a headless test proves the section does not advance while the station lives,
      and advances to `planet_approach` when it dies.

- [ ] **3. Laser phase.** Once all turrets are destroyed, the station rotates and fires
      `LaserRay` beams at varying positions, forcing the player to keep moving. Beams must
      telegraph before they damage (`warn_duration`) — an instant-kill beam with no tell is
      unfair, and research should set the actual timing.
      *Done when:* a test proves the phase only starts after the last turret dies, and that a
      beam damages the player only during its active window, not its warning window.

- [ ] **4. Bullet hell + reinforcements.** During the fight, existing enemy ships fly in from the
      sides, top and bottom. Turrets and station fire bullet-hell patterns.
      *Done when:* reinforcement waves spawn from at least three screen edges, projectiles route
      through `bullet_pool`, and a headless run of the section produces no errors.

- [ ] **5. Destruction hands off to the planet approach.** Station death plays out and the level
      continues into `planet_approach` and the planet entry.
      *Done when:* a headless run of the full Level 1 section sequence completes end to end.

**Open questions for the plan stage** (research these, do not guess):
PixelLab maximum sprite dimensions; how many turrets makes the first phase interesting rather
than tedious; standard telegraph durations for sweeping-laser boss attacks in shmups.

---

## Discovered

<!-- The agent appends suspected bugs and follow-ups it found but did not act on. Triage these. -->
