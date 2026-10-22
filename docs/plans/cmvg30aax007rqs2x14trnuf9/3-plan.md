# t10 — Wrecks and derelict structures are real cover; debris drifts as a collision hazard

Epic `cmug23om70001m52wqfwclf3l`, phase 6. The design is the epic's approved plan §2.8 (with "For every task", §2.17,
§4.1, §4.4). This file pins only the build choices §2.8 leaves open, the build order and the test layout. Nothing below
changes a name, layer, number or rule of §2.8 except where marked **(pinned)** with the reason. Context: `1-context.md`.

## Problem

Today a destroyed ship leaves nothing, and the battlefield has no solid cover: only asteroids block sight. Phase 6's
later tasks (t11 wreck spawning, t12 explosive wrecks, t13 sniper cover, t14 fighter cover, t15 the Ram's plate fragment,
t18 the hub battleground) all need one thing first: a dead hull that is solid for ships, opaque for sight lines and
shots *from both sides*, harmless when it sits still, dangerous when it drifts into you, and that goes away on its own
without ever vanishing on screen.

## Design

### Files

`assault/scenes/hazards/wreck/`:
- `wreck.gd` — `class_name Wreck extends CharacterBody2D`.
- `wreck_small.tscn`, `wreck_medium.tscn`, `wreck_large.tscn`, `structure_satellite.tscn`,
  `structure_cargo_platform.tscn`, `structure_station_module.tscn` — all on `wreck.gd`.
- `debris_fragment.gd` — `class_name DebrisFragment extends Area2D`; `debris_drift.tscn`.
- `wreck_scenes.gd` — `class_name WreckScenes extends RefCounted`, `enum Size { SMALL, MEDIUM, LARGE }`,
  `static func scene_for(size: int, explosive: bool) -> PackedScene` (explosive → `null` until t12).
- `HAZARD.md` — one file for the folder (every scene in it is on one of the two scripts; same as `gravity_well/`).

### Wreck scene layout (each of the six)

```
Wreck (CharacterBody2D, wreck.gd)  layer 1 (ENVIRONMENT), mask 0
├── Sprite2D                       the t9 PNG, scale 1
├── CollisionShape2D               CircleShape2D "Shape_body"
├── Health                         health_component.gd
├── HurtBox (HurtBox)              layer 512, mask 96
│   └── CollisionShape2D           SAME SubResource "Shape_body", same transform  (covers the body exactly)
├── ContactHitBox (HitBox)         layer 1024, mask 0, monitoring false, monitorable false, damage 10, CONTACT
│   └── CollisionShape2D           SAME SubResource "Shape_body", same transform  (contact-geometry rule)
└── ProjectileLifetime             max_time 30, max_distance 0, use_world_rect true
```

**(pinned) Circles.** Every body is one `CircleShape2D` so `HazardInfo.radius` is the body radius exactly, the LOS ray and
the avoidance footprint agree, and the yield test below is a centre-distance check. Radii from each sprite's opaque
footprint (r50–r90 of opaque pixels, measured): small 13, medium 25, large 40, satellite 28, cargo platform 55, station
module 45. HP: wrecks 200, structures 800. Structures: `lifetime = 0`, `drift_velocity = 0`.

### `wreck.gd`

Exports: `blocks_los := true`, `drift_velocity := Vector2.ZERO`, `lifetime := 40.0` (0 = permanent), `assault_drift :=
60.0`, `health_amount := 200`, `contact_damage := 10`, `contact_arm_delay := 0.6`, `avoid_weight := 0.6`,
`lifetime_fade := 2.0`. Constants `RETIRE_FADE := 0.5`. Signals `expired` (ProjectileLifetime's host signal) and
`destroyed(world_position: Vector2)` (HP reached 0; t12 hangs the explosive blast on it).

- `_ready()`: join group `wrecks`; `Health.set_health(health_amount)`; HurtBox `received_damage → Health.decrease`;
  `Health.amount_changed(current)` → at ≤ 0: `ExplosionEffect.explode()` (asteroid precedent), `destroyed.emit`,
  `queue_free()` (no fade: it blew up). `HitEffect.burst()` on every hit. `expired → queue_free` (Assault only reaches it:
  leaving the world rect is off screen). Contact box `damage = contact_damage`, `damage_type = CONTACT`.
- `_enter_tree()`: apply the pending `spawn_into` transform; `_assault = EnemyWorld.arena(get_tree()) != null`; in Open
  Space `ProjectileLifetime.set_physics_process(false)` **(pinned)** — its 30 s cap must not cut the 40 s Open Space life,
  and Open Space has no rect; reset `_age`; `Hazards.register(self)`.
- `_exit_tree()`: `Hazards.unregister(self)`.
- `_physics_process(delta)`: `_age += delta`; arm the contact box once at `_age >= contact_arm_delay`
  (`set_deferred("monitorable", true)`); Open Space with `lifetime > 0` → `retire(lifetime_fade)` at
  `_age >= lifetime - lifetime_fade`; move (below); write `velocity` (the drift actually applied, for readers — never
  `move_and_slide()`).
- Velocity: Assault `Vector2(drift_velocity.x, assault_drift)`; Open Space `drift_velocity`.
- `hazard_info()`: one `HazardInfo`, `kind = &"wreck"`, `radius` = body radius × node scale, `avoid_weight`,
  `velocity` = applied drift, `line_of_sight_blocker = blocks_los`, `source = self`, no forces.
  `try_claim(node)` / `release(node)` / `is_claimed_by(node)` delegate to it.
- `blocks_line_of_sight() -> bool` → `blocks_los`. `stops_enemy_rounds() -> bool` → `true`.
- `spawn_into(container, at, rot)` / `_attach(container)` (untyped) — verbatim `HazardField`. Sets `spawned = true`
  **(pinned)** so t11's alive cap can count only runtime wrecks (epic review round 2, N4) and never retire a placed
  structure.
- `retire(fade := RETIRE_FADE)`: once; `Hazards.unregister(self)` at once; release any claim; body `collision_layer = 0`,
  HurtBox and ContactHitBox `collision_layer = 0` (a layer write is legal inside a flush; `monitorable` goes via
  `set_deferred`); then `modulate.a` falls linearly to 0 over `fade` seconds of accumulated delta and `queue_free()`.
  `is_retiring()` for tests and t11. `_enter_tree` does not re-register a retiring wreck.

### (pinned) The clamp-edge yield

§2.8 asks for the row "a wreck drifting onto the Assault player at the clamp edge never holds the player for more than
2 physics frames", and names the remedy "the wreck yields: it stops drifting into a body it touches". Measured context:
the Assault player moves in `_process` and its idle state never calls `move_and_slide()`, so nothing would ever push an
idle player out of a wreck that position-writes into it, and at the clamp edge (y 1100) even a moving player is clamped
back in. Without a yield the row fails, so the yield is built, in both modes, for bodies in groups `player` and `enemies`:

- Each tick with a non-zero velocity, before the position write, the wreck queries its own body shape
  (`PhysicsDirectSpaceState2D.intersect_shape`, bodies only, mask `ENVIRONMENT | ENVIRONMENT_PLAYER`, itself excluded)
  at its **current** position, and keeps only colliders in `player` / `enemies` that lie ahead of the drift
  (`(ship.global_position − global_position).dot(v) > 0`).
- If one overlaps: undo the previous tick's step (`global_position -= _last_step`, at most once per contact) and hold
  (`_last_step = 0`, applied velocity 0) — the overlap lasts at most the one tick in which it began.
- While holding, it re-queries at the **next** position each tick and resumes as soon as that is clear of every ship ahead.

So the first contact still happens (the step that runs into a ship overlaps it for one physics step, which is what makes
a drifting wreck hurt), and the hold ends the overlap on the next tick. A ship that moves away releases it. Cost: one shape
query per moving wreck per tick (no query for a stationary wreck or structure; at most t11's cap of wrecks alive).
"Held" in the test = a physics frame in which the wreck's and the player's body circles overlap by more than 0.5 px.

### Shots and sight (both sides)

- Player bullets (mask 513), player rockets and enemy rockets (impact masks 513 / 640) stop on the HurtBox (512) and
  damage the Health. Wrecks are not in `enemies`, never scored, never in the enemy container, never a homing target
  (every targeting path reads group `enemies`).
- `enemy_bullet.tscn` HitBox `collision_mask` 128 → 1152 (`PLAYER_HURTBOX | HAZARD_CONTACT`); the rounds inherit it.
  `_on_hit_box_area_entered(area)`: `if area.collision_layer & CollisionLayers.HAZARD_CONTACT and not
  _stops_rounds(area): return` then `expired.emit()`. `_stops_rounds` asks `area.owner` (falling back to
  `area.get_parent()`) for duck-typed `stops_enemy_rounds() == true`. Asteroid contact boxes (1024, owner an
  `AsteroidBase`) do not answer, so a round still passes an asteroid; `become_friendly()` still writes mask 513.
  `test_enemy_rounds.gd:59`'s pinned mask is updated to the new value (an intended change, not a regression).
- Before the contact box arms (first 0.6 s) a round passes the wreck; accepted (a wreck that just appeared).
- LOS: the body is on layer 1 and answers `blocks_line_of_sight()`, so `LineOfSight.clear()` stops at it unchanged.
- Beam: blocked (layer-1 body) and cannot cut a wreck (beam damages only `enemies` / `asteroids`) — stated in `HAZARD.md`.

### `debris_fragment.gd` / `debris_drift.tscn`

```
DebrisFragment (Area2D, debris_fragment.gd)  layer 0, mask 0, monitoring false, monitorable false
├── Sprite2D                                  debris_1.png
├── ContactHitBox (HitBox)                    layer 1024, mask 0, damage 8, CONTACT, monitorable false
│   └── CollisionShape2D                      CircleShape2D r 14
└── ProjectileLifetime                        max_time 30 (= `lifetime`), max_distance 0, use_world_rect true
```

Exports `speed := 30.0`, `deceleration := 0.0`, `spin := 0.0` (rad/s), `lifetime := 30.0` (0 = permanent → the
`ProjectileLifetime` is switched off), `direction := Vector2.DOWN`, `avoid_weight := 0.4`, `textures:
Array[Texture2D]` (debris_1..6), `speed_min := 20.0`, `speed_max := 40.0`; vars `source: Node`, `source_clear_radius :=
0.0`. `configure(rng: RandomNumberGenerator)` picks the texture, a speed in `[speed_min, speed_max]` and a direction from
the caller's rng (randomness only from a seeded rng — the plan's determinism rule); without it the authored values hold.
Movement: `speed = max(0, speed − deceleration·delta)`, `global_position += direction·speed·delta`, `rotation +=
spin·delta` (the heading is `direction`, never the rotation). Contact box armed (`set_deferred("monitorable", true)`)
on the first tick at which `source` is invalid or the centre is farther than `source_clear_radius` from it; it stays
armed. `HazardInfo` `kind = &"debris"`, radius = contact radius, `avoid_weight`, `velocity`, LOS false. Not a body, so
never a LOS blocker and never solid. `expired → queue_free`. Same `spawn_into` / `_attach` / `_enter_tree`.

**(pinned) Debris hurts on touch whatever its speed.** §2.8's "only a moving wreck or debris hurts" rests on a body
stopping the ship first; a fragment has no body, so a ship that flies into one is hurt. That is what makes it a collision
hazard. (Hub debris with `speed` 0 is t18's to place.)

### Test layout — `tests/integration/test_wreck.gd`

Real physics on the 8× clock (`_scale_clock()` / `_restore_clock()` in `before_each` / `after_each` only for the files'
physics rows — a per-test helper flag, like `test_level1_drone_exit.gd`); hand-ticked rows otherwise. All nodes added
with `add_child_autofree`.

1. `test_los_blocked_by_wreck_not_by_debris` — two points either side, real `LineOfSight.clear()` after one physics frame.
2. `test_player_bullet_stops_on_wreck_and_damages_it` (real `bullet.tscn`, `expired` counted, HP < 200).
3. `test_enemy_rocket_stops_on_wreck` (real `dumb_rocket.tscn` fired at it: it detonates / ends).
4. `test_enemy_round_stops_on_wreck_after_arming` and `test_enemy_round_still_passes_an_asteroid` (real
   `pulse_round.tscn` from a `BulletPool`, real `small_asteroid.tscn`).
5. `test_wreck_hp_reaches_zero_under_fire_and_it_frees` (direct `received_damage` × n).
6. `test_drifting_wreck_hurts_the_player_and_an_enemy` (dual-mode: real `player_ship.tscn` / `player_fighter.tscn` and a
   real `swarm_drone.tscn`; armed wreck drifting into each). `test_stationary_wreck_touched_by_moving_player_does_not_hurt`
   (Open Space ship flown into it with `move_and_slide` for 1 s: blocked, HP unchanged).
   `test_wreck_spawned_on_player_does_not_hurt_before_arming` (spawned overlapping, HP unchanged at 0.55 s).
7. `test_assault_drift_is_60_down_whatever_inherited_y` and `test_assault_wreck_frees_on_leaving_world_rect`;
   `test_open_space_wreck_frees_after_lifetime` (hand-ticked: retiring at 38 s, gone after 40 s + one frame).
8. `test_wreck_at_clamp_edge_never_holds_assault_player_over_2_frames` (real `player_fighter.tscn` at y 1100 inside an
   `assault` harness, wreck above drifting down; ≤ 2 overlapping frames over 3 s; boundary: the same with the yield
   disabled (`yield_to_ships = false`, a test-only export) holds it for many frames — proves the row can fail).
9. `test_retire_unregisters_at_once_and_frees_after_fade`; `test_spawn_into_freed_container_leaves_no_orphan` (both
   scripts); `test_registered_while_alive_unregistered_after_free`; `test_never_in_group_enemies`;
   `test_claims_delegate_to_info`; `test_wreck_scenes_scene_for`.
10. Fragment rows: decelerates and stops, spins without turning its heading, armed only once clear of a live source (and
    at once when the source is freed), frees after `lifetime`, `configure(rng)` deterministic for one seed.

Gates: add the six wreck scenes to `test_enemy_hurtbox_geometry.gd` and `test_contact_hitbox_geometry.gd` ROSTERs (their
completeness guards only sweep `enemies/`). Transparency, collision-layer and UID gates sweep the new files themselves.

## Build sequence

1. Tests 1–10 written, watched failing (missing classes).
2. `wreck.gd` + `wreck_medium.tscn`; rows 1–9 green on it.
3. Other five scenes; `WreckScenes`; roster additions.
4. `EnemyBullet` mask + filter; `test_enemy_rounds.gd` mask row; row 4 green.
5. `debris_fragment.gd` + `debris_drift.tscn`; row 10.
6. `HAZARD.md`; `global.md`/module doc pointer via `updating-project-docs`; leak check; gate; gate time.

## Risks

- **Stationary-harmless margin is 0.05–0.27 px** (slide margin + radius difference). Row 6 is a real-physics row so a
  change to player scale fails loudly. If it ever proves flaky, the fallback is arming the contact box only while the
  wreck's drift is non-zero (rounds would then pass a stationary structure, so it is not the default).
- **Yield vs. "drifting wreck hurts"** — the hurt depends on the one overlapping physics step. Row 6 proves it.
- **Gate time**: allowance +3 s; physics rows use short windows (≤ 3 s simulated at 8×).
- **EnemyBullet change** touches every enemy round; the full suite (rounds, density, station gunnery) is the check.

## Out of scope

Wreck spawning on death and the alive cap (t11), explosive wrecks and `scene_for(_, true)` (t12), cover use (t13/t14),
the Ram's fragment scene (t15), hub placement (t18), phase docs (t19).

## Revision 2 — answers to `4-review.md` round 1 (supersedes the text above where they differ)

| Finding | Change |
|---|---|
| **B1** OS lifetime switch-off undone by the child's READY | In Open Space the wreck writes `_lifetime.max_time = 0.0` in its own `_ready()` (a property, never reset by READY; Open Space has no rect and `max_distance` is 0, so the component is inert). No `set_physics_process` toggling anywhere. Rows: `test_open_space_wreck_survives_real_physics_past_30_s` (real physics, 8×: after ≥1 frame `max_time == 0`, and a hand tick of the child's `_physics_process(31.0)` leaves the wreck registered and in the tree) and the same for `structure_satellite.tscn`. Debris: `_lifetime.max_time = lifetime` in `_ready()` (0 → 0), no toggling. |
| **M1** yield fires before the hit | The hold starts only when, for a ship ahead whose body the wreck overlaps, **either** `Hazards.hurt_box_of(ship).overlaps_area(ContactHitBox)` is true (the hit registered at the last step) **or** the penetration along the drift exceeds `YIELD_DEPTH` 1.5 px (shape query at `position − v̂·1.5` still overlaps; covers an unarmed box, a rolling player and a ship with no hurtbox). On the hold the wreck backs off by the whole distance it travelled while overlapping that ship (`_overlap_travel`), so the overlap ends on that tick. Row 6 becomes a sweep: 10 sub-pixel start offsets (0.0–0.9 px, exact touch included) run **concurrently** in one scene (pairs 200 px apart) for the Open Space ship, the Assault fighter and a real Swarm Drone, plus a 15 px/s Open Space drift; each ship hurt exactly once. |
| **M2** sniper hurtbox > body | `sniper.tscn` HurtBox shape scale 1.4505496 → 1.4400002 (= body; still covers it for the hurtbox gate). New invariant row: for every mover-driven enemy scene (9) and both player scenes, the hurtbox circle radius × global scale ≤ the body's (+0.001); the bomber's rectangle compares half-extents. Real-physics row: a real `sniper.tscn` pushed into a still armed wreck with `move_and_slide()` for 1 s takes no damage. Context and Risks corrected: a body rests touching (gap ≈ 0–0.007 px), so "still = harmless" rests on hurtbox ≤ body, not on the slide margin. |
| **M3** Health clamps to 100 | `_ready()` sets `Health.max_health = health_amount` before `set_health()`; the scenes author both too. Row: one 10-damage hit leaves exactly `health_amount − 10` (medium wreck 190, satellite 790). |
| **M4** a retiring wreck still takes hits | `retire()` also `HurtBox.set_deferred("monitoring", false)` and the damage / death handlers return while retiring. Row: a real `bullet.tscn` through a retiring wreck — HP unchanged, no `destroyed`, bullet not consumed. |
| **m1** Sniper Shot pierces cover | Pinned: **cover stops the Sniper Shot.** `bullet.gd`'s `unlimited_pierce` branch stops on group `asteroids` **or** a parent answering duck-typed `stops_piercing() == true`; `Wreck.stops_piercing()` → true. Row: a Sniper Shot (`sniper_bullet.tscn`) ends on a wreck. Logged in DECISIONS. |
| **m2** held Assault wreck vanishes at the 30 s cap | `expired → retire()` (0.5 s fade then free), not `queue_free`. |
| **m3** a wreck spawned on a ship parks on it | Ships the body already overlaps on the wreck's first physics tick are ignored by the yield until they separate. Row (Assault): a wreck spawned on the idle player drifts off it, overlap gone within 1.5 s. |
| **m4** debris lifetime twice | `lifetime` is the single source (copied in `_ready()`). |
| **m5** pinned choices unrecorded | Build step 6 adds a Phase 6 DECISIONS.md entry: circle bodies and radii, `spawned`, the yield (+ `YIELD_DEPTH`), debris hurts at any speed, Open Space lifetime via `max_time`, hurtbox ≤ body, cover stops the Sniper Shot, `stops_enemy_rounds` / `stops_piercing`. |
| **m6** stale gunnery comment | Step 4 updates `station_gunnery.gd:33-35` (mask 1152; 1024 areas only stop a round when the owner answers `stops_enemy_rounds()`; still no self-damage). |
| nits | Rect row spawns at y 1150; spawned-on-player row asserts the hurt after arming. |

Debris scene detail fixed while drafting: the 64 px `debris_*.png` are drawn at `Sprite2D.scale` 0.5 (≈ 32 px) with a
contact circle r 12; damage 8.

## Revision 3 — answers to `4-review.md` round 2

| Finding | Change |
|---|---|
| **R2-M1** Sniper Shot damage depends on callback order | Decision: **cover stops the Sniper Shot and takes its full damage.** `bullet.gd`'s `unlimited_pierce` branch gains its own sub-branch, separate from the asteroid one: when the hurtbox's parent answers `stops_piercing() == true` the bullet emits `expired` and `queue_free()`s **without touching `HitBox.damage`**, so the hurtbox reads the full value whichever `area_entered` runs first (`queue_free` is deferred). The asteroid sub-branch is unchanged. Row `test_cover_stops_the_player_sniper_shot_and_takes_its_full_damage`: a `sniper_bullet.tscn` with `unlimited_pierce = true` set by the test ends on a medium wreck and the wreck's HP is exactly `200 − 50`. |
| **R2-m1** live drones in the sweep | Each sweep drone is added, then `suspend_ai()` **and** `set_physics_process(false)`; the row also asserts every drone's x is unchanged (only the wreck's push along y may move it — it does not, the drone is not depenetrating either). |
| **R2-n1** | The test sets `unlimited_pierce = true` itself (already in the draft). |
| nits | `HAZARD.md` states: the yield's depth cap is measured along the drift, so a near-sideways brush (> ~79° off the drift) can stop the wreck before it hurts; the "drifts off a ship it was born on" row uses a medium wreck (1.29 s; a large one needs 1.79 s); a wreck reads its mode in `_enter_tree()` from `EnemyWorld.arena()`, so in an Assault scene it must enter the tree after the `ArenaCamera` (a note for t18). |
