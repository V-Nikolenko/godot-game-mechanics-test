# Beams — the Phase 8 enemy energy-weapon family

**Role:** a shared enemy laser weapon. A thin warning line appears on the exact path, then a beam hurts everything on that line except the
ships that fired it. It is a weapon component, not an enemy: an owner (a turret mount, later a drone pair, a fence, a hull) holds it and drives
its clock. Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.1–§2.3 (built in t2); decisions: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`
→ Phase 8.

`LaserRay` (`assault/scenes/hazards/laser_ray/`, level 1, the race and the station) and the station's `StationLaserPhase` are **not** part of this family
and are untouched: the ray is a 9999 one-hit kill on sprite timing with a `Timer` re-damage. Ph11 moves the station onto `EnemyBeam`.

## Files

```
enemy_beams/
├── BEAMS.md                ← this file
├── enemy_beam.gd           EnemyBeam extends Node2D (Kind BEAM / SWEEP / LANCE / TWIN, Phase OFF / TELEGRAPH / ACTIVE / FADE)
├── energy_hit_scan.gd      EnergyHitScan: candidates / is_exempt / hits_band / bounding_radius / deliver (static)
├── enemy_beam_scenes.gd    EnemyBeamScenes: scene_for / export_of / export_of_scene
├── beam.tscn               BEAM   (beam cannon)
├── sweep_beam.tscn         SWEEP  (the mount rotates it at sweep_rate over sweep_arc_deg)
└── lance.tscn              LANCE  (sniper lance: long telegraph, locked commit window, one hit)
```

Later tasks add `twin_beam.tscn` (TWIN, endpoints; with cover clipping, the strain flicker and laser-wall registration) and the Pulse Ring
(`energy_ring.gd` / `energy_ring.tscn`, `EnergyRing`; Ph7's `PulseRing` is a different, visual-only ring).

## The owner contract

- `setup(host, owner_group)` once, before the first `start()`: the **owner set** (never hit) is `host` and every node in `owner_group`.
- `start(telegraph_override := -1.0, active_override := -1.0)`: OFF / FADE → TELEGRAPH (ignored while TELEGRAPH or ACTIVE: a beam never re-aims
  mid-shot). Negative = the scene export; `active` 0 = held until `cancel()`. Clears the per-target re-hit table.
- `tick(delta)` on the owner's physics tick — **the only clock**: no `Timer`, no `create_timer`, no `_process`. `self_tick = true` makes
  `_physics_process` call it, for scene-placed props only.
- `cancel()`: TELEGRAPH → OFF at once (it never hurt), ACTIVE → FADE.
- Signals: `phase_changed(phase: int)` once per change, `target_hit(target: Node2D, damage: int)` per delivered hit.
- Queries: `phase()`, `is_lethal()`, `is_committed()` (the Lance's last `commit_seconds` of TELEGRAPH), `hit_segments()`, `hazard_info()` (null until
  the endpoint-beam task).
- An emitter beam points along its **local +X** from its own `global_position`. The owner rotates the beam's **parent**, never the beam. The beam
  owns no `StateLight`; the host sets its light from `phase_changed` / `is_committed()` (TELEGRAPH = CHARGING, commit = COMMIT, ACTIVE = ARMED).

## Exports (one scene per kind; every value authored in the `.tscn`)

| Export | `beam.tscn` | `sweep_beam.tscn` | `lance.tscn` |
|---|---|---|---|
| `telegraph_seconds` / `commit_seconds` | 0.9 / 0 | 0.9 / 0 | 1.0 / 0.5 |
| `active_seconds` / `fade_seconds` / `ignite_grace` | 1.2 / 0.15 / 0.1 | 2.0 / 0.15 / 0.1 | 0.2 / 0.1 / 0 |
| `length` / `tip_grace_px` | 700 / 24 | 400 / 24 | 1100 / 24 |
| `hit_half_width` / `draw_half_width` | 12 / 16 | 10 / 14 | 8 / 10 |
| `damage` / `rehit_interval` | 10 / 0.55 | 10 / 0.55 | 24 / inf (once per shot) |
| `telegraph_width` | 4 | 4 | 4 |
| `sweep_arc_deg` / `sweep_rate` | – | 100 / 0.8727 rad/s | – |
| `blocked_by_cover` / `registers_hazard` | true / false | true / false | true / false |

Tests and owners read these through `EnemyBeamScenes.export_of(kind, property, fallback)` (fallback: the script default), never as typed numbers.

## Rules every beam follows

- **Timeline:** TELEGRAPH (never lethal) → ACTIVE (lethal once `ignite_grace` has passed, and never while `set_strained(true)`) → FADE (never lethal)
  → OFF. Phase lengths are summed tick deltas with a 1e-6 tolerance (54 ticks of 1/60 s end a 0.9 s telegraph).
- **Geometry:** drawn from the emitter for `length`; the **hit** segment stops `tip_grace_px` short of the free tip. The hit band is
  `hit_half_width` either side; the drawn glow is `draw_half_width` (wider): a graze that looks safe is safe.
- **Who it hurts:** every node in `player`, `allies`, `enemies` and `asteroids` whose hurtbox **shape** meets the band (`Shape2D.collide`, exact for
  any shape, scale and rotation) — other enemies included — except the owner set. Enemy ordnance (rockets, mines) is never hit.
- **Tunnelling:** each lethal tick also tests the two triangles swept between the previous and the current hit segment, so a target the line
  crossed between two ticks is hit.
- **Damage is a direct emit** (`HurtBox.received_damage.emit`), like every beam in the project: it bypasses `EnemyShield` bubbles, `ArmorPlate`s
  and `HurtBox.accepted_damage_types` (so a beam cuts a big asteroid that only takes ROCKET from player fire, as `BeamBehavior` and `LaserRay`
  already do); a plated Ram refuses it in its own hull rule; the player's i-frames and shield charge apply. The shape test does not read
  `HurtBox.monitoring`, so the player's barrel-roll does not dodge a beam (it never dodged `LaserRay` either).
- **Re-hit:** at most one hit per target per `rehit_interval` (0.55 s on every held beam). It is strictly above the player's 0.5 s i-frames because
  Godot steps physics before idle: a re-hit on exactly 0.5 s lands before the i-frame `Timer` expires and is refused, so the player would feel
  1.0 s. The Lance's `inf` hits once per activation.
- **Scoring:** a kill by a beam is an ordinary kill (`was_killed`, `died`); there is no attribution.
- **Drawing:** `Telegraph` (`telegraph_width` px, ≥ 3; yellow, white while committed), `Glow` (red, `2 * draw_half_width`) and `Core` (white-hot,
  `hit_half_width`) are code-built `top_level` `Line2D`s in global space, not anti-aliased, no PNG; the glow and core ease in over `ignite_grace` and
  out over `fade_seconds`.

## Fairness rules (gate rows reading the scene exports and both player scenes)

`R` = 0.25 s reaction; `v_c` = the slower player's `cruise_speed()` (360); `r_p` = the larger player hurtbox's circumscribed radius (20.1 px, the ship).

- Static beams (BEAM, the SWEEP's start bearing): `telegraph_seconds ≥ R + (hit_half_width + r_p) / v_c` (0.9 ≥ 0.339).
- Sweep: `sweep_rate × length ≤ v_c` (349 ≤ 360 px/s): the tip never outruns the player.
- Lance: `commit_seconds ≥ 0.5` and `telegraph_seconds − commit_seconds ≥ R`.
- Every held beam: `rehit_interval > ` every player i-frame window. Every beam: `telegraph_width ≥ 3`.

A later difficulty tier (Ph16) must stay inside them.

## Tests

`tests/integration/test_enemy_beams.gd` — the timeline, cancel, re-hit cadence (exact, hand-ticked), telegraph width and colour, swept hit, tips,
±1 px width, the Bomber-rectangle exact-shape row, the export table, victims, the owner set, the plated Ram, shield bypass, ordnance, scoring, the
static `rehit_interval` row, the real-frame player cadence rows (4× clock) and the fairness rows, each with its synthetic boundary.
