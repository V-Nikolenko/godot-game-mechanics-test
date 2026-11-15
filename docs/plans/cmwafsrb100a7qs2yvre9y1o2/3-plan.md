# t4 — Heavy Gunship: shell, movement and Assault life

Task plan for Phase 10 t4. The design is the epic's approved plan (`docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` §2.4, §2.11, §2.15, §2.16, and
round-2 review findings N2, N7, N8, N10). This file fixes the build-level choices that plan leaves open and the test list. It does not redesign
anything; where it departs from a plan line it says so and the departure goes to `DECISIONS.md`.

## Problem

Today the Gunship drops from the top of the screen, parks 55 px below the top edge, slides left and right under the player, and flies off the
top when it is hurt. In Open Space it cannot work at all (it reads the camera). Three of level 1's four never fire, because their rails switch
off its `_physics_process`. After this task the Heavy Gunship is a mobile gun platform built from parts. It keeps its distance and turns a
battery side-on to the player. It sweeps wide arcs, boosts away when rushed, and turns its other side to you when a battery dies. In Assault it
does the same inside the corridor for a 9 s budget, then leaves along a measured curve. Overheat / vent / emergency / rear missiles are t5;
art is t9; level-1 rails come off in t11.

## Design

### Files (`git mv assault/scenes/enemies/gunship assault/scenes/enemies/heavy_gunship`)
`heavy_gunship.tscn` / `heavy_gunship.gd` (`class_name HeavyGunship extends BaseEnemy`), `heavy_gunship_brain.gd` (`HeavyGunshipBrain extends EnemyBrain`),
`heavy_gunship_config.gd` / `.tres` (`HeavyGunshipConfig extends ShipConfig`, flat), `ENEMY.md` rewritten. The `.uid` sidecars move with their
scripts (git mv keeps the UIDs). The scene is rewritten by hand, and every new `ext_resource` is left UID-less. The old textures stay as
placeholders: the hull `Sprite2D` keeps `heave_gunship.png` at rotation `PI` and is scaled to roughly cover the rectangle. The part `Sprite`
children have no texture until t9.

### Scene: exact geometry (flush-edge rule, review N2: outer sides exactly on the hull coordinate)
Hull frame: nose = local +y (nose-down art, `sprite_forward_angle` `PI/2`), so **port = local +x**, starboard = local −x. Body rectangle 112 × 144
centred on the origin: x ∈ [−56, 56], y ∈ [−72, 72].

| Node (under `Modules`) | id | role | HP | centre | rect (w × h) | exposed edge | `HomingPoint` (module-local) | Mount slot |
|---|---|---|---|---|---|---|---|---|
| `BatteryPort` | `battery_port` | WEAPON | 160 | (40, 10) | 32 × 40 | x = 56, y −10..30 | (16, 0) | BURST_CANNON, rest 0°, traverse 160 |
| `BatteryStarboard` | `battery_starboard` | WEAPON | 160 | (−40, 10) | 32 × 40 | x = −56, y −10..30 | (−16, 0) | BURST_CANNON, rest 180°, traverse 160 |
| `Cannon` | `cannon` | WEAPON | 200 | (0, 60) | 32 × 24 | y = 72, x −16..16 | (0, 12) | HEAVY_CANNON, rest 90°, traverse 70 |
| `Missiles` | `missiles` | WEAPON | 140 | (0, −60) | 40 × 24 | y = −72, x −20..20 | (0, −12) | ROCKET_BATTERY, rest 270°, traverse 360 |
| `VentPort` | `vent_port` | WEAK_POINT | 0 | (48, −34) | 16 × 24 | x = 56, y −46..−22 | (8, 0) | — |
| `VentStarboard` | `vent_starboard` | WEAK_POINT | 0 | (−48, −34) | 16 × 24 | x = −56, y −46..−22 | (−8, 0) | — |

Vents: `starts_vulnerable` false, `hull_share` 1.0. All others: `hull_share` 0, `starts_vulnerable` true. The hull keeps two bare stretches
of flank for the control shot: x = ±56, y 30..72 (42 px) and the 12 px gap y −22..−10.
Root: `CollisionShape2D`, `HurtBox/CollisionShape2D` and `ContactHitBox/CollisionShape2D` all reference **one** `RectangleShape2D` sub-resource at
scale 1 (contact / hurtbox geometry gates). Body layer / mask stay at the defaults 1 / 1, like every other mover-driven enemy. **Deviation from
§2.4.1** ("layer ENEMY_HITBOX"): a body on layer 256 would be seen by every mask that looks for enemy hitboxes. Logged in DECISIONS.
Other children: `Sprite2D` (hull, hit-flash material), `Health` (700), `HitFlashAnimationPlayer`, `ContactHitBox` (damage authored 30,
re-applied from config), `ContactProfile` (COLLISION), `Brain`, `EnemyMover`, `ModularHull`, `StateLight` at (0, 0).

### `HeavyGunshipConfig` (flat)
`@export_group` **Movement**: `max_speed` 140, `acceleration` 120, `max_turn_rate` 0.9. **Range**: `preferred_range` 560, `assault_preferred_range`
420, `range_drift` 90, `range_tolerance` 100, `min_range` 260. **Arc**: `orbit_angular_speed` 0.16, `assault_orbit_angular_speed` 0.26,
`assault_arc_half_deg` 70, `reversal_min` 5, `reversal_max` 8. **Tactics**: `break_speed` 360, `break_seconds` 0.7, `break_rearm` 3.0.
**Engagement**: `engage_seconds` 9.0, `exit_speed` 300, `exit_acceleration` 240. **Idle**: `perceive_radius` 900, `lose_radius` 1500,
`notice_time` 0.6, `idle_radius` 180, `idle_speed` 0.4. Inherited: `max_health` 700, `collision_damage` 30, `score_value` 300, hazards
1.0 / 90 / 0.6 (explicit in the `.tres`), `wreck_chance` 0. The Phases / Defense groups arrive with their fields in t5. The old fields are
deleted.

**Two Assault-only numbers that §2.16 does not list (judgement, logged in DECISIONS):**
- `assault_orbit_angular_speed` 0.26 rad/s (≈ 109 px/s at 420 px).
- `assault_arc_half_deg` 70: the Assault arc is kept within ±70° of straight above the player and reverses at its ends.

Why: §2.4.3 says the corridor clamps the arc so it "swings side to side above or beside the player". The corridor is 1480 × 1480 round the
view and does not stop an orbit at 420 px from passing under a player who sits 100 px above the view's bottom edge. At 0.16 rad/s the arc
also crosses the top of its sweep too slowly for the never-parks row: it spends 2.4 s within 8 px of one y. Lever (4) of §2.12 ("the
heavy's Assault orbit speed halved") is this export.

### `HeavyGunship` (root script)
- `_ready()`: `super._ready()`; join `enemies` and its owner group `StringName("heavy_gunship_%d" % get_instance_id())`. Apply the config:
  health, score, contact damage, mover `max_speed` / `acceleration` / `max_turn_rate`, and `brain.config`. Then
  `$ModularHull.build_mounts(self, brain.rng, owner_group, brain.attack_gate)` and `brain.bind_mounts(...)` (mounts by module id).
  `brain.attack_gate` is a bound `Callable` to the brain's `attack_gate_open()`.
- Duck-typed answers: `is_laser_blocking() -> false`; `launch_velocity() -> velocity`; `rocket_clear_radius()` = half-diagonal + 4
  (√(56² + 72²) + 4 ≈ 95.2, read from the body rectangle); `homing_point(from)` = the `homing_point()` of the nearest live vulnerable module
  (distance from `from`), else `global_position`.
- Accessors: `modular_hull()`, `owner_group()`, `body_size()`. No `_physics_process` of its own (BaseEnemy ticks brain then mover). No camera reads.

### `HeavyGunshipBrain`
`enum Phase { APPROACH, BROADSIDE, BREAK_AWAY, VENT, EMERGENCY, DISENGAGE, IDLE, NOTICING, RETURNING }` (append-only). `signal phase_changed(new_phase: int)`.
The structure is the Missile Corvette's: `_start()` on the first tick, then `EngagementBudget`, `AnchorIdle` in Open Space unless `start_engaged`,
and `orbit_dir` / reversal / drift drawn from `rng`.
- **APPROACH**: `arrive` at the point `held_range()` from the player on the line to it; the nose faces the player (the cannon bears). BROADSIDE
  once `|distance − held_range()| ≤ range_tolerance`.
- **BROADSIDE**: the corvette's arc (`Steering.orbit` at `held_range() + range_drift·sin(…)`, period drawn in 7–10 s; angle advancing at
  `orbit_dir × arc speed`; reversal every `reversal_min..max` s). In Assault the arc angle is clamped to ±`assault_arc_half_deg` of straight
  above the player, and reaching a limit reverses `orbit_dir` and redraws the reversal clock. Facing: `face_toward(pos + nose × 100)` with
  the nose chosen by `_desired_nose(bearing)`:
  - a live battery side → port: `nose = bearing.rotated(+PI/2)`; starboard: `nose = bearing.rotated(−PI/2)`. `_side` is chosen once, the first
    time a side is needed, as the side the player is on in the hull frame (local x ≥ 0 → port). It is kept while its battery lives, so the
    hull never flips needlessly. When its battery dies it becomes the other side if that one lives. The mover's `max_turn_rate` swings the nose
    the shorter way.
  - no live battery, cannon live → `nose = bearing` (nose to the player);
  - no live battery or cannon (missiles only) → `nose = −bearing` (keep the range, nose away).
- **BREAK_AWAY**: from APPROACH / BROADSIDE when the player is inside `min_range`, `break_left ≤ 0` and (Assault) `budget.remaining() ≥
  break_seconds`: `mover.boost(Steering.break_contact(pos, player, vel, −orbit_dir, 1).normalized(), break_speed, break_seconds)`, rearm
  `break_left = break_rearm` (counts down in every phase). While boosting it holds the broadside facing; BROADSIDE when the boost ends.
- **VENT / EMERGENCY**: stubs. Entering either goes straight on to BROADSIDE (t5 fills them).
- **Weapons** (every tick in APPROACH / BROADSIDE / BREAK_AWAY): `target = TargetInfo.player(tree)`. `sees = can_see_player()` on the physics
  step, true otherwise (the turret rule). Every gun mount gets `tick(delta, target, sees or mount.fires_past_cover())`, and the Missiles mount
  gets `can_fire` false (t5 opens it). In IDLE / NOTICING / RETURNING every mount `scan(delta)`s. In DISENGAGE nothing is ticked (no fire;
  the exit probe stays cheap).
- **Attack gate** (`attack_gate_open()`, every mount's `telegraph_gate`): true unless the budget is active and
  (`_disengage_pending` or `budget.remaining() < attack_window() + 0.05`). `attack_window()` is the longest `charge_seconds + (burst_count −
  1) · burst_gap` over the **live** gun mounts (battery, cannon): 1.05 s at full strength (heavy cannon 0.7 + 0.35). It is read from each mount
  duck-typed.
- **Budget expiry**: DISENGAGE at once, unless a gun mount is in TELEGRAPH / FIRE or the mover is boosting. In that case `_disengage_pending`,
  and DISENGAGE on the first tick neither holds. The gate stops any telegraph that would end after expiry, and the boost check stops any boost
  that would. So the deferral is bounded by `attack_window()` (asserted: `break_seconds ≤ attack_window()` at full strength).
- **DISENGAGE** (Assault only): `release_constraint()`, then the brain writes `mover.max_speed = exit_speed` and `mover.acceleration =
  exit_acceleration`. It curves at `min(max_turn_rate, exit_acceleration / exit_speed)` toward the nearest projectile-rect edge (+64 px
  overshoot), and `queue_free()` once outside the rect (the corvette's code). StateLight OFF.
- **Hub idle**: `AnchorIdle(patrol_anchor, perceive, lose, notice, idle_radius)`. IDLE `orbit`s the anchor, NOTICING stops and faces the player,
  RETURNING `arrive`s. RETURNING is never entered while boosting (retried every tick).
- `accepts_tow()` → false (every phase). `on_suspended()` → light off (a rail rides, mounts are no longer ticked: no fire).
  `on_emp_started()` → nothing extra (BaseEnemy halts the mover).
- StateLight: CHARGING while any gun mount telegraphs, ARMED while one can fire, else OFF (the turret brain's mapping, without COMMIT).
- Requests only: `arrive`, `orbit`, `request_velocity`, `face_toward`, `boost`, the two limit writes on DISENGAGE, `release_constraint()`.

### Builder and callers
`WaveBuilder.heavy_gunship()` / `HEAVY_GUNSHIP` replace `gunship()` / `GUNSHIP`.
- `level_1_director.gd`: the four rows become `b.heavy_gunship()`, unchanged otherwise. Their rails stay until t11; the deep_space 3.5 s row has none.
- `level_2_waves.gd:34`: becomes `builder.heavy_gunship()`, rail kept. Its commented lines use `builder.HEAVY_GUNSHIP`.
- `test_station_reinforcements.gd:363` asserts `WaveBuilder.HEAVY_GUNSHIP`, with "heavy gunship is AI and must never get a mover".
- AC "no file references …" is scoped to `.gd` / `.tscn` / `.tres` / `.cfg` outside `docs/` and `.godot/` (review N8).

### Exit probe — `tests/helpers/ph10_exit_keys.gd`
`heavy_gunship_exit(host)`. It calls `PROBE.worst_disengage(host, load(SCENE), Phase.DISENGAGE, [break_speed, 10.0], 20.0, corridor_starts(host),
prepare_probe)`. `break_speed` (360) is the fastest the hull can carry into DISENGAGE (a boost, since `max_speed` is 140).

The static `prepare_probe(ship)` does two things:
- It drops every `player` from its group (the Ph9 rule; DISENGAGE never reads the player).
- It frees every module's `MountSlots` before the ship enters the tree, so no mount or pool is built. Mounts never write motion, so the exit is
  bit-identical; a row pins one start with and without the hook.

`corridor_starts(host)` is built exactly as `ph9_exit_keys.gd` builds it. The plan names both the view grid and `corridor_starts()`. The
corridor set covers the view grid's area, and each of its positions includes the heading straight away from its exit edge. I will measure the
view grid once during development. If it is not slower, only the corridor set ships (saving ≈ 0.8 s), and both figures go in DECISIONS;
otherwise both sets ship. `test_heavy_gunship.gd` sweeps `tests/` for a hand-built Ph10 probe call (the Ph8 / Ph9 sweep).

### Legacy rows moved (§2.4.6)
- `test_base_enemy.gd`: roster comment renamed. `test_legacy_enemies_are_not_ai_driven` keeps `bonus_drone` only. `heavy_gunship` joins the
  every-phase refusal row; its title widens from "mover-less structure" to "every-phase refusers".
- `test_enemy_emp.gd` legacy rows and `test_emp_blast_module.gd`'s legacy process-disable row use the Bonus Drone (legacy, no brain), with the same assertions.
- `test_config_instance_isolation.gd`: the canonical subject keeps the gunship under the new path and class.
- `test_enemy_bullet_lifetime.gd`: drops `gunship_cfg.bullet_speed` (the derived defaults are unchanged, because 150 stays the minimum).
- `test_support_ship.gd`: the gunship row flips (owner choice 7). The Heavy Gunship is a legal ward (`is_candidate` true), and beside a fighter
  and a bonus drone it is chosen (higher score). The bonus drone stays not a candidate.
- `test_explosion_effect_placement.gd`: scene path renamed.
- Roster renames: `test_enemy_contact_damage.gd` (`test_heavy_gunship_rams_for_its_configured_collision_damage`, `HeavyGunshipConfig`),
  `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd` (the "only real gap" comment is updated).
- `test_enemy_dual_mode.gd`: a `heavy_gunship` `HAZARD_PROFILES` row (1.0 / 90 / 0.6), and one spawn row (closes to its held range in both modes).

## Build sequence
1. `git mv` the directory and files. Write the config, the brain and the root script. Rewrite the scene. Update the builder and callers
   (levels, station test). The project imports and level 2 loads.
2. Write `test_heavy_gunship.gd` (rows below) and `ph10_exit_keys.gd`. Run them red, then green.
3. Move the legacy / roster rows. Run every roster gate and the level-1 gates and replays.
4. Measure the exit (corridor and view grid) and the gate time: two `scripts/gate-time.sh` runs, plus the summed time of the new / changed files.
5. Update `DECISIONS.md` (t4 notes: the measured exit, the deviations above, and N7: owner choice 3 holds for projectiles only, since the beam on a
   part and a root `EnemyShield` do not wear the hull through a part). Add the `tests/README.md` gate row. Update the docs (`updating-project-docs`:
   ENEMY.md, assault.md, PROJECT.md / CLAUDE.md lines, enemy-roster builder name). Run `bash /agent/verify.sh` and `scripts/check-test-leaks.sh`.

## Test plan — `tests/integration/test_heavy_gunship.gd`
Hand-ticked at 1/60 (`_tick`: `_physics_process(dt)` then the position integrated) unless the row is real physics. `_spawn()` writes
`engage_seconds = 1000` except in the Assault-life rows. The player stub is moved by the test. "Both" = label-parameterised over `["open_space", "assault"]`.
1. **Spawn** (both): 6 modules with the table's ids / roles / HP; 4 mounts with variants BURST, BURST, HEAVY_CANNON, ROCKET_BATTERY and traverses
   160 / 160 / 70 / 360; hull `Health` 700; contact damage 30; `is_ai_driven()`, `answers_emp()` true; `rocket_clear_radius()` ≈ 95.2; owner group joined;
   the shipped config numbers; `break_seconds ≤ attack_window()`; the Phase enum is append-only.
2. **Flush-edge (static)**: for every module, its hurtbox rect's outer side is within **0.01 px** of the root hurtbox side over its whole
   width (N2). Its `HomingPoint` is the midpoint of that side. Body, root hurtbox and contact box share one `RectangleShape2D`.
3. **Every part is reachable** (real physics 8×, both; hull held still): for each of the six parts, a player bullet fired along the inward normal at
   its `HomingPoint` damages the part once and the hull by `damage × (1 + hull_share)`. That is ×1 for guns, and ×2 for vents opened for the row
   (direct hit + forward). A control bullet into the bare flank at (56, 51) damages only the hull. A closed vent hit through its edge: the hull
   takes ×1 and the vent emits `deflected`.
4. **Homing rocket** (real physics 8×, both): a player homing missile `locked_target` = the gunship, launched from the port side, damages `BatteryPort`.
5. **Range** (both): over 20 s against a still player and against a 200 px/s circling player (circle radius 300 round the start point),
   the distance stays within `held_range() ± (range_drift + range_tolerance)` once first inside it.
6. **Broadside** (Open Space): both batteries alive, the angle between the nose and the bearing to the player is within 90° ± 20° for ≥ 80 % of
   20 s of BROADSIDE. Control: the same run with `max_turn_rate` 0.05 misses the 80 %.
7. **Side swap** (both): port facing the player; `BatteryPort.destroy()`; within 5 s the starboard side faces the player (angle within 90° ± 20°,
   starboard side) and stays there for the rest of 10 s. Then `BatteryStarboard.destroy()`: within 5 s the nose faces the player (± 20°). With
   the cannon also destroyed, the nose points away (± 20°).
8. **Break-away** (both): a 300 px/s rusher inside `min_range` triggers exactly one boost (BREAK_AWAY entered once); a second entry inside
   `min_range` within `break_rearm` triggers none; after the rearm, another one.
9. **Assault never parks**: over 9 s with the player moving left and right at 150 px/s, the y spread is ≥ 120 px, and the hull never stays within
   8 px of one y for more than 2 s. After first entering the corridor rect it never leaves `inner_rect().grow(soft_band)` before DISENGAGE. It
   never goes below the player.
10. **Assault life**: with the shipped 9.0 s budget, DISENGAGE is entered at 9 s (+ deferral ≤ `attack_window()`) and the hull is freed within
    the measured exit after that. A 1 s budget boundary row ends in DISENGAGE. Over a full life no mount enters TELEGRAPH with
    `budget.remaining() < attack_window() + 0.05` (recorded on each mount's `phase_changed`). Control: with the gate bypassed, a telegraph
    starts too late.
11. **Open Space never disengages**: 30 s with `engage_seconds` 9.0 in Open Space and no DISENGAGE.
12. **Hub idle** (Open Space): it orbits the anchor at `idle_radius`; it notices at `perceive_radius` (NOTICING, then APPROACH) and RETURNs
    beyond `lose_radius`.
13. **No legacy assumptions**: a source sweep of `heavy_gunship*.gd` for `get_camera_2d`, `get_visible_rect`, `_physics_process` and `Timer`
    (none). The probe-key sweep over `tests/`. The exit-probe bit-identity row (prepare hook vs none on one start). The probe ran once (memo).
14. **Fires** (Open Space): with the player 500 px off the port beam, a Pulse round leaves `BatteryPort`'s mount within 4 s, and the Missiles
    mount never fires in 20 s (t5).

Boundary rows: the 1 s budget, the late-telegraph control, the 0.05 turn-rate broadside control, and the closed-vent control.

## Risks
- **Gate time** (3.5 s allotment): the probe is ≈ 2166 hand-ticked runs. Mitigations: mounts stripped by the hook, mounts not ticked in
  DISENGAGE, and the memo. If it is over, share scenarios between rows first.
- **Level-1 side effects**: the deep_space heavy now fights. Slice replays that include it (`test_level1_ph8_attacks.gd`'s 3.0 s slice) must
  stay green. Lasers are not lit in replays (t11 lights them).
- **Real-physics part rows**: a bullet's first overlap is ≤ 15 px deep, and the vent is 16 px deep. The flush edge (exact) guarantees a
  same-step overlap with both.

## Out of scope
VENT / EMERGENCY behaviour, the cannon shield, rear missiles opening, battery-loss UNPOWERED rows (t5); art (t9); level-1 rails, the lit replay,
the heavy count / deadline / spill-over gates (t11); docs beyond the rename and the new entity's own doc (t13).

## Revision 2 (after review round 1, `4-review.md`)

Each change below supersedes the matching text above.

- **B1. Broadside in both harnesses.** Row 6 is label-parameterised over `["open_space", "assault"]`. The Assault run uses the shipped Assault arc
  and clamp with a still player at (640, 620). The `max_turn_rate` 0.05 control runs in both.
- **M1. The probe strips the whole `Modules` node.** `prepare_probe(ship)` drops `player` from its group and frees `Modules` before the ship
  enters the tree. `ModularHull._ready()` already returns cleanly without one, so there are no parts, no mounts and no pools. The root tolerates
  an empty hull: `bind_mounts` gets a hull with no modules, `homing_point()` falls back to `global_position`, and the brain treats "no part" as "no
  live battery or cannon". DISENGAGE reads none of it, and the bit-identity row pins the hook. **Build step 2 measures the probe's cost first**,
  before the other rows, and records it. **Escalation trigger:** if the probe alone costs more than 1.5 × 3.5 s = 5.25 s (wall, `before_all`), the
  run ends `Result: ESCALATE` with the profile.
- **M2 (N10). The approach-speed lever is deferred to t11, and t4 measures the figure.** t11 owns the level-1 attack-in-budget rows and the lit
  replay, and which lever helps depends on that replay. t4 adds one hand-ticked Assault row that measures the time to the first battery
  `TurretMount.Phase.FIRE`. The heavy spawns at the deep_space row's world point and the stub sits at `level1_slice_replay.gd`'s `PLAYER_OFFSET`
  from the view centre. The row asserts the fire happens before the 9 s budget ends (the row fails if it does not) and prints the time, which
  goes in DECISIONS for t11. The world point is read through the real `WaveManager` placement math (`WaveBuilder` design units × `ArenaCamera.WORLD_SCALE`
  from the view's top-left, the same formula `level1_slice_replay.gd` uses) and is never typed.
- **M3. EMP cancels a shown telegraph.** `on_emp_started()` calls `scan(0.0)` on every mount (it stops the weapon, starts the cooldown if it was
  firing, and enters SCAN) and turns the light OFF. New row, both harnesses: an EMP during a battery TELEGRAPH means no round from any mount for the
  window and the light OFF; the battery fires again after. Extra row: a railed heavy (`suspend_ai()`) fires nothing over 5 s with the player in arc
  and range, and its light is OFF.
- **M4. No fire from outside the view in Assault (the turret rule).** When `EnemyWorld.has_view_rect(tree)` holds, every mount's `can_fire` is
  ANDed with `EnemyWorld.view_rect(tree).has_point(actor.global_position)`. New row (Assault): a hull held still 200 px above the view's top edge,
  with the player inside the cannon's arc and range, starts no TELEGRAPH in 3 s. The control: the same hull inside the view does.
- **M5. Never-parks over three seeds.** Row 9 runs seeds 1, 2 and 3. If one fails, the rule is fixed (a reversal drawn while the arc is within the
  apex band waits until the hull has left it), and the seed is not chosen.
- **M6. A deterministic late-telegraph control.** Row 10's control first runs the 1 s-budget scenario ungated with a long budget and records the
  first battery TELEGRAPH time `t0`. Then `engage_seconds = t0 + attack_window() / 2`: the ungated run must telegraph with less than
  `attack_window() + 0.05` left, and the gated run must not.
- **M7.** The DECISIONS note and the `ph10_exit_keys.gd` header say: **any change to an exit lever (`exit_speed`, `exit_acceleration`,
  `max_turn_rate`) re-runs the view-grid comparison** before the corridor-only set stands.
- **M8. The derived exit bound is checked in t4.** New row: `engage_seconds + attack_window() + heavy_gunship_exit().seconds + 0.5 < 23.2`.
  `CLOUD_DESCENT_WINDOW := 23.2` is a named constant citing §2.12 / §2.4.3 (t11 replaces it with the live `_deadline_rows` figure). The margin is
  recorded in DECISIONS.

## As built (deviations from the text above)
Recorded in full in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` → *Phase 10, built in t4*: `braking` 360 in the config; the orbit angle may
lead the hull's bearing by at most `ORBIT_MAX_LEAD` 0.35 rad and re-syncs after a break-away; DISENGAGE is a fast path at the top of `tick()`;
row 5's circling player strafes round the heavy instead of jinking on its own 300 px circle; the hub-idle row ticks 4 s longer; the M5 apex rule
was not needed (seeds 1–3 green); the real-physics rows run at the 16× clock (they wait a count of physics frames). The file's own time is over
the 1.5× allotment line; see the gate-time note there.
