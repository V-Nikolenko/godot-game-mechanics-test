# Level 1 space-station mini-boss — PRD

**Epic id:** `station-mini-boss` (the join key the web UI reads) · **Status:** done ·
**Ran:** 2026-09-01 → 2026-09-03, six unattended cycles, one sub-item per cycle.

This epic was written by the user directly into `BACKLOG.md` at `613ad48`, before the Ideas tab
existed — it is not a drafted idea, so there is no rawer original text to quote. The wording below
is the user's, verbatim from that commit, with the sub-item bodies as they stood when each cycle
picked them up.

---

## The ask

> ## EPIC — Level 1 space-station mini-boss
>
> **Outcome:** Level 1 currently runs Deep Space → Asteroid Belt → Planet Approach → Cloud Descent.
> Between the asteroid belt and the planet approach, the player should meet a **space station
> mini-boss**: a bullet-hell encounter they cannot skip. Turrets first, then a rotating laser phase,
> and only when the station is destroyed does the level continue to the planet.

### Reuse — do not rebuild these (the user's own table, checked at authoring time)

| Need | Already exists |
|---|---|
| "Cannot progress until boss dead" | `LevelSection.EndCondition.ENEMIES_CLEARED` (see `cloud_descent`) |
| Telegraphed rotating lasers | `assault/scenes/hazards/laser_ray/laser_ray.tscn` — has `warn_duration`, `active_duration`, `loop`, `off_duration` |
| Per-turret destructibility | `global/components/health_component.gd` + `hurtbox_component.gd` + `hitbox_component.gd` |
| Damage feel / death | `damage_reaction.gd`, `hit_effect.gd`, `explosion_effect.gd`, `low_health_smoke.gd` |
| Reinforcement waves | `WaveManager` + `wave_builder.gd`; enemies in `assault/scenes/enemies/` |
| Bullet-hell throughput | `global/components/bullet_pool.gd` — see `docs/BULLET_POOL.md` |

Every row held. Nothing in that table was rebuilt, and the reuse went further than the table
asked: the only genuinely new *shared* code in the whole epic is one resource,
`global/resources/attack/radial_attack_pattern.gd`, added alongside the three concrete patterns (`AimedAttackPattern`, `ForwardAttackPattern`, `GatlingAttackPattern`) that
already existed. Three additive extensions to shared components —
`LaserRay.hit_mask_override`, `BulletPool.cancel_active()`, `ExplosionEffect.explode(at)` — were
written so their default behaviour is bit-identical to before.

### The five sub-items, as asked

1. **Station and turrets exist as a destructible entity.** Generate the station and turret sprites
   via PixelLab. Assemble the station scene with N turrets as child entities, each individually
   damageable. The station core takes no damage while any turret is alive. *Done when:* a GUT test
   destroys turrets one at a time and proves the core is invulnerable until the last turret dies,
   then becomes damageable.
2. **The encounter blocks level progress.** Add a new `LevelSection` (suggested name
   `station_assault`) to `level_1_director.gd`, between `asteroid_belt` and `planet_approach`,
   using `ENEMIES_CLEARED`. Add the matching `phases/phase_station_assault.tres`. *Done when:* a
   headless test proves the section does not advance while the station lives, and advances to
   `planet_approach` when it dies.
3. **Laser phase.** Once all turrets are destroyed, the station rotates and fires `LaserRay` beams
   at varying positions, forcing the player to keep moving. Beams must telegraph before they
   damage (`warn_duration`) — an instant-kill beam with no tell is unfair, and research should set
   the actual timing. *Done when:* a test proves the phase only starts after the last turret dies,
   and that a beam damages the player only during its active window, not its warning window.
4. **Bullet hell + reinforcements.** During the fight, existing enemy ships fly in from the sides,
   top and bottom. Turrets and station fire bullet-hell patterns. *Done when:* reinforcement waves
   spawn from at least three screen edges, projectiles route through `bullet_pool`, and a headless
   run of the section produces no errors.
5. **Destruction hands off to the planet approach.** Station death plays out and the level
   continues into `planet_approach` and the planet entry. *Done when:* a headless run of the full
   Level 1 section sequence completes end to end.

**Clarified afterwards:** nothing. No user input arrived during the epic — all six cycles ran
unattended. Every judgement call is recorded in the plan directories and in *Open questions* below.

---

## Player-facing goal

Level 1 stops being a continuous scroll and acquires a wall the player has to knock down.

- **You meet a fortress, not a ship.** It sits near the top of the arena and does not move. Your
  shots spark off the hull and do nothing at all — no HP bar moves, no number appears. That teaches
  the rule with zero UI: *kill the guns first*.
- **Phase 1 is a target-priority decision under fire.** Four turrets, each with its own HP, each
  firing an aimed 3-bullet fan at you. Every gun you destroy visibly quietens the station — 6.7
  bullets/second at full strength down to 1.7 with one gun left — so shooting the right thing is
  its own reward. Meanwhile squads of ordinary enemy ships cross in from all four screen edges, and
  ignoring them to focus the boss is a legitimate choice.
- **Stripping the armour is not a reward, it wakes the thing up.** The moment the last turret dies
  the hull starts turning, sweeping telegraphed beams around itself and throwing precessing rings
  of bullets out of the exposed core. The fight flips from "aim carefully" to "keep moving", and
  the reinforcements stop because the boss no longer needs help.
- **Every lethal thing tells you first.** ~1.9–2.0 s of visible warning line before a beam is
  lethal, roughly six times the human reaction floor. Nothing in the encounter kills without a tell.
- **The boss dies like a boss.** Seven explosions roll across the 256 px hull, the spin decays, the
  hull darkens, one big central blast, and then the wreck is gone and the level moves on to the
  planet approach — which cannot happen a moment earlier, because the section is gated on the
  station being dead.
- **The fight is over in 30–60 s.** Genre sizing for a stage-1 mini-boss; the 180 s section timeout
  is a safety net, not a pacing device.

---

## Scope

### In scope, and delivered

- One new enemy family under `assault/scenes/enemies/space_station/` — the hull, four turrets, and
  five behaviour nodes (laser phase, gunnery, reinforcements, death sequence, plus a bullet pool).
- Three PixelLab sprites: `station_core.png` (256×256), `station_turret.png` and
  `station_turret_destroyed.png` (64×64).
- One new `LevelSection` in Level 1 (`station_assault`, third of five) plus its background phase.
- The additive shared-code extensions listed above, and `LevelSection.enemies_cleared_timeout`.

### Explicitly out of scope, and not built

- **New enemy types for the reinforcements.** The user's constraint; the squads are the shipped
  `interceptor`, `kamikaze_drone` and `fighter`.
- **The "WARNING! A HUGE BATTLESHIP IS APPROACHING" arrival beat.** Sub-item 2's research found it
  is the genre standard (Darius 1987 onward) and its plan *identified* the hook, deliberately
  without building it — scope creep at the time. It is still not built: nothing in `EventBus` or
  `LevelDirector` announces a boss. This is the largest missing piece of presentation.
- **Hitstop / `Engine.time_scale` on the death blow.** Two sources in sub-item 5's research asked
  for it. Declined for a concrete reason, not for time: `LevelDirector`'s own progression runs on
  `get_tree().create_timer()`, as do every gunnery and laser timer, so a global time scale would
  slow the level's state machine along with the spectacle.
- **Escalating the surviving turrets' fire rate as their siblings die.** The Gradius pattern, found
  in research for sub-items 1 and 4a, rejected on purpose: cancelling out the 4→3→2→1 quietening
  would delete the feedback loop the armour rule exists to teach.
- **Station balance beyond first-pass values.** Nobody has played this.

### Where the epic was split, and why

- **Sub-item 4 was split into 4a and 4b** on 2026-09-02, during the laser-phase cycle. As written
  it bundled two independent systems — the station's own fire, and reinforcement waves — each about
  one session of work with its own research question. 4a is the half that changes phase 1 from
  passive to a fight, so it went first. The backlog carries them as separate tasks; both are done.
- **Sub-item 3 took two cycles**, because the first ended at a blocked review with no code (see
  `REPORT.md` → *Decisions and course changes*).

---

## Constraints

The user's four, plus the two the project imposes:

1. **Top-down, no perspective.** The station is viewed flat from directly above — no vanishing
   point, no angled faces; turrets read as mounted on its surface. This bit twice: both turret
   sprites shipped as 3/4 views and had to be regenerated (`c60742b`). Root cause was the *tool*,
   not the prompt — `create_image_pixflux`'s `view` parameter defaults to unset and is documented
   as "weakly guiding". The fix, and the reason the `pixel-art-generation` skill now mandates
   explicit parameters, is recorded in the station's `ENEMY.md` → *Sprite provenance*.
2. **Sprites come from PixelLab**, saved under `assault/assets/sprites/`, with the station and
   turrets as separate sprites so turrets can be destroyed and swapped independently. Held —
   `station_turret_destroyed.png` is a `create_object_state` derivative of the intact turret.
3. **Scale: station ≈ 4× the 64×64 player, turrets ≈ player size, and do not hardcode a
   pre-multiplied pixel size.** Resolved by stating the rule explicitly in `ENEMY.md`: sprites and
   in-scene turret offsets are **final on-screen pixels** at `scale = 1`; `ArenaCamera.WORLD_SCALE`
   (2.0) applies only to *authored spawn offsets* and `EnemyPathMover` paths. So the hull is
   256×256 literal, while the spawn `at(0, -90)` is a design-unit offset and *is* doubled.
4. **Reuse existing enemy scenes for reinforcements.** Held.
5. **Composition over inheritance** (project convention). `SpaceStation extends BaseEnemy` and owns
   nothing but lifetime; the laser phase, gunnery, reinforcements and death sequence are four
   sibling `Node`s under the hull, each with a single job. `space_station.gd` gained *no* accessor
   for 4b at all.
6. **Config-driven stats** (project convention). 21 of its own exports on `SpaceStationConfig`, plus the four it inherits from `ShipConfig`; the `.tres`
   wins over the scene's `Health` node.

---

## Open questions at the time, and how each was resolved

The user named three at the top of the epic. All three were answered by research, not guessed.

| Question | Resolution |
|---|---|
| **PixelLab maximum sprite dimensions?** | Answered from the tool schemas, not the web: `create_image_pixflux` takes 16–400 px per side at 1 generation; `create_image_pro` reaches 512×512 but costs 20–40. A 256 px hull and 64 px turrets fit the cheap tool, so no allowance was spent on `_pro`. |
| **How many turrets makes phase 1 interesting rather than tedious?** | **Four.** Shipped cores-and-turrets bosses run 1–4 guarded cores (Gradius Big Core line) and **6 is already cited as a pain point** (Star Fox's Great Commander "eventually forc[es] players to risk collision damage to hit the last turret"). Four sits at the top of the shipped range, below the cited failure, and places symmetrically on a square top-down hull — which matters because placement is hand-authored. |
| **Standard telegraph duration for a sweeping-laser boss attack?** | **~2.0 s from first warning pixel to lethal.** Danmakufu's delay-laser tutorial telegraphs a screen-covering beam 120 frames (2.0 s) ahead; the human reaction floor for a simple visual cue is 200–300 ms and is explicitly *not* the target. Shipped as `laser_warn_duration = 1.4`, which measures 1.9–2.0 s to lethal once `LaserRay`'s own 0.56 s charge-up is counted. |

Four more surfaced during the epic and were resolved the same way:

| Question | Resolution |
|---|---|
| **Invulnerable core, or unhittable core?** | **Invulnerable but hittable.** Gradius's shield walls physically *stop* the shot; a shot sailing through the core reads to a player as a bug. The core's `HurtBox` stays live and `_on_received_damage` rejects the damage — which is also the only correct choice technically, because `plasma_nova_module.gd` and `beam_behavior.gd` both emit `received_damage` directly and would leak straight past a disabled hurtbox. |
| **Where does a stationary mini-boss sit on screen?** | **No prescriptive answer exists** — this is stated plainly in sub-item 2's research rather than dressed up. Derived from the project's own geometry instead: `at(0, -90)` → world (640, 180), hull spanning world y 52–308, leaving ~412 px of play space below it. |
| **`randf()` for "beams at varying positions"?** | **No — a fixed angle list.** "Don't decide attack orders based on randomness" is an explicit rule from a bullet-hell developer, whose failure case is a boss that a player reports as always using its hardest attack. Random ordering is also untestable. Every attack in this boss is deterministic; four tests assert it. |
| **How long should a mini-boss death take?** | **≈1.8 s, 7 blasts** — labelled a judgement call in the research, because no source gives a number. Long enough to read as a chain, short enough not to be resented on a fifth retry. |

---

## Links

- `REPORT.md` — what shipped, how it was verified, what changed course, known gaps.
- `SOURCES.md` — every external source, what it contributed, and the ones that could not be read.
- Plan directories: [`station-mini-boss-destructible`](../../plans/station-mini-boss-destructible/),
  [`station-assault-section`](../../plans/station-assault-section/),
  [`station-laser-phase`](../../plans/station-laser-phase/),
  [`station-bullet-hell`](../../plans/station-bullet-hell/),
  [`station-reinforcements`](../../plans/station-reinforcements/),
  [`station-death-handoff`](../../plans/station-death-handoff/).
- Entity doc: [`assault/scenes/enemies/space_station/ENEMY.md`](../../../assault/scenes/enemies/space_station/ENEMY.md).
