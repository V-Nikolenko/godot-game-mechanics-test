# Enemy rockets: Dumb and Pursuit (epic t5)

The design is the epic's approved plan (`docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.6, §2.7, §4.1, §4.3). This
file pins only the build choices that plan leaves open, the build order, and the test layout. Nothing below changes
a name, layer, number or rule of the epic plan.

## Problem

There is no enemy rocket. The epic's Missile Corvette (t7/t8) needs one family that is dodgeable (a visible straight
boost, mild lead steering for a finite window, then a frozen heading), shootable (a player bullet or missile kills it
with no blast), harmful to the player only through its blast, and harmful to enemies, ordnance, Ram plates and
asteroids through its impact. It must never hit the ship that fired it and must never be overrun by it.

## Design

### Files

| File | Content |
|---|---|
| `assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd` | `class_name EnemyRocket extends Area2D`, the whole §2.6 contract and both guidance kinds |
| `assault/scenes/projectiles/enemy_rockets/dumb_rocket.tscn` | DUMB, exports from the §2.6 table |
| `assault/scenes/projectiles/enemy_rockets/pursuit_rocket.tscn` | PURSUIT, exports from the §2.6 table |
| `assault/scenes/projectiles/enemy_rockets/enemy_rocket_scenes.gd` | `class_name EnemyRocketScenes`: `scene_for(kind)`, `pool_size_for(kind, cfg)` |
| `tests/helpers/rocket_launcher_fixture.gd` | the fixture launcher (§2.7) |
| `tests/integration/test_enemy_rockets.gd` | the §2.7 rows |
| `tests/integration/test_enemy_bullet_lifetime.gd` | + DUMB and PURSUIT lifetime rows (+ a boundary row) |

Scenes reference scripts by `path` only (no `uid=`; Godot mints the `.gd.uid` sidecar on import; never hand-typed).

### Scene shape (both kinds)

```
DumbRocket / PursuitRocket (Area2D, enemy_rocket.gd; layer 0, mask 0)
├── HitBox (HitBox)  layer 32, mask 640, damage_type ROCKET, damage = impact_damage, monitoring/monitorable false
│   └── CollisionShape2D (circle r = body_radius)
├── HurtBox (HurtBox) layer 512, mask 96      # received_damage NOT connected
│   └── CollisionShape2D (circle r = body_radius + 2)
├── ProjectileLifetime  max_time / max_distance per the table, use_world_rect true
├── RocketTrail         (global/components/rocket_trail.gd)
└── Pop (ExplosionEffect)  small burst for detonation / defuse / fizzle
```

The placeholder look is `_draw()` (nose-up body along local −Y, `body_color` export), as the plan says; t9 adds the
`Sprite2D` and drops the placeholder. No texture in t5, so the sprite-transparency sweep sees nothing new. Each
instance duplicates its two circle shapes in `_ready()` and sizes them from `body_radius` (so a Ph16 export change
reaches the shape; the ordnance precedent for per-instance shapes).

### Script

- **Exports** (the §2.6 list): `kind`, `launch_speed`, `cruise_speed`, `boost_seconds`, `accel`, `turn_rate`,
  `guidance_seconds`, `lead_max`, `impact_damage`, `blast_radius`, `blast_damage`, `blast_frames` (3), `arm_clearance`
  (8), `body_radius`, `max_time`, `max_distance`, plus look-only `body_color`. `max_time` / `max_distance` are the rocket's
  numbers and are pushed into the `ProjectileLifetime` child in `_ready()` and `reset()` (one source of truth: the
  rocket's exports; the child's authored values equal them in the scene).
- **`_RESET_PROPS`** = every export except `kind` and `body_color`, captured in `_ready()`; `reset()` restores them and
  clears state (heading DOWN, speed 0, clock 0, not armed, not done, launcher null), closes the HitBox and opens the HurtBox
  (`set_deferred`), re-enables and resets the lifetime, re-applies `impact_damage` to the HitBox.
- **`launch(dir, aim_point, launcher)`**: heading = `dir.normalized()` (zero → `Vector2.DOWN`); `inherited =
  max(0, launcher.launch_velocity().dot(heading))` when the launcher is valid and answers it, else 0; `speed =
  launch_speed + inherited`; `_aim = aim_point`; records `launcher` (a plain reference checked with
  `is_instance_valid`), `_clear_radius = launcher.rocket_clear_radius()` (duck-typed, else 0) and `_launch_point =
  global_position`; `_launched = true`; `rotation = heading.angle() + PI / 2`; `HitBox.damage = impact_damage`.
- **Tick** (`_physics_process(delta)` → `_tick(delta)`, `_tick` is the hand-tick entry tests call):
  return if done or not launched. With `t` = clock before this tick:
  1. guidance — if `turn_rate > 0` and `boost_seconds <= t < boost_seconds + guidance_seconds`:
     `_aim = _aim_point()`; `heading = Steering.turn_toward(heading, _aim − global_position, turn_rate, delta)`;
  2. speed — held during the boost (`t < boost_seconds`), afterwards `move_toward(speed, cruise_speed, accel × delta)`;
  3. `global_position += heading × speed × delta`; `rotation = heading.angle() + PI / 2`; `clock += delta`;
  4. arming — if not armed: the reference point is the launcher's `global_position` while it is valid and in the tree,
     the launch point (radius 0) for a null launcher; a launcher that was given and is now freed arms the rocket at once.
     Armed when `distance >= clear_radius + body_radius + arm_clearance`; opening is `set_deferred` on `monitoring` and
     `monitorable`.
  `is_guiding()` reports the same window on the current clock; `aim_point()` returns `_aim` (the launch aim until
  guidance replaces it).
- **`_aim_point()`**: `TargetInfo.player(get_tree())`; no target → **no turn this tick** (heading kept, `_aim` untouched — Revision 1 item 1);
  `intercept(global_position, speed)`; not ok or `time > lead_max` → `predicted_position(lead_max)`.
- **Impact** (`HitBox.area_entered`): return if done or not armed; return if `area.get_parent() is EnemyRocket`; return
  if `ArmorQuery.deflects(area, hit_box)`; else `_detonate()` = `_mark_done()`, `ContactBlast.spawn(get_parent(),
  global_position, blast_radius, blast_damage, blast_frames)`, pop, `expired.emit()`.
- **Shoot-down** (`HurtBox.area_entered`, connected by the rocket): return if done; return unless `area is HitBox`;
  return if its parent `is EnemyRocket`; else `_defuse()` = `_mark_done()`, pop, `expired.emit()` (no blast).
  "Once per area" is the `_done` latch: the first resolving area ends the life, every later one is ignored.
- **Fizzle**: `expired` from the `ProjectileLifetime` reaches `_on_expired()`; if not yet done it marks done and pops —
  never a blast. `_mark_done()` latches, closes both areas deferred, stops the lifetime's physics process (the Ph4 latch).
- Never in group `enemies`, never registered for score.

### `EnemyRocketScenes`

`DUMB` / `PURSUIT` preloads; `scene_for(kind)` returns them and `null` (with `push_error`) for kinds t6 adds.
`pool_size_for(kind, cfg)` = `count × ceil(max_time / cfg.salvo_period_min)`, `count` = `cfg.warhead_salvo_count`
for WARHEAD else `cfg.salvo_count`; `max_time` read from the kind's scene via `PackedScene.get_state()` (no
instantiation), falling back to the script default.

### Fixture launcher (`tests/helpers/rocket_launcher_fixture.gd`)

`extends CharacterBody2D`, no `class_name`, built in code by a static `build(at)`: a `HurtBox` on 512 / mask 1121 (circle
r 40) wired to a `Health` (100 HP), `launch_velocity()` = `velocity` (settable), `rocket_clear_radius()` = 40, a
`muzzle_offset` (default 20 px along the fire direction), and one `BulletPool` per kind (`pool_size` 4,
`persist_after_owner_death = true`, direct children) built in `_ready()`. `fire(kind, dir, aim_point) -> EnemyRocket`
acquires at `global_position + dir × muzzle_offset` and calls `launch(dir, aim_point, self)`. The rocket alone decides
arming; the fixture passes nothing else.

## Build sequence

1. Lifetime rows in `test_enemy_bullet_lifetime.gd` + `test_enemy_rockets.gd` skeleton (fail: no class).
2. `enemy_rocket.gd`, both scenes, `enemy_rocket_scenes.gd`; `--import`; lifetime rows green.
3. Fixture launcher; hand-ticked rows (guidance, DUMB, dodge, inequalities, moving launcher) green.
4. Real-physics rows (shoot-down, friendly fire, Ram plate, asteroid, real player scenes, world rect, fizzle, pool
   persistence) on the 8× clock, green.
5. `scripts/gate-time.sh` (≤ 6.0 s new GUT time), `scripts/check-test-leaks.sh`, `bash /agent/verify.sh`.
6. DECISIONS.md t5 as-built line (Revision 1 items 1, 6, 7 only; the tuning line already exists), docs via `updating-project-docs`.

## Test plan (`tests/integration/test_enemy_rockets.gd`)

Hand-ticked rows build `enemy_ai_harness.gd` in the body (`use_parameters(["open_space", "assault"])`), add the rocket,
turn off its and its lifetime's physics process, and call `_tick(1/60)` then the lifetime's `_physics_process(1/60)`
(tree order). In Assault a long row ends at the projectile rect edge (1608 × 1608); every assertion holds in both modes.

| Row | Mode | Asserts | Boundary / can-fail |
|---|---|---|---|
| guidance convergence | both | after boost the heading–to–aim angle shrinks monotonically until < 3°; per-tick turn ≤ `turn_rate·dt + 1e-4`; heading constant to 1e-6 after `boost + guidance` | turn cap is checked against the real per-tick delta |
| dodge (a) runner 420 px/s from 300 px ahead | both | never within `body_radius + 13.5` (largest real player hurtbox, fighter 5 × 2.7) before expiry | (c) is the same law hitting |
| dodge (b) 220 px/s head-on, 700 px/s perpendicular boost at 150 px | both | closest approach > `body_radius + 13.5` over the whole life | — |
| dodge (c) stationary 600 px | both | comes within touch distance | proves (a)/(b) can fail |
| DUMB straight | both | heading constant to 1e-6 for its life; reaches `cruise_speed` by `boost + (cruise − launch)/accel + 2 ticks`; `rotation == heading.angle() + PI/2` every tick | — |
| config inequalities | — | DUMB, PURSUIT: `cruise >= 1.1 × 210`, `launch > 240 × boost`; PURSUIT `cruise / turn >= 250` (constants `# until t7`) | a synthetic 200 px/s cruise fails the first |
| moving launcher | both | DUMB and PURSUIT: start speed `launch + 210`; distance grows every tick; `is_armed()` false while distance < `40 + r + 8`, true from the first tick at or past it | control with `launch_velocity()` = 0: distance shrinks |
| `pool_size_for` | — | DUMB 3, PURSUIT 6 with the plan's corvette numbers | — |
| reset restores exports | — | changed exports and state come back after `reset()` | — |
| shoot-down: player bullet | OS, physics | rocket `expired` once, no `ContactBlast`, bullet freed | — |
| shoot-down: homing missile | OS, physics | missile freed, rocket `expired` once, no `ContactBlast`, fixture enemy behind untouched | — |
| friendly fire on a fixture enemy | OS, physics | HP drops by exactly `impact_damage`, one blast, blast does not add damage; launcher HP unchanged after 0.5 s; two rockets 2 px apart both alive after 1 s | — |
| Ram plate | OS, physics | DUMB at a plate: 50 → 34, no `plate_broken`, rocket consumed, hull HP unchanged; second rocket at a plate set to ≤ 16 HP: `plate_broken` once | — |
| asteroid | OS, physics | big asteroid HP drops by `impact_damage` | — |
| real player scenes | both, physics | direct hit = `blast_damage`; detonation on a fixture 30 px away = `blast_damage`; at `blast_radius + 20` = 0; with one shield charge a direct hit spends exactly one charge and no HP | — |
| world rect | assault, physics | rocket fired out of the rect expires with no blast | — |
| fizzle | both, hand-ticked | lifetime expiry emits `expired` once and spawns no `ContactBlast` | — |
| persistence | OS, physics | freeing the launcher leaves in-flight rockets flying, an unarmed one arms on the next tick, each frees itself on expiry | `check-test-leaks.sh` |

Real-physics rows share builds where they can (one container, several rockets per case) to stay inside 6.0 s.

## Risks

- Real player scenes carry input, cameras and progression bindings: tests set `ShipProgressionState` shield count via the
  save sandbox pattern (`test_boost_bar.gd`), disable the ship's physics process so it holds still, and zero the shield
  through `Shield.set_all_zero()` where health must read the hit.
- `area_entered` on a newly opened HitBox for an area already overlapping: Godot reports it on the next flush; the arming
  rows only rely on that through real physics.
- Gate time: if over 6.0 s, convert rows to hand-ticked form or merge builds (never cut an assertion).

## Out of scope

CLUSTER, WARHEAD, SUBMUNITION (t6); the corvette and its `launch_velocity()` (t7); sprites (t9); any spawn in a level or
the hub.

## Revision 1 (answers 4-review.md round 1)

| # | Change |
|---|---|
| 1 | `_aim_point()` returns `{has, point}`; **no player → no turn at all** (heading kept, `_aim` untouched). New hand-ticked row (both modes): the harness player leaves group `player` before the boost ends; the heading stays constant to 1e-6 through `boost + guidance`. Ph4's bomb keeps its own behaviour (not touched). |
| 2 | Real-player rows set the test rocket's `impact_damage` to 3 (≠ `blast_damage`) before `launch()`, and record every `received_damage` emission on the real player `HurtBox`: the list must equal exactly `[blast_damage]` for a direct hit and for the 30 px detonation, `[]` at `blast_radius + 20`; the shield row asserts one charge spent, HP unchanged and the same `[blast_damage]` list. |
| 3 | Friendly-fire target = `fixture_enemy.tscn` built the `test_enemy_shield_hits.gd` way: HP 1000 set before entering the tree, a circle shape (r 16) added to its `HurtBox`, deltas read from `Health`. The homing-missile row gets a control in the same case: a second missile on a clear path to a second fixture damages it by the missile's damage. |
| 4 | Fizzle row awaits two physics frames after expiry before counting blasts (counted through `child_entered_tree`), with a positive control in the same harness: a hand-ticked detonation (rocket ticked into a fixture point via the impact handler called directly with a fixture hurtbox area) is counted as exactly one blast after the same await. |
| 5 | Ram plate row: Ram frozen (`suspend_ai()` plus `set_physics_process(false)`), rocket fired from behind the hull (−y side) along +y at `PlateFront` (0, 36), so it crosses the hull HurtBox (r 34) for several ticks first; `plate_broken` connected with a one-argument callable. |
| 6 | `launch()` applies `max_time` / `max_distance` to the lifetime, `body_radius` to both shapes and `impact_damage` to the HitBox (also done in `_ready()` / `reset()`). The reset row also checks a `max_time` set after `acquire()` and before `launch()` reaches the lifetime. |
| 7 | **Adopted the narrow fix:** the shoot-down handler also ignores `CONTACT`-type HitBoxes (the ally fighter's contact box is the only thing on layer 64 that is not a projectile), so an ally meeting a rocket detonates it through its 128 hurtbox and takes the blast, as the epic's table says. Logged in DECISIONS (t5 line). Row: a `CONTACT` HitBox on 64 crossing an armed rocket does not defuse it. |
| 8 | Row: a launched rocket is not in group `enemies` (and has no `score_value`). |
| 9 | Real-player rows record the `ContactBlast` position on `child_entered_tree` and assert its distance to the player `HurtBox`'s global centre (≤ 30 + body_radius for the near row; ≥ `blast_radius + 20` − 1 for the far one); the far rocket's path never comes within `body_radius + 13.5` of the player (it is fired from the far side of the fixture, away from the player). |
| 10 | `rotation` compared with `assert_almost_eq(…, 1e-5)`. |
| 11 | Claim removed: Assault rows end at the 1608 × 1608 rect edge; assertions hold in both. |
| 12 | No duplicate DECISIONS line; only the t5 as-built line with items 1, 6, 7. |
| 13 | `reset()` closes the HitBox with `set_deferred` as well. |
