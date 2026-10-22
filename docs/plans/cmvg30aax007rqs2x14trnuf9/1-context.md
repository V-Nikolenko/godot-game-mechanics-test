# Context — t10 wreck family (epic cmug23om70001m52wqfwclf3l, phase 6)

The design is the epic's approved plan, §2.8 (with "For every task", §2.17, §4.1, §4.4). This file records what the code
looks like today where §2.8 touches it; measured on `a1e94b2`.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/hazards/hazard_info.gd`, `hazards.gd` | `HazardInfo` (claims), static registry, `container(tree)`, `hurt_box_of` | The wreck and fragment register and expose an info; claims delegate to it |
| `global/hazards/hazard_field.gd` | `spawn_into` / `_attach` (untyped param) / `_enter_tree` transform | The exact deferred-attach pattern both new scripts copy |
| `assault/scenes/hazards/asteroid_base.gd`, `small_asteroid/` | Body + Health + HurtBox(512/96) + ContactHitBox(1024) scene; position-write drift | Scene layout precedent; group `asteroids` is a LOS blocker |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd` + `.tscn` | Round: HitBox 256 / mask 128; `_on_hit_box_area_entered` expires on any area | Mask gains 1024; expire filter on `stops_enemy_rounds()` |
| `tests/integration/test_enemy_rounds.gd:59` | Asserts every round's HitBox mask == `PLAYER_HURTBOX` | Must become `PLAYER_HURTBOX | HAZARD_CONTACT` (intended change) |
| `global/enemy_ai/line_of_sight.gd` | Ray on `ENVIRONMENT | HAZARD_CONTACT`, bodies only, opt-in `blocks_line_of_sight()` | A layer-1 body answering true blocks; an `Area2D` fragment never can |
| `assault/scenes/player/weapons/behaviors/beam_behavior.gd:59-76` | Ray mask `1 | 1024` bodies; damages groups `enemies`/`asteroids` only | Wreck blocks the beam and cannot be cut: document in HAZARD.md |
| `global/components/projectile_lifetime.gd` | `max_time` / `max_distance` / world rect, emits host `expired` | Assault wreck end (rect + 30 s cap); fragment `lifetime` |
| `global/enemy_ai/enemy_world.gd` | `arena(tree)` != null ⇔ Assault | Per-mode lifetime/drift selection |
| `assault/scenes/player/player_fighter.gd:72-117`, `states/move_state.gd:69-74` | Assault player moves in `_process` (move_and_slide + clamp y ≤ 1100); idle state never moves | The clamp-edge "held" row; an idle player is never depenetrated |
| `assault/scenes/projectiles/bullets/bullet.tscn` | Player bullet HitBox 64 / mask 513 | Stops on the wreck HurtBox (512); no armour answer → consumed |
| `assault/scenes/projectiles/enemy_rockets/*.tscn`, `enemy_rocket.gd:378` | Impact box 32 / mask 640; detonates unless `ArmorQuery.deflects` | Detonates on the wreck HurtBox (512) |
| `tests/integration/test_enemy_hurtbox_geometry.gd`, `test_contact_hitbox_geometry.gd` | Hand `ROSTER`s; body node named `CollisionShape2D`; contact box = first `HitBox` direct child | Add the six wreck/structure scenes |
| `tests/integration/test_entity_sprite_transparency.gd` | Sweeps `assault/scenes/{...,hazards,...}` | Covers the new scenes automatically |
| `tests/helpers/enemy_ai_harness.gd`, `test_level1_drone_exit.gd::_scale_clock` | Dual-mode harness; 8× clock | Test scaffolding |

## Measured geometry (runtime, `/tmp` probe)

- Every mover enemy root: `collision_layer = 1`, `collision_mask = 1` (defaults) → enemies are stopped by a layer-1 wreck
  body and are layer-1 hits for a LOS ray (already recast past). HurtBox == body size (sniper +0.15 px radius).
- Open Space player: body r 11.05, hurtbox r 5 × 2.2 = 11.0. Assault fighter: body r 5.1 × 2.7 = 13.77, hurtbox r 13.5.
  (The epic review's "hurtbox 5" ignored the node scale.) Gap at rest against a stationary wreck = slide margin 0.08 +
  0.05 / 0.27 px (CORRECTED in plan revision 2: a body actually rests touching, gap ≈ 0–0.007 px; harmlessness rests on hurtbox ≤ body) — the test is a
  real-physics row.
- Player body layer 4, mask 1; player HurtBox mask 1281 (includes 1024). Enemy HurtBox mask 1121 at runtime
  (`DefenseProfile`) — includes 1024.

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `HazardField.spawn_into/_attach/_enter_tree` | Deferred attach copied verbatim |
| `ProjectileLifetime` | Assault rect + cap, fragment lifetime |
| `HitEffect` (`global/components/hit_effect.gd`), `ExplosionEffect` | Hit flash, death pop (asteroid / turret precedent) |
| `CollisionLayers` constants | No magic numbers in code |
| `Hazards.container(tree)` | Runtime parent; nothing spawns without it |

## Conventions that constrain this

No `Timer`s, accumulated `delta`; no new physics bit; nothing in `global/` names `ArenaCamera`; a wreck is never in
`enemies`, never scored, never in the enemy container; never hand-type a `uid://`; each scene gets a `HAZARD.md`.
