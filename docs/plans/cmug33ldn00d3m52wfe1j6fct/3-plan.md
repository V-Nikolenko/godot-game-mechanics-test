# EnemyBrain + EnemyMover: enemies run their own AI on physics, rails still override it

Task `cmug33ldn00d3m52wfe1j6fct` (epic t10-brain-mover). Implements epic plan
`docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md` §2.2, §2.3, §2.4, §2.10 (`suspend_ai`), P-9, P-10, applying
epic review round 2's N2 (sweep shape). It does not re-derive the epic design; it fixes the details the epic
plan left to this task. Context: `1-context.md`.

## Problem

For the player: nothing changes in this task. Every Assault wave, the race and Open Space play exactly as
today. What changes is that an enemy can now *want* something and *get there*: a brain decides once per
physics frame, and a mover turns that decision into the one velocity/facing write. Rail-driven spawns
(264 of 268) keep overriding it, now through a contract instead of only by node name. The ported Drone
Interceptor (t14) is the first real consumer; here only a test fixture uses it.

## Revision 2 (after review round 1)
R1 arrive/hold use the deceleration rate; R2 wrapper tests; R3 exact 1/64 steps; R4 sweep covers `velocity.x`,
`look_at`, `rotate`; R5 non-zero-velocity inert case; non-blocking notes folded in (sniper list, process delta,
exact frame count, get_state root lookup, no copied ids, DECISIONS note).

## Design

### Files
| New / changed | Path |
|---|---|
| `EnemyBrain` | `global/enemy_ai/enemy_brain.gd` (new) |
| `EnemyMover` | `global/enemy_ai/enemy_mover.gd` (new) |
| `MovementConstraint` | `global/enemy_ai/movement_constraint.gd` (new) |
| `BaseEnemy` | `assault/scenes/enemies/base_enemy.gd` (tick + `suspend_ai()`) |
| `EnemyPathMover` | `assault/scenes/enemies/enemy_path_mover.gd` (one added call) |
| fixture | `tests/helpers/fixture_enemy.tscn`, `fixture_enemy.gd`, `fixture_brain.gd` (no `class_name`) |
| tests | `tests/unit/test_enemy_mover.gd`, `tests/integration/test_enemy_brain_contract.gd`, `tests/integration/test_enemy_mover_single_writer.gd` |

### `MovementConstraint` (RefCounted)
`func filter(_position: Vector2, desired: Vector2) -> Vector2: return desired`. Identity. t11 subclasses it.

### `EnemyBrain` (Node)
```gdscript
class_name EnemyBrain extends Node
@export var rng_seed: int = 0          # 0 = randomize() in _ready; non-zero = rng.seed = rng_seed
var actor: CharacterBody2D             # get_parent() as CharacterBody2D (F11: not BaseEnemy)
var mover: EnemyMover                  # first sibling that `is EnemyMover`, or null
var attack: AttackController           # first sibling that `is AttackController`, or null
var rng := RandomNumberGenerator.new()
func tick(_delta: float) -> void: pass  # virtual; called by the owner's physics tick
func on_suspended() -> void: pass       # virtual; called once by BaseEnemy.suspend_ai()
```
- Resolution happens in the brain's own `_ready()` (children are ready before the parent, and the siblings
  already exist in an instantiated scene). A bare `EnemyBrain.new()` with no parent resolves nulls, logs
  nothing. Concrete brains overriding `_ready()` must call `super._ready()` (documented).
- The header documents IDEAS §4's vocabulary (SPAWN, SEARCH, APPROACH, POSITION, ATTACK, EVADE, REPOSITION,
  DISENGAGE, PANIC, DESTROYED) as names, not an enforced enum; the rule that brains keep clocks as accumulated
  `delta` and draw randomness only from `rng`; that perception goes through `TargetInfo`; and that a brain never
  writes `actor.velocity`/`rotation` or calls `move_and_slide()` (the single-writer gate).
- No signals (nothing to declare).

### `EnemyMover` (Node)
Exports (all "0 = off/instant" so an unconfigured mover is a pass-through):

| Export | Default | Meaning |
|---|---|---|
| `max_speed` | 0.0 | cap on the non-boost velocity; 0 = uncapped |
| `acceleration` | 0.0 | px/s² cap on the velocity change when speeding up; 0 = instant |
| `braking` | 0.0 | px/s² cap when the desired speed is below the current speed; 0 = same as `acceleration` |
| `turn_lerp` | 0.0 | `lerp_angle` factor per second; 0 = snap to target |
| `max_turn_rate` | 0.0 | rad/s cap on the rotation change per step (IDEAS §3.1 `turn_rate`); 0 = off |
| `constraint_mode` | `AUTO` | `enum ConstraintMode { AUTO, NONE }` |

State: `var actor: CharacterBody2D`, `var constraint: MovementConstraint` (public; injected before
`add_child` wins).

Request API (the brain calls these inside `tick`; all requests are **per step** — cleared at the end of each
`step()`, so a brain that stops requesting decelerates to zero at `braking`):
- `request_velocity(v)` — the one primary request; a second call in the same tick **replaces** the first.
- Wrappers that call `request_velocity(Steering.x(actor.global_position, …))`: `seek(target, speed)`,
  `arrive(target, speed)` (uses `actor.velocity` and the mover's **deceleration** `_decel() = braking if braking > 0 else acceleration` — the slowing radius must match the rate the mover actually slows at; review R1), `orbit(center, radius, angle,
  max_correct_speed)`, `intercept(target: TargetInfo, speed, lookahead)`, `retreat_from(threat, speed)`,
  `evade(threat_pos, threat_vel, speed, lookahead)`, `strafe(target, side, speed)`, `hold_position(anchor,
  tolerance, speed)` (uses `_decel()`), `drift(direction, speed)`. No steering maths lives in the mover.
- `add_nudge(v)` — offered, additive; summed onto the primary before limits.
- `face_toward(point)` — explicit heading for this step; otherwise the heading is the commanded velocity.
- `boost(dir, speed, duration)` — for `duration` seconds the desired velocity is `dir.normalized() * speed`,
  ignoring the primary, nudges, `max_speed` and the accel/braking limits (the constraint still applies).
  `is_boosting()`. A new `boost()` replaces the current one.
- `halt()` — zeroes `actor.velocity`, clears requests and any boost. Used by `BaseEnemy.suspend_ai()` (N2:
  the zeroing goes through the mover, so the mover stays the only velocity writer).

`step(delta)` (called only by the owner's physics tick), in order:
1. No-op if `actor == null` (bad parent / bare).
2. `desired` = boost velocity if boosting, else `primary + Σnudges`, capped at `max_speed` if > 0.
3. Limits (skipped while boosting): `rate = braking if (desired.length() < actor.velocity.length() and
   braking > 0) else acceleration`; `v = actor.velocity.move_toward(desired, rate * delta)` if `rate > 0`,
   else `v = desired`.
4. `v = constraint.filter(actor.global_position, v)` if a constraint is set.
5. `actor.velocity = v; actor.move_and_slide()` — the only `move_and_slide()` in the AI stack.
6. Facing — the one rule: `heading` = the face_toward direction if requested, else `v`. If
   `heading.length_squared() > 1e-6`: `target = heading.angle() - _sprite_forward_angle()` where
   `_sprite_forward_angle()` is `actor.get("sprite_forward_angle")` if it is a float/int, else `PI/2`.
   `r = target if turn_lerp <= 0 else lerp_angle(actor.rotation, target, delta * turn_lerp)`; if
   `max_turn_rate > 0` the change `angle_difference(actor.rotation, r)` is clamped to `±max_turn_rate·delta`.
   A zero heading leaves `rotation` untouched.
   (Note: nothing else in the AI stack may call `look_at`/`rotate` on the actor either — gated below.) (`delta * turn_lerp` is not clamped to 1, matching today's
   interceptor `lerp_angle(rotation, target, delta * 7.0)` for the t14 port.)
7. Boost timer `-= delta`; clear primary, nudges and face request.

`_ready()`:
- `actor = get_parent() as CharacterBody2D`. If null (and there *is* a parent): `push_warning` once and stay
  inert (`actor` null → `step()` no-op). **No `push_error`** — load integrity allows none, and a warning only
  happens on `_ready()`, never on load.
- If `constraint == null and constraint_mode == AUTO`: `constraint = EnemyWorld.movement_constraint(get_tree())
  as MovementConstraint` (null today; t11 makes it real). `NONE` never calls `EnemyWorld`.

Alternative rejected: persistent requests (last request holds until changed). It makes a brain that forgets
to request keep flying forever, and makes `boost` end in an ambiguous state. Per-step requests are the
`NavigationAgent2D`/steering norm and what the epic's "one primary request per tick" says.

### `BaseEnemy`
```gdscript
var _brain: EnemyBrain        # resolved by type in _ready (first child that `is EnemyBrain`)
var _mover: EnemyMover        # same
var _ai_suspended := false
func _physics_process(delta):
    if _ai_suspended or _brain == null: return
    _brain.tick(delta)
    if _mover: _mover.step(delta)
func suspend_ai():             # idempotent
    if _ai_suspended: return
    _ai_suspended = true
    if _brain: _brain.on_suspended()
    if _mover: _mover.halt()
func is_ai_suspended() -> bool
```
- Subclasses with their own `_physics_process` (bomber, gunship, kamikaze, ram, drone interceptor)
  override it entirely (GDScript 4 does not chain callbacks), so they are byte-identical. Subclasses without
  one (light assault, interceptor, bonus drone, space station, sniper — which uses `_process`) become physics-processing but return at the first line — no behaviour change.
- `BaseEnemy._ready()` never calls `set_physics_process(false)` (it would switch off the subclasses' own
  override).
- `suspend_ai()` does not touch `AttackController`: a rail-driven ship keeps its timer-based fire as today. A
  `driven_by_brain` controller stops with the brain — acceptable, no such enemy rides a rail in Phase 1
  (noted for Phase 15).
- `base_enemy.gd` itself writes no `velocity`/`rotation` (the sprite flip writes a child's
  `rotation_degrees`), so the single-writer sweep can include it as an ancestor (below).

### `EnemyPathMover._ready()`
After the existing two steps, unchanged and unconditional:
```gdscript
	_actor.set_physics_process(false)               # today
	var state_machine := _actor.get_node_or_null("AIStateMachine")   # today
	if state_machine: state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	if _actor.has_method("suspend_ai"):             # new, additional (P-10, F3)
		_actor.suspend_ai()
```
No `else`. The `PathMoverActor` fixture has no `suspend_ai()` and is unaffected.

### Fixture enemy (`tests/helpers/`)
- `fixture_enemy.tscn`: root `CharacterBody2D` (`motion_mode = floating`) with `fixture_enemy.gd`
  (extends `BaseEnemy`, adds nothing), children `Health` (health_component.gd), `HurtBox` (Area2D,
  hurtbox_component.gd, layer 512), `HitFlashAnimationPlayer` (library with `RESET` and `hit`), `EnemyMover`,
  `Brain` (fixture_brain.gd). All ext_resources **UID-less**, no scene uid, no `unique_id=` and no
  `metadata/_custom_type_script` copied from any template (CLAUDE.md: never hand-type or copy a UID).
- `fixture_brain.gd` (extends `EnemyBrain`): configurable in tests — `desired_velocity`, `face_point`
  (`Vector2.INF` = none), a `decision_interval` (s, accumulated delta) at which it draws `rng.randf()` and
  appends it to `decisions`; it counts `tick_count`, `suspended_count`, and records `tick_log` (the delta each
  tick). Each tick it calls `mover.request_velocity(desired_velocity)` and `face_toward` if set.
- Script-built helper actors for the unit test are plain `CharacterBody2D.new()`; the "has
  `sprite_forward_angle`" case uses the fixture enemy root.

### Single-writer gate (`test_enemy_mover_single_writer.gd`, invariant)
Rosters (all outside `addons/`, `.godot/`):
- **A — AI scripts:** every `*_brain.gd` anywhere, and every `global/enemy_ai/*.gd` except `enemy_mover.gd`.
  Forbidden: a write through a receiver — `(actor|_actor|body|_body|self)\.(velocity(\.[xy])?|rotation|global_rotation|
  rotation_degrees)` followed by `=`/`+=`/`-=`/`*=`/`/=` (not `==`), `(actor|_actor|body|_body)\.(set_velocity|set_rotation|look_at|rotate)\(`, and any `move_and_slide(` / `move_and_collide(`. `info.velocity = …` in `target_info.gd` is a
  snapshot write and is (correctly) not matched (N2).
- **B — mover-driven enemy roots:** every `.tscn` whose text references `enemy_mover.gd`; its root node's
  script **and that script's ancestor scripts** (`get_base_script()` chain, `res://` only; `enemy_mover.gd`
  never appears there). The prefilter matches the full path `res://global/enemy_ai/enemy_mover.gd`; the root
  script is read with `PackedScene.get_state()` (node 0's `script` property), not by instantiating. Forbidden: bare or `self.` writes to `velocity` (incl. `velocity.x`/`.y`, review R4)/`rotation`/`global_rotation`/
  `rotation_degrees` (`(^|[^\w.])` anchor), bare or `self.` `set_velocity(`/`set_rotation(`/`look_at(`/`rotate(`, and `move_and_slide(` /
  `move_and_collide(`. From t10 this covers `fixture_enemy.gd` + `base_enemy.gd`; t14's interceptor joins
  automatically.
- Comments are stripped per line (from the first `#` outside a string literal) before matching, so a doc
  comment quoting `actor.velocity = …` is not a hit.
- Allowlist: empty, permanent (a `const ALLOWLIST: Array[String] = []` asserted empty).
- Cases: roster A non-empty and contains `enemy_brain.gd` and `target_info.gd`; roster B non-empty and contains
  the fixture root script and `base_enemy.gd`; no hits in A; no hits in B; **boundary (can fail):** the same
  matcher functions run on synthetic sources — `"rotation = 0.0"` (B) and `"actor.velocity = Vector2.ZERO"`,
  `"\tmove_and_slide()"`, `"actor.look_at(p)"`, `"actor.velocity.y += 1.0"` (A) and `"velocity.x = 0.0"`, `"rotate(0.1)"` (B) are reported; `"if velocity == v:"`, `"# actor.velocity = v"`, `"info.velocity =
  v"` (A) and `"var s := velocity.x"`, `"sprite.rotation_degrees = 180.0"` (B) are not.

## Build sequence
1. Fixture scripts/scene + `MovementConstraint` + `EnemyBrain` + `EnemyMover` skeleton (compiles, load clean).
2. `test_enemy_mover.gd` red → implement `EnemyMover` → green.
3. `test_enemy_brain_contract.gd` red → `BaseEnemy` tick/`suspend_ai` + `EnemyPathMover` call → green;
   `test_enemy_path_mover.gd` unchanged and green.
4. `test_enemy_mover_single_writer.gd`; prove the boundary by temporarily adding a write to the fixture
   (then revert).
5. `godot --import` (creates `.uid` sidecars) + full `bash /agent/verify.sh`; `scripts/check-test-leaks.sh`.
6. Docs: `updating-project-docs` (global.md enemy_ai section, PROJECT.md single-writer convention line,
   CLAUDE.md gate entry, tests/README coverage); `DECISIONS.md` only for deviations.

## Test plan
**`tests/unit/test_enemy_mover.gd`** (plain `CharacterBody2D` actor, `motion_mode = FLOATING`, in the tree;
`mover.step(dt)` called directly with `dt = 1/60`, or `dt = 1/64` wherever a duration is summed over steps —
1/64 is exact in binary floating point, so accumulated clocks hit their boundaries exactly (review R3, epic N7)):
- pass-through: all limits 0 → `velocity == requested`, `move_and_slide` moved the actor.
- `acceleration = 600`: from 0 toward (300,0), one step → |v| = 10; after 30 steps → 300 (exact, not overshoot).
- `braking = 1200`, `acceleration = 600`: from (300,0) toward 0, one step → 280; **boundary:** `braking = 0` →
  290 (falls back to acceleration).
- `acceleration = 0` → instant.
- `max_speed = 100`: request (300,0) → 100; boost at 480 ignores it.
- `add_nudge` sums with the primary; second `request_velocity` in one tick replaces the first.
- requests clear after a step: no request next step → velocity 0 (instant) / decays at braking.
- constraint: an injected doubling constraint doubles the velocity; `constraint_mode = NONE` with an
  `&"assault_arena"` provider that answers `enemy_movement_constraint()` (a stub node) → `constraint` stays
  null; `AUTO` with that stub → resolves the stub's instance; injected constraint set before `add_child` wins
  over AUTO.
- facing: plain actor (no `sprite_forward_angle`) heading RIGHT → rotation `-PI/2` (PI/2 default); fixture
  enemy with `sprite_forward_angle = -PI/2` heading UP → 0; nose-down heading DOWN → 0; `face_toward` beats the
  velocity; zero heading leaves rotation unchanged.
- `turn_lerp = 7`: one step from 0 toward PI/2 target → `lerp_angle(0, t, 7/60)`.
- `max_turn_rate = PI` (rad/s): target PI/2 away, one step → change exactly `PI/60`; **boundary:** 0 = uncapped
  (snaps).
- `boost(RIGHT, 480, 0.125)` at `dt = 1/64`: velocity 480 for 8 steps, not boosting on the 9th (back to the
  primary request).
- `halt()` zeroes velocity and cancels a boost.
- wrappers (review R2): for each of `seek`, `arrive`, `orbit`, `intercept`, `retreat_from`, `evade`, `strafe`,
  `hold_position`, `drift`, one step with all limits 0 gives `velocity == Steering.<same>(…)` with the
  documented argument mapping; plus `arrive` with `acceleration = 600, braking = 1200` passes 1200 as the
  slowing rate (the velocity equals `Steering.arrive(…, 1200)` and differs from `…, 600)` at a point inside
  the 600-radius).
- **boundary:** mover under a `Node2D` parent → no engine error (GUT error tracker), `actor == null`, `step()`
  is a no-op (the warning itself is asserted if GUT's tracker records it, otherwise not); a bare `EnemyMover.new()` stepped without a tree → no crash.

**`tests/integration/test_enemy_brain_contract.gd`** (fixture enemy):
- brain resolves `actor` (the root), `mover`, and `attack` (null; and an `AttackController` added before
  `add_child` is found).
- order: brain requests `(k*10, 0)` on its k-th tick; after `entity._physics_process(dt)` k times,
  `velocity == (k*10,0)` — the mover stepped *after* the brain in the same frame (a mover-first loop lags by one).
- one tick per frame: after N direct calls, `tick_count == N` and `tick_log` all `dt`; and a real
  `await wait_physics_frames(3)` advances `tick_count` by **exactly** 3 (the engine drives it once per frame; a
  brain that also ticked itself would give 6). Direct-call cases never `await`, so no engine frame interleaves.
- `suspend_ai()` → no further ticks, `velocity == ZERO`, `on_suspended` called once even when called twice.
- `EnemyPathMover` attached (after `add_child`, as `wave_manager.gd` does) → `is_ai_suspended()`,
  `suspended_count == 1`, `is_physics_processing() == false` (never switched off by the test itself — only the
  *path mover's own* ticking is disabled, as t2 does), and after 20 path ticks the position equals
  `spawn + movement.sample(t) * WORLD_SCALE` exactly (0.001).
- rng (`dt = 1/64`): two fixtures with `rng_seed = 1234` → identical `decisions` over 128 ticks (2 s);
  `rng_seed = 99` → a different sequence; decisions are drawn at the accumulated-delta interval (0.25 s → exactly
  8 in 128 ticks; **boundary:** none after 15 ticks, one after 16).
- no brain: fixture with its `Brain` removed (and `free()`d) before `add_child`, `velocity = (50, 0)` set →
  `_physics_process(dt)` leaves `velocity == (50, 0)` and `position` unchanged (a mover stepped without a brain
  would zero it — review R5); a legacy subclass (`bonus_drone.tscn` has no own `_physics_process`) is inert
  too: its position is unchanged after `_physics_process(dt)`.

**`test_enemy_mover_single_writer.gd`** — as specified above.

Existing gates that must stay green unchanged: `test_enemy_path_mover.gd` (incl. the real light assault ship),
t1 enemy pins, `test_drone_interceptor.gd`, `test_patrol_drone.gd`, config isolation, contact damage /
hitbox / hurtbox geometry, player-bullet lifetime, signal arity, project load integrity, station family.

## Risks
- **Real physics frames in GUT:** subclasses without their own `_physics_process` now tick every frame; the
  early return is cheap. A leaked `await` — none planned beyond `wait_physics_frames`; check with
  `scripts/check-test-leaks.sh`.
- **`move_and_slide()` outside a physics frame** in unit tests uses the *process* delta (review note), not the
  physics step; tests assert on
  `velocity`, and on position only as "moved / not moved".
- **Fixture `.tscn` loaded by load-integrity:** UID-less ext_resources are legal; if Godot warns on missing
  uid for `.gd` sidecars, run `--import` first so sidecars exist.
- **A brain-driven `AttackController` stops on a rail** (brain no longer ticks). No Phase 1 enemy is both;
  logged in `DECISIONS.md` for Phase 15.

## Out of scope
- The corridor constraint (t11), dual-mode harness (t12), interceptor port (t14), docs close-out (t15).
- Weighted steering blending (rejected in epic plan), `DamageReaction` adoption (deferred).
