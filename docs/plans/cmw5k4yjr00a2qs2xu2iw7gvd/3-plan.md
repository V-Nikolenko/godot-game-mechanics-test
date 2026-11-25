# Phase 9 t4 — the seeking-ordnance retarget hook and the hijacked homing rocket

Task plan for `cmw5k4yjr00a2qs2xu2iw7gvd`. The approved design is the epic plan's §2.5 (`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md`); this plan
does not redesign it. It fixes the choices §2.5 leaves open (marked **Choice**), resolves one contradiction inside it (marked **Resolution**) and orders the work.
Context: `1-context.md` in this directory.

## Problem

Phase 9's Hacker Frigate (t8) turns the player's homing rockets against the player. Before any Hacker exists, the rocket itself needs a contract a claimer can call and a
"hijacked" flight mode that is readable and fair: today a homing rocket can only fly at its `locked_target` (instant turns, 500 px/s, 100 damage on whatever it touches)
or straight. The player must be able to see a claimed rocket (amber, a target bracket, a brief tether to the claimer), dodge it (it turns slowly and slows down), shoot it
down with one bullet, lure it into an enemy (full damage there), and survive a hit (a small 18-damage blast, never the 100-damage impact). Player rockets must never shoot
each other down, and inside a lit jammer field every seeker flies straight.

## Design

### `global/components/seeking_ordnance.gd` (new)
`class_name SeekingOrdnance extends RefCounted`; `const GROUP := &"player_seeking_ordnance"`;
`static func eligible(tree: SceneTree, at: Vector2, reach: float) -> Array[Node2D]`: every node of `GROUP` that is a valid, in-tree `Node2D` within `reach` of `at`
(centre distance `<=`) answering `can_be_retargeted() == true` (duck-typed via `has_method`), sorted by distance, ties by `get_instance_id()`. Null tree → empty.

### `homing_missile.gd` / `.tscn`
**Scene additions** (all hijack tuning as exports, values set on the scene):
`hijack_speed` 380, `hijack_turn_rate` 1.6, `hijack_seconds` 2.5, `hijack_ease_seconds` 0.5 (the "eases over the first 0.5 s"), `hijack_blast_damage` 18,
`hijack_blast_radius` 40, `hijack_blast_frames` 3, `hijack_trigger_radius` 30, `hijack_arm_seconds` 0.25, `hijack_arm_clearance` 60, `tether_seconds` 0.3.
New child `HurtBox` (`hurtbox_component.gd`, layer 512, mask 64, `monitoring` / `monitorable` false, a 7 px `CircleShape2D`). New child `Pop` (`ExplosionEffect`, small
amber burst — the `pursuit_rocket.tscn` pattern). Script ext_resources added UID-less (legal; never hand-type a `uid://`).

**Contract** (joins `SeekingOrdnance.GROUP` in `_ready()`):
- `signal retargeted(source: Node)`, `signal retarget_ended()`.
- `can_be_retargeted() -> bool`: false once claimed (a latch: a rocket is claimed at most once), once done, outside the tree, or while
  `Hazards.count() > 0 and Hazards.jammer_at(global_position) != null`.
- `retarget(target: Node2D, seconds: float, source: Node) -> bool`: false (no state change) for an invalid `target` or `not can_be_retargeted()`. Otherwise:
  `_hijack_left = seconds if seconds >= 0.0 else hijack_seconds`; target / source stored; `_had_source = source != null`; `_since_claim = 0`;
  `_heading = Vector2.UP.rotated(rotation)` (heading kept); `_cleared` = distance to target ≥ `hijack_arm_clearance` now; `locked_target = null`;
  `_tether_left = tether_seconds`; tell on; HurtBox `monitoring` / `monitorable` on **deferred** (a claim can come from a physics callback); emits
  `retargeted(source)` then `EventBus.player_ordnance_hijacked(self, source)`; returns true.
- `is_retargeted() -> bool`: hijacked and not done.
- `jam_guidance(_source: Node) -> void`: `locked_target = null`; if hijacked, `_guidance_jammed = true` (straight until its window ends).
- `is_tether_visible() -> bool`: `_tether_left > 0`, not done, source still valid.

**Normal flight** unchanged except: with a `locked_target` and `Hazards.count() > 0 and Hazards.jammer_at(global_position) != null` → `_fly_forward(delta)`.

**Hijacked flight** (`_physics_process` → `_hijack_step(delta)` while hijacked), in this order:
1. `_had_source and not is_instance_valid(_hijack_source)` → `_finish(false)`, return (source death; **Choice:** a claim with a null source has no source to lose).
2. Clocks: `_since_claim += delta`; `_hijack_left -= delta`; `_tether_left -= delta` (0 once `<= 1e-6`).
3. Speed: `lerpf(speed, hijack_speed, clampf(_since_claim / hijack_ease_seconds, 0, 1))` — 500 → 380 over 0.5 s, then exactly 380.
4. Heading: `Steering.turn_toward(_heading, target_pos - global_position, hijack_turn_rate, delta)` unless the target is gone (`not is_instance_valid(_hijack_target)`),
   guidance was jammed, or `Hazards.jammer_at(global_position)` is set; then `Hazards.bend_heading(...)` when `Hazards.count() > 0`.
5. Move, `rotation = _heading.angle() + PI / 2`.
6. Arming / blast, **only while `is_instance_valid(_hijack_target)`** (review M2: the target is the player, which can be freed mid-hijack; a rocket with no target flies
   straight and fizzles at the end of its window): distance to the target centre `d`; `d >= hijack_arm_clearance` latches `_cleared`; armed = `_since_claim >= hijack_arm_seconds - 1e-6 and _cleared`;
   armed and `d <= hijack_trigger_radius` → `ContactBlast.spawn(get_parent(), global_position, hijack_blast_radius, hijack_blast_damage, hijack_blast_frames)`, `_finish(true)`, return.
7. `_hijack_left <= 1e-6` → `_finish(false)` (fizzle), return.
8. `queue_redraw()`.

**One end of life, `_finish(blasted: bool)`:** `if _done: return`; `_done = true`; if it was hijacked → pop and `retarget_ended.emit()`; close the HitBox and HurtBox
deferred (`monitoring` / `monitorable` off, shapes disabled — the `EnemyRocket._mark_done()` pattern); `hide()`; `expired` once through the lifetime's own latch
(`_lifetime.expire_now()`, skipped when `expired` is what called us) and the lifetime's physics off; `queue_free()`.
Callers: the blast, the fizzle, source death, the shoot-down (`HurtBox.received_damage` while hijacked), a non-deflected hit on anything (`_on_hit_box_area_entered`),
and the `ProjectileLifetime` backstop (`_on_expired()` = `if not _done: _finish(false)`), so a hijack that `max_time` ends still emits `retarget_ended`.

**Resolution — `queue_free()` at the end of the frame, not two physics ticks later.** §2.5 asks for the `EnemyRocket` two-tick delay *and* says t3's rows stay
green. They cannot both hold: `test_homing_missile_lifetime.gd`'s 6.0 s row times the free (tick 360 ± 1.5) and `test_player_bullet_lifetime.gd`'s ownership row asserts
`is_queued_for_deletion()` right after `expired`. The delay exists in `EnemyRocket` only because a **pool** re-parents the rocket and `Area2D` then re-reports a live pair;
the homing rocket is never pooled, so a deferred `queue_free()` already removes it (and its pairs) at the end of the frame. The areas are still closed deferred and `_done`
latches first, so nothing in the same flush runs `_finish` twice. Logged in `DECISIONS.md`.

**Choice — the pop only on a hijacked rocket's end.** An unhijacked rocket's ends keep today's observable behaviour exactly (no pop; freed), per §2.5's last line.

**Collisions — the self-hit guard.** `_on_hit_box_area_entered(area)` starts `if _done or _is_player_homing(area.get_parent()): return`, before `ArmorQuery`.
**Choice:** `_is_player_homing(node)` is `node != null and node.get_script() == get_script()`, so `homing_missile.gd` does not name its own `class_name`. This is a
**precaution, not a known leak** (review M5): `enemy_mine.gd`'s self-reference leaked at exit, but `enemy_rocket.gd` names `EnemyRocket` four times with a leak-free gate, so
there is no general self-reference rule; `DECISIONS.md` records it that way. No subclass of `homing_missile` exists, so script identity and `is` agree. `warhead_missile.gd::_on_hit_box_area_entered` starts with
`if area.get_parent() is homing_missile: return` (a cross-reference, not a cycle).

**Shoot-down:** `HurtBox.received_damage` → `_on_shot_down(_damage)` → `_finish(false)` if hijacked. An unhijacked rocket's HurtBox is closed, so a bullet passes.

**Tell** (IDEAS §21): the `AnimatedSprite2D` `self_modulate` → `Color(1.0, 0.7, 0.3)`; the trail turns amber through a new `RocketTrail.set_colors(birth, death)`
(rewrites the particles' ramp; colours set before `_ready()` are used when it builds) with a read-back `birth_color() -> Color` for the test; `_draw()` draws the target bracket (four 4 px corner ticks on a ring of r 12, spinning at 3 rad/s) while
hijacked and, while `is_tether_visible()`, a line from the source to the rocket (white → amber, alpha fading over `tether_seconds`), computed with `to_local()`.

### `warhead_missile.gd`
Only the guard above.

### `global/components/rocket_trail.gd`
`set_colors(birth: Color, death: Color) -> void` and `birth_color() -> Color`. Nothing else changes; the default ramp is unchanged.

## Revision 2 (after review round 1)
Added R1–R3 and M2–M4 rows to the test plan, the M2 target guard in steps 4 and 6, the M1 / M6 risks and the M5 rationale. No design change.

## As built (implementation notes)
- **The salvo self-hit row could not fail on its own** (measured on Godot 4.6): an area that turns monitorable while it already overlaps another forms no pair, so a claimed rocket never meets its own HitBox or its mates' on the claim tick. The crossing row is the real-physics falsifier of both guards; the salvo row also hands each HitBox callback the claimed HurtBox directly. Logged in DECISIONS.md.
- The speed row reads speed back from single-precision positions, so its tolerance is 1e-2 px/s (1e-3 failed on float32 rounding, not behaviour).
- The clearance row ends at tick 30 (round-2 review: its "player stops" tail could not fail).

## Build sequence
1. **Tests first:** `tests/integration/test_seeking_ordnance.gd` with every row below; run it, watch it fail (missing API).
2. `seeking_ordnance.gd`; `RocketTrail.set_colors`.
3. `homing_missile.tscn` (exports, `HurtBox`, `Pop`) and `homing_missile.gd` (contract, hijacked flight, `_finish`, guard, tell, jammed seekers).
4. `warhead_missile.gd` guard.
5. Run the new file; then prove the two guard rows can fail (remove each guard, run, restore) and record it.
6. Regression files: `test_homing_missile_lifetime.gd`, `test_player_bullet_lifetime.gd`, `test_enemy_rockets.gd`, `test_armor_query.gd`, `test_hazard_projectiles.gd`,
   `test_ram_corvette.gd`, `test_enemy_shield_hits.gd`, `test_station_incoming_damage_paths.gd`, `test_collision_layer_names.gd`, `test_signal_emit_arity.gd`,
   `test_project_load_integrity.gd`, `test_resource_uid_integrity.gd`.
7. `scripts/gate-time.sh` after (before measured at the start: same script), `scripts/check-test-leaks.sh` (the new file awaits), `bash /agent/verify.sh`.
8. Docs (`updating-project-docs`): `CLAUDE.md`, `PROJECT.md` Conventions, `global.md` (`SeekingOrdnance`, `RocketTrail.set_colors`), `DECISIONS.md` "Phase 9, built in t4",
   `tests/README.md` gate-time row.

## Test plan — `tests/integration/test_seeking_ordnance.gd`
Hand-ticked rows run in both harnesses (`enemy_ai_harness.gd`, label-parameterised): the rocket's and its lifetime's physics off, `r._physics_process(DT)` then
`lifetime._physics_process(DT)` at 1/60. The claimer is a fixture `Node2D` (an inner class whose `claim(reach, cap)` calls `SeekingOrdnance.eligible()` then
`retarget(player, -1.0, self)`). A `ContactBlast` is counted by watching `child_entered_tree` on the world and awaiting one idle frame (its attach is deferred).
Real-physics rows run at the 8× clock (the `test_enemy_rockets.gd` `_scale_clock()` shape).

| Row | Asserts (boundary / falsifier in brackets) |
|---|---|
| Group / eligibility | homing rocket in `GROUP`, warhead not; `eligible()` sorted by distance, ties by id; drops a hijacked rocket, one inside a lit jammer and one beyond `reach` [one exactly at `reach` is kept]; `retarget()` refused (false, no signal, no EventBus emit) for each of those and for a null target; a refused claim leaves the rocket flying as before |
| In-flight turn | rocket flying directly away from the player, claimed: per-tick heading change ≤ `hijack_turn_rate · DT + 1e-4` on every tick; points at the player (≤ 0.05 rad) before 2.5 s [control: the turn is non-zero, i.e. it does steer] |
| Speed | per-tick displacement / DT: 500 → 380 by tick 30 (monotone), then 380 ± 1e-3 |
| Blast only (real players, both modes, real physics) | claimed 300 px away heading at the player: exactly one `received_damage(18)`, HP − 18, never 100; a second rocket with one shield charge: the charge is spent, HP unchanged |
| Arming — time rule (review R1) | claimed 70 px from a stationary target, nose on it (`_cleared` latches on the claim, `d <= 30` from about tick 5): no blast on ticks 1..15; on tick 15 it is ~47 px past the target [a clearance-only build blasts on about tick 5] |
| Arming — clearance rule (review R1) | claimed 20 px out; each tick the fake player is moved to 20 px behind the rocket (the player chasing its own just-claimed rocket): no blast through tick 30 though `_since_claim >= 0.25` from tick 15 [a time-only build blasts on tick 15]; then the player stops: any later blast comes only after a tick with `d >= 60` |
| Arming — on the ship | claimed at 0 px on the ship: no blast in its first 0.25 s |
| Fizzle | target out of reach: `retarget_ended` and `expired` once each on tick 150 ± 1, no `ContactBlast`, freed |
| Window from the claimer (review R3) | `retarget(target, 1.0, src)` fizzles on tick 60 ± 1; `retarget(target, 0.0, src)` fizzles on its first tick; no blast in either [a build that ignores `seconds` fizzles both on tick 150] |
| Null source (review M3) | a claim with `source = null` is accepted and lasts its whole window (fizzle on tick 150 ± 1, not tick 1) |
| Target freed (review M2) | the target freed on tick 20 of a hijack: no error logged, the heading is constant from tick 21, fizzle on tick 150 ± 1, no blast |
| `jam_guidance()` (review R2) | unhijacked rocket with a `locked_target`: after `jam_guidance(null)` `locked_target == null` and the heading is constant over 30 ticks; hijacked rocket, `jam_guidance(src)` on tick 10: heading constant from tick 10 to the end of the window, `retarget_ended` once on tick 150 ± 1, no blast, still `is_retargeted()` until then; control: the same rocket without the call turns |
| Source death | claimer freed: the next tick fizzles (`retarget_ended` once, no blast); no error logged |
| Lure (real physics) | a hijacked rocket crossing `fixture_enemy.tscn` (+ 14 px HurtBox, in `enemies`) on its way to the player: the enemy loses exactly 100, the rocket ends (`retarget_ended`), no `ContactBlast` |
| Shoot-down (real physics) | one real `Bullet` into a hijacked rocket: the rocket ends with no blast, the bullet is consumed; the same bullet line through an unhijacked rocket: both fly on (HurtBox inert) |
| Self-hit guard (real physics, real `RocketState` salvo) | middle rocket of a 3-salvo claimed: all three valid and not queued at 2, 10 and 30 physics frames after the claim; the claimed HurtBox monitorable [fails without the homing guard — proved once by removing it] |
| Crossing guard (real physics, `RocketState` homing + warhead salvos) | a hijacked rocket flown head-on through a fresh homing salvo and a warhead salvo: all alive 10 frames after the crossing, its HurtBox still monitorable [fails without either guard — proved once each] |
| Lifetime ends a hijack | hovering on a hurtbox-less static `Node2D` for 300 ticks, player ≥ 700 px away, then claimed: `expired` on tick 360 ± 1 with `retarget_ended` once, no blast, freed, still inside the Assault rect; control: an unhijacked hover to tick 360 emits no `retarget_ended` |
| Tether | `is_tether_visible()` true for ticks 1..17, false from tick 18 (0.3 s, the 1e-6 rule); claimer freed at tick 5 → false on tick 6 (and the rocket fizzles) with no error |
| Jammed | in a lit jammer: a hijacked rocket's heading constant over 30 ticks; an unhijacked rocket with a `locked_target` flies straight; [outside the field both turn] |
| Dodge | Open Space: cruising 420 px/s perpendicular to a rocket claimed 400 px away heading at the ship, a 90° turn at 0.6 s: never blasted. Assault: strafing 360 px/s across a claim 500 px above, one reversal: never blasted. Control (both): stationary is blasted. Exact turn / reversal timing fixed by a pre-run of the flight model and written in the row |
| Primary fire during a hijack (both real ships) | lockstep `WeaponState` over 120 ticks for every `UpgradeState.ALL_IDS` mode: ship B with a hijacked rocket in flight (claimed on B) logs the same shots, cadence and damage as ship A without [non-vacuous: A fired] |
| EventBus | `player_ordnance_hijacked` once per successful claim with (rocket, source); never on a refused claim |
| Tell (review M4) | before: sprite white, HurtBox closed; after `retarget()` and **one awaited idle frame** (the HurtBox opens deferred): sprite `self_modulate` amber, HurtBox monitoring / monitorable, the trail's `birth_color()` amber (pins `RocketTrail.set_colors`) |

## Risks
- **The dodge rows are geometry-sensitive.** If a plan number (380 px/s, 1.6 rad/s, 30 px) makes a fair dodge fail, the number is a *starting value*: change the least
  number that makes the row pass and log it in `DECISIONS.md`. The pre-run fixes the scenario first, not the number.
- **Gate time** (2.5 s allotment): real-physics rows at 8× (~5 game s in total) plus hand-ticked rows. Share scenarios (one salvo scene, one crossing scene) before cutting anything.
- An `EnemyRocket` meeting a hijacked rocket's HurtBox detonates (both end) — accepted in §2.5.
- The `ally fighter`'s CONTACT ram box (layer 64) also shoots a hijacked rocket down. Accepted: it is a player-side hitbox.
- **Other things that destroy a hijacked rocket (review M1), accepted:** a `LaserRay` with the default `_HIT_MASK` (128 | 256 | 512: level 1's laser columns and every ray of
  `laser_wall.tscn`) emits `received_damage(_KILL_DAMAGE)` on any HurtBox it meets, so a lit column kills a hijacked rocket (`_on_shot_down`); so does a reflected `EnemyBullet`
  (layer 64). Lasers kill everything; the station laser phase overrides the mask and does not. Recorded in `DECISIONS.md` so t8 / t14 (a Hacker in level 1) are not surprised.
- **For t8 (review M6), recorded in `DECISIONS.md`:** the rockets are children of `RocketState`, so a rocket freed with its player (any parent free) never reaches `_finish` and
  emits no `retarget_ended`; a Hacker counting its claims must also check `is_instance_valid`. Beam primaries (`mining_laser`, target by group) can never shoot a hijacked
  rocket down — a t9 fairness note.

## Out of scope
The Hacker, its dart and pulse (t8), EMP routing and `TARGET_SEEKERS` (t5 calls `jam_guidance`), `EnemyRocket` jamming (t5/t7), audio (Ph17).
