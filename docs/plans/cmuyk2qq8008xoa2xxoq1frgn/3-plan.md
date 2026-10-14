# t16 — the Ram Corvette's armour (task `cmuyk2qq8008xoa2xxoq1frgn`)

**Revision 2** (answers review round 1 in `4-review.md`; see "Response to review round 1" at the end). Builds epic plan `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (Revision 2) §2.6.1, §2.6.3, the ram
row of §2.7 (placeholders only) and the t16 row of §4. Context: `1-context.md`. The epic plan is approved, so this
plan only pins down what that text leaves open and names the tests. Plan-review findings applied: **B2** is already
built (t4's idempotent `ArmorPlate._resolve`), and this task relies on it for the volley rows; **N10** (the
side-plate inner edge must clear the outer warhead's 23 px lateral reach) is turned into scene geometry and a test
assertion. The other findings name other tasks.

## Problem

Today the Ram Ship/Corvette is bullet-proof by a collision-mask trick: its hurtbox does not even see the player's
bullets until the first rocket hits it, the player's Sniper Shot dies on it for 0, and after that one rocket it is a
100 HP ship. It flies straight down on a rail and is not in the `enemies` group, so homing rockets, the beam and the
ship modules treat it inconsistently.

After this task it wears **three visible armour plates** (front, left, right). Bullets glance off the plates and the
hull with a flash and keep flying (they are not used up). Each rocket knocks off exactly the plate it hits; a Sniper
Shot chips a plate and flies on. Only when all three plates are gone does the hull (120 HP) take damage from
anything — bullets, the beam, engine-boost contact. Touching an armoured Corvette hurts (50) and shoves the player
away; once exposed it hurts more (60) and no longer shoves. On rails (all of level 1 today) it plays exactly as
before apart from the armour rule. With the AI on (tests, later the hub and level 1) it intercepts the player and,
in Assault, leaves when its budget runs out; the charge itself is t17.

## Design

### Scene `ram_corvette.tscn` (rebuilt in place, root UID kept)

| Node | Type / script | Notes |
|---|---|---|
| `RamCorvette` | `CharacterBody2D`, `ram_corvette.gd` | Body layer 1 (default; it is what makes the beam's ray stop on it). `sprite_forward_angle` default `PI/2` (nose = local +y). |
| `Sprite2D` | `Sprite2D` | **Placeholder**: `ram_ship.png` (32 × 32, 67 % opaque), `rotation = PI` (the raw art points up), `scale 2.6` (≈ 84 px). Hit-flash `ShaderMaterial`. Named `Sprite2D` so `_rotate_sprite()` leaves it alone. t18 swaps the texture and drops rotation/scale. |
| `CollisionShape2D` | body `CircleShape2D` r **34** | The one shared SubResource. |
| `HurtBox` | `HurtBox` | Same SubResource and scale (1) as the body. Mask written by the **default** `DefenseProfile` (1121); the scene-authored `DefenseProfile` node is deleted. |
| `ContactHitBox` | `HitBox` (layer 256, **mask 128**, CONTACT) | Same SubResource and scale. Damage from config (50). Mask 128 (the player hurtbox) as on the Razor and Swarm drones: `ContactProfile` reaches `contact_made` and the shove only through this box's own `area_entered`, which never fires on mask 0 (review round 1, finding 1). |
| `ContactProfile` | `ContactProfile`, `mode = ARMOR` (4) | `shove_speed` set from config in `_apply_config`. |
| `Health` | `Health` | 120 from config. |
| `HitFlashAnimationPlayer` | tracks re-pointed at `Sprite2D:material:…` | |
| `Plates` | `Node2D` | Never a hurtbox at root level (the station's `Turrets` precedent). |
| `Plates/PlateFront` | `Node2D`, `armor_plate.gd` at (0, 36), rotation 0 | Authored children: `HurtBox` (512 / 96, empty types) with a `CapsuleShape2D` r 6, height 36, `CollisionShape2D.rotation = PI/2` (tangential); `Health` 50; `Sprite` (`Sprite2D`, no texture) with a `Polygon2D` child as the placeholder plate, so `set_glow` and `hide` reach it. |
| `Plates/PlateLeft` | same, at `(0, 36).rotated(-100°)` = (35.45, −6.25), rotation −100° | Capsule r 6, height 28. "Left" is the **ship's** left: the nose points to local +y, so the ship's left is local +x. |
| `Plates/PlateRight` | same, mirrored: (−35.45, −6.25), rotation +100° | |
| `EnemyMover` | `EnemyMover`, AUTO | |
| `Brain` | `RamCorvetteBrain` | |
| `StateLight` | `StateLight` at (0, −22) | OFF in this task; t17 drives it. |

**N10 geometry.** A frontal warhead volley's outer rockets reach ±(16 + 7) = ±23 px from the axis. A side plate's
inner lateral edge is 35.45 − (6 · cos 10° + 14 · sin 10°) ≈ 27.1 px, a 4 px margin; the front capsule spans
x ∈ [−18, 18], so the outer rockets do touch the front plate (whichever touches first breaks it; t4's resolver
lets the others pass). The test asserts the 23 px bound against the live scene's side-plate shapes, so moving a plate
inward fails a named assertion rather than a flaky volley row.

### `RamCorvetteConfig` (flat)

`max_health` 120, `collision_damage` 50, `score_value` 35 (kept), and new: `plate_health` 50,
`exposed_collision_damage` 60, `armor_shove_speed` 260.0, `cruise_speed` 280.0, `acceleration` 500.0,
`max_turn_rate` 2.2, `engage_seconds` 4.5, `exit_speed` 500.0. `movement_speed` (the legacy rail-less speed) is
removed; nothing else reads it. t17 appends the charge fields.

### `RamCorvette` (`ram_corvette.gd`)

- No `_physics_process` (the `BaseEnemy` brain/mover tick runs it). Joins **`enemies`**; never `ram_ships`.
- `_apply_config(cfg)`: health, score, contact damage, mover speeds, brain config, `contact_profile.shove_speed =
  cfg.armor_shove_speed`, each plate's `health.max_health/current_health = cfg.plate_health`.
- Connects every plate's `broken` → `_on_plate_broken(plate)` and `deflected` → `_on_plate_deflected(hit_box)` (flash).
- Signals: `armor_deflected(damage: int)`, `plate_broken(plate_name: StringName)`, `armor_broken`.
- `is_armored()` → `_armored`; `deflects_hit(_hb)` → `is_armored()`; `is_laser_blocking()` → `is_armored()`.
- `homing_point(from)` → the global position of the live plate nearest `from` (a plate counts only when `is_instance_valid` **and** `is_alive()`), else `global_position`.
- `live_plate_count()`.
- `_on_received_damage(damage)`: armoured → `armor_deflected.emit(damage)`, hit flash, return; else `super`.
- `_on_plate_broken(plate)`: `plate_broken.emit(plate.name)`; when the last one goes, `call_deferred("_expose")`.
- `_expose()` (idempotent: returns at once when already exposed): `_armored = false`; contact damage → `exposed_collision_damage`; `shove_speed` → 0;
  `armor_broken.emit()`.

**Why exposure is deferred (a decision the epic plan leaves open).** `HurtBox.received_damage` carries no hit, and
Godot gives no order between the plate's `area_entered` and the hull's. A rocket that breaks the **last** plate in
the same physics step it first overlaps the hull would, with an immediate flip, also deal its full damage to the hull
(the plate consumed it, so it must not count twice), and the hull's `deflects_hit` answer could flip mid-step. With
the flip deferred to the end of the step, everything the hull sees in the step the last plate dies is still a
deflection, and the next step sees an exposed hull. A boundary test pins it. `is_armored()` therefore reads true for
the rest of that step; nothing reads it across steps except the beam (one frame late, harmless).

**Not done here, on purpose.** The contact profile stays armed after `armor_broken` — the "disarm, arm only during
CHARGE" rule needs CHARGE and lands with it in t17. Glow, stagger, the exposed speed bump and evasion are t17.

### `RamCorvetteBrain` (minimal, `ram_corvette_brain.gd`)

The Bomber t9 shell's shape: `enum Phase { APPROACH, LINE_UP, WIND_UP, CHARGE, WIDE_TURN, DISENGAGE }` declared
in full so values never move (only APPROACH and DISENGAGE are implemented), `phase_changed(new_phase: int)`,
`enter_phase(p)` seam, `budget: EngagementBudget(config.engage_seconds)` built on the first tick.
- APPROACH: `mover.intercept(target, config.cruise_speed, INTERCEPT_LOOKAHEAD = 0.5)`; zero velocity with no target.
- Budget expiry → DISENGAGE: the shared nearest-edge exit at `exit_speed`, freed outside the world rect (copied
  from the Bomber, as every brain does).
- `on_suspended()`: light OFF. The rail fallback is the ARMOR profile itself (armed for life); nothing to fire.
- Requests only: its only writes on the mover are `max_speed` and `release_constraint()`.

### Outside changes

- `bullet.gd`: the `unlimited_pierce` branch drops `or parent.is_in_group("ram_ships")` (X4); comment updated.
- `engine_boost_module.gd`: `RamCorvette` removed from `_IMMUNE_CLASSES`; class comment and `get_description()`
  say the Corvette's armour deflects boost damage until its plates are gone. `emp_blast_module.gd` unchanged.
- `defense_profile.gd` / `base_enemy.gd`: comments no longer name the ram as the `apply_alternate()` user (X2: it
  has no shipped user now) or as the "first hit arms it" example.
- `station_reinforcements.gd` / `test_station_reinforcements.gd` case 16: comment-only — the Corvette's mask is the
  default 1121 now; the assertion stays as a generic guard.
- `tests/unit/test_defense_profile.gd`: the scene-authored-profile case builds on `tests/helpers/fixture_enemy.tscn`
  with a `DefenseProfile` child added before `_ready()`; the alternate cases' "ram ship's shape" comment becomes a
  plain example.
- `tests/integration/test_base_enemy.gd`: exactly the edits the task lists (constants and ram branch removed, three
  ram cases retired, `ram_corvette` kept in `_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW` with the reason "its hull deflects
  every hit while a plate lives, like the station's core", dropped from the flip list and its boundary skip,
  `_AUTHORED_CONTACT_MODES` gains `ram_corvette: ARMOR`). Still no static `RamCorvette` reference there.
- `tests/integration/test_player_bullet_lifetime.gd`: plate rows (below); the asteroid case's comment loses
  "or ram-ship".

## Build sequence

1. Config + scene + `ram_corvette.gd` + minimal brain (with the new `test_ram_corvette.gd` written first, red).
2. Outside changes (bullet, engine boost, comments, defense-profile fixture, base-enemy edits).
3. `test_player_bullet_lifetime.gd` plate rows; dual-mode pair in `test_enemy_dual_mode.gd`.
4. Full gate + `scripts/check-test-leaks.sh`; `ram_corvette/ENEMY.md` rewritten; DECISIONS line for the deferred
   exposure and the removed `movement_speed`.

## Test plan

`tests/integration/test_ram_corvette.gd` (replaces the legacy file; INTENT). Real-physics cases are parameterised
over `["open_space", "assault"]` on `tests/helpers/enemy_ai_harness.gd` worlds, with the Corvette's physics tick
off (stationary, brain not ticking) so the projectiles, not the AI, are under test. Signal counts use connected
counters (a broken plate frees itself; GUT's watchers crash on it).

1. **Scene and config.** Body r 34 shared (same SubResource) by `HurtBox` and `ContactHitBox`; root hurtbox mask
   1121; three `ArmorPlate`s under `Plates`, none a direct root child; HP 120, contact 50, plate HP 50, shove 260
   from config; `ContactProfile` ARMOR and armed at spawn; group `enemies`, not `ram_ships`; no `DefenseProfile`
   authored. **N10: every side plate's shape AABB in the Corvette's frame keeps |x| > the outer warheads' reach, derived as the volley's 16 px outer offset + the warhead scene's own capsule radius (asserted to be 23); `PlateLeft` sits on +x and `PlateRight` on −x.**
2. **Bullets glance off (dual).** A real default bullet fired at the hull centre from the side, and one at each plate
   from outside it: hull HP and every plate's HP unchanged, `armor_deflected` emitted, every bullet still alive and
   not expired.
3. **Each rocket breaks exactly the plate it hits (dual).** Real warheads: from the front (below, flying up) → only
   `PlateFront` breaks; from the ship's left (+x, flying −x at the side plates' y) → only `PlateLeft`; **the mirror (−x, flying +x) → only `PlateRight`**; **from the rear
   (above, flying down the axis) → it crosses the deflecting hull and breaks `PlateFront` from inside**. Each rocket
   consumed, hull HP unchanged, `plate_broken` carries the plate's name.
4. **Plate-by-plate vulnerability (dual).** Warheads break the plates one at a time. After each of the first two, a
   real bullet at the hull deals 0 and is not consumed and `is_armored()` is true. **After the third (one frame
   later) `is_armored()` is false, `armor_broken` fired once, and a bullet at the hull reduces HP by exactly its
   damage and is consumed.**
5. **Deferred exposure boundary.** With two plates gone, in one synchronous block: the last plate resolves a ROCKET
   hitbox, then the hull emits `received_damage(100)` → HP unchanged, deflected; after one process frame
   `is_armored()` is false and a further `received_damage(30)` lands.
6. **Homing volley (dual).** A real `RocketState` (actor 300 px below, `CooldownTimer`, a `MovementController`
   stub not in the tree) calls `_launch_homing()`: within 3 s all three plates are broken, all three rockets are
   consumed, hull HP is still 120, and the Corvette is exposed.
7. **Frontal warhead volley (dual).** The same state, `_launch_warhead()` with the actor facing the nose: only
   `PlateFront` breaks, exactly one rocket is consumed, both side plates are alive at full HP.
8. **Sniper Shot (dual).** A real `sniper_bullet.tscn` with `unlimited_pierce` and the real `sniper_shot.tres`
   damage (40) fired up the axis: `PlateFront` loses 40, the hull loses 0, the shot is alive past the Corvette.
   Exposed (plates broken by warheads first): the hull loses 40 and the shot still flies on.
9. **Beam (dual).** `BeamDriver` (the station suite's) below the Corvette with the real `mining_laser.tres`, 40
   frames: armoured → endpoint stops at the hull (not full length) and HP unchanged; exposed → full length and HP
   lower.
10. **Engine boost and EMP.** `EngineBoostModule._damage_nearby_enemies(player)` with a player node 10 px away:
    armoured → HP unchanged and `armor_deflected`; exposed → HP −45, from a **fresh** module (one instance remembers
    every enemy it hit in `_hit_this_boost` and would skip the Corvette for the wrong reason). `EMPBlastModule._is_immune(ram)` is true;
    `EngineBoostModule._is_immune(ram)` is false.
11. **Contact, end to end (dual).** A real player HurtBox/Health pair (layer 128, mask 1281) on a root that records
    `apply_knockback` calls, placed overlapping the Corvette: armoured → it takes 50, `contact_made` fires once, exactly
    one `apply_knockback` of length `armor_shove_speed` (260) pointing away from the hull, and the Corvette loses
    nothing. Exposed → a second such player takes 60 and gets **no** `apply_knockback`. Run once with the
    `ContactHitBox` mask set back to 0 to show the row fails (it does: `contact_made` 0, shoves 0).
12. **`homing_point`.** From below → `PlateFront`'s position; with `PlateFront` broken, from below-left → the nearer
    side plate; with none → `global_position`.
13. **Rails.** `suspend_ai()` leaves the ARMOR profile armed and the brain idle (no velocity after ticks).

`tests/integration/test_enemy_dual_mode.gd`: **APPROACH mid-corridor identical in both modes**; **DISENGAGE frees it
in Assault only** (budget 0.2 s), the Bomber pair's shape.

`tests/integration/test_player_bullet_lifetime.gd` plate rows: a bullet launched through `StraightBehavior` across a
live `ArmorPlate` (on the real Corvette) is not consumed and spends no pierce charge; launched at the exposed hull it
is consumed; **an `unlimited_pierce` bullet crossing an armoured Corvette is not stopped (the `ram_ships` rule is
gone) and the asteroid rule still stops one**.

Gates expected green unedited except as listed: contact damage (reads 50), contact geometry (shared SubResource),
hurtbox geometry (one direct-child HurtBox covering r 34), config isolation (flat), single writer (empty allowlist),
signal arity, sprite transparency (ram_ship.png 67 %; plate sprites have no texture), UID / project-load integrity,
collision layer names (512, 96, 256 already named). `scripts/check-test-leaks.sh` clean.

## Risks

- **Volley rows depend on real physics timing.** Mitigated by the idempotent resolver (B2), generous frame budgets
  and asserting outcomes (which plates broke, how many rockets were consumed), never frame numbers.
- **Homing tie-break.** After the front plate breaks, both side plates can be equidistant; whichever each rocket picks,
  three rockets and three plates still strip the hull. The assertion is on the outcome only.
- **A homing rocket beyond the third** (upgraded `homing_count`) that is already inside the hull when the last plate
  breaks parks at the centre: `homing_point` falls back to `global_position` and the hull's `area_entered` has already
  fired. Out of scope; recorded as a follow-up.
- **Level 1 is on rails** and unaffected apart from the armour rule (bullets no longer vanish on it; rockets strip
  plates one at a time). Kill difficulty rises for warhead users — owner question §8.6 of the epic plan.

## Out of scope

LINE_UP / WIND_UP / CHARGE / WIDE_TURN, glow wiring, stagger, exposed speed/evasion, the ARMOR disarm rule after
exposure, the Assault diagonal (t17); art (t18); hub idle (t19/t20); level-1 migration (t21/t22); docs beyond
`ENEMY.md` and the DECISIONS line (t23).

## Response to review round 1

| Finding | Response |
|---|---|
| 1 (BLOCKING) shove can never fire on mask 0 | Fixed: `ContactHitBox.collision_mask = 128`. Row 11 is now end to end in both harnesses (`contact_made`, one 260 px/s `apply_knockback` away from the hull, 50 damage; exposed: 60 and no shove). Verified red on mask 0, green on 128. |
| 2 engine boost reuses one module | Already a fresh module per phase; now stated in row 10. |
| 3 mirror side unchecked | Row 3 gains the mirrored `PlateRight` row; row 1 asserts the signs of the side plates' x. |
| 4 N10 bound a bare 23 | Derived from the warhead scene's capsule radius + the volley's 16 px offset (sanity-asserted = 23). |
| 5 station case 16 | `station_reinforcements.gd`'s comment keeps "don't use the ram here", restated: its hull deflects bullets until rockets strip its plates. Case 16's assertion is unchanged (the task says comment-only; the station suites stay unedited apart from that comment). |
| 6 docs now false | `global.md` (DefenseProfile / `apply_alternate`) and `enemy-roster.md` (the `ram` entry and the squad-table note) are updated in this task. |
| 7 test floor | `_MIN_ROSTER_SIZE - 1` (done). |
| 8 details | `homing_point` checks `is_instance_valid` and `is_alive()`; `_expose()` is idempotent; row 6's `RocketState` and actor live under the autofreed harness root and the `MovementController` stub is `autofree`d. |
| 9 process | Noted. The earlier run's notes said implementation waits for approval; this run drafted code while the review ran. Nothing is committed before an APPROVED verdict, and every finding above is applied to the draft. |
