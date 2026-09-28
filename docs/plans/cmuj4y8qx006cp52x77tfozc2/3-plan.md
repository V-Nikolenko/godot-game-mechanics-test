# ContactProfile and ContactBlast — task plan (epic step t3)

Task `cmuj4y8qx006cp52x77tfozc2`. The **design is already approved**: epic plan
`docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md` §2.3 (rev 2, the answer to epic review B1) and its §4 rows. This
plan does not redesign it; it pins the concrete API, the edge rules the epic plan leaves to the implementer, and the
test fixture. Code facts: `1-context.md`.

## Problem

Today every enemy's `ContactHitBox` is always live: touching any enemy hurts, all the time. The phase-2 drones need
three more rules: *never* (Bonus Drone, made explicit), *only while attacking* (Razor dash) and *only while attacking,
then explode* (Swarm burst) — and the explosion has to actually hurt a player standing next to the drone, including
when the player shoots the committed drone point-blank. This task builds the mechanism; no enemy changes behaviour
yet (every legacy enemy resolves the default COLLISION profile, which touches nothing).

## Design

### `global/components/contact_profile.gd` — `class_name ContactProfile extends Node`

```
enum Mode { NONE, COLLISION, RAMMING, EXPLOSIVE }
@export var mode: Mode = Mode.COLLISION
@export var blast_radius: float = 0.0
@export var blast_damage: int = 0
@export var blast_frames: int = 3
signal contact_made(area: Area2D)
signal detonated(position: Vector2)
func setup(actor: Node2D, hit_box: HitBox, health: Health) -> void
func set_armed(armed: bool) -> void
func is_armed() -> bool
func detonate() -> void
```

- `setup()` stores the three references (any may be null except `actor`), clamps `blast_frames` to ≥ 2 with a
  `push_error` (clamp happens here, not in a setter, so a scene-authored value is checked once, at a point where a
  test can `assert_push_error`), connects `hit_box.area_entered → _on_contact` and `health.amount_changed →
  _on_health_changed`, and applies the mode's resting state:
  - NONE: hitbox `monitorable`/`monitoring` → false (`set_deferred`).
  - COLLISION: **the hitbox is not touched at all.** This keeps every legacy enemy byte-for-byte, including
    `SpaceStation`'s own death-time `collision_layer = 0` write.
  - RAMMING / EXPLOSIVE: disarmed (both flags false, `set_deferred`).
  - `setup()` is idempotent-safe: a second call is ignored (guards against a double connect).
- `set_armed(a)`: no-op for NONE / COLLISION (`is_armed()` stays false for them). For RAMMING / EXPLOSIVE it records
  `_armed` and sets both flags with `set_deferred` (C5), so it is legal from a physics callback.
- `_on_contact(area)`: NONE → ignore; RAMMING / EXPLOSIVE while unarmed → ignore (belt and braces for the one flush
  in which the deferred disable has not landed yet); otherwise `contact_made.emit(area)`, then EXPLOSIVE →
  `detonate()`.
- `_on_health_changed(current)`: `current == 0 and mode == EXPLOSIVE and _armed` → `detonate()`. Unarmed death never
  detonates. Repeat emits are harmless (idempotent `detonate()`).
- `detonate()`: EXPLOSIVE only (other modes: no-op). A `_detonated` flag makes it idempotent; it is set
  **before** spawning, because a contact handler that kills the owner (`health.set_health(0)`, the Swarm's rule)
  re-enters `detonate()` through `_on_health_changed` while the contact-path call is on the stack. Container is
  `actor.get_parent()`; if the actor is null / freed / not inside the tree or has no parent → `push_warning`,
  nothing spawned, nothing emitted (the flag is still set, so a later call does not retry). Otherwise
  `ContactBlast.spawn(container, actor.global_position, blast_radius, blast_damage, blast_frames)` and
  `detonated.emit(at)`.
- It never reads or writes motion; it holds no timer.

### `global/components/contact_blast.gd` — `class_name ContactBlast extends HitBox`

```
static func spawn(container: Node, at: Vector2, radius: float, damage: int, frames: int) -> ContactBlast
```

- Builds the node out of tree: `CollisionShape2D` + `CircleShape2D(radius)`, `collision_layer =
  CollisionLayers.ENEMY_HITBOX` (256), `collision_mask = 0`, `monitorable = true`, `monitoring = false`, `damage`,
  `damage_type = CONTACT`, stores `at` and `frames` (clamped ≥ 2).
- Parents it with a **deferred call on the blast itself**, `blast._attach.call_deferred(container)` — legal from
  inside an `area_entered` callback — and returns it (it is not in the tree until the next message flush).
  `_attach(container)` takes an **untyped** parameter (a typed `Node` parameter makes the deferred call itself fail
  on a freed container — "Cannot convert argument 1 from Object to Object" — before the body runs) and does
  `container.add_child(self)` if `is_instance_valid(container) and container.is_inside_tree()`, otherwise
  `queue_free()`s itself (`free()` from inside its own deferred call is refused: "Object is locked and can't be
  freed"). Review round 2 R2-B1. **Deviation from the literal §2.3 wording** (`container.add_child.call_deferred(blast)`), review
  round 1 B1: a deferred call whose target (the container) is freed first is dropped by the engine and the orphan
  blast leaks (`ObjectDB instances leaked at exit`); deferring on the blast means something always owns it. Same
  timing: both run in the same message flush.
- `_enter_tree()`: `global_position = _at` (after parenting, `ExplosionEffect`'s reason).
- `_physics_process`: `_frames_alive += 1`; at `>= frames` → `queue_free()` (and stops counting). No timer.
- Does not hit enemies (mask 0 and enemy hurtboxes do not mask 256). Not an enemy, not scored
  (`ScoreTracker` only registers `WaveManager.enemy_spawned`).

### `BaseEnemy` wiring

- New `var contact_profile: ContactProfile`, resolved in `_ready()` right after the defense profile by
  `_resolve_contact_profile()`: the first scene-authored `ContactProfile` child, else `ContactProfile.new()` (mode
  COLLISION) added as a child. Then `contact_profile.setup(self, contact_hit_box, health)`.
- `suspend_ai()` calls `contact_profile.set_armed(true)` (inside the existing idempotence guard; null-guarded because
  a subclass could in principle suspend before `_ready()`). COLLISION ignores it, so rails are unchanged for every
  legacy enemy.
- Nothing else in `BaseEnemy` changes: no subclass override is touched, and the Kamikaze / Interceptor keep their
  own `area_entered` connections until their own tasks (t8b, t9) move them onto `contact_made`.

### Rejected alternatives
- Blast as a child of the profile / enemy: freed with the owner in the frame it is enabled (epic review B1).
- `create_timer` lifetime for the blast: the suite's leak trap, and it would outlive a freed test tree.
- COLLISION re-asserting `monitorable = true`: would silently undo `SpaceStation`'s death-time layer write ordering
  and change nothing useful.

## Build sequence

1. **Tests first**: `tests/unit/test_contact_profile.gd`, `tests/integration/test_contact_blast_damage.gd`, the new
   `test_base_enemy.gd` cases, and a fixture helper `tests/helpers/contact_fixture.gd` (static builder: instantiates
   `tests/helpers/fixture_enemy.tscn`, adds a code-built `ContactHitBox` — layer 256, mask 128, CONTACT, circle r 10
   — and an optional `ContactProfile` before the enemy enters the tree). Run them; they fail on the missing classes.
2. `contact_blast.gd` → blast cases green.
3. `contact_profile.gd` → profile cases green.
4. `BaseEnemy` wiring → base-enemy cases green; run the full suite (legacy pins unchanged).
5. `bash /agent/verify.sh`, `scripts/check-test-leaks.sh`.
6. Docs: `updating-project-docs` (global.md components table + integration recipe, PROJECT.md mention, CLAUDE.md is
   not changed — no new gate file). DECISIONS.md only if something deviates from §2.3.

## Test plan

`tests/unit/test_contact_profile.gd` (fixture enemy in a container `Node2D`, real physics frames where noted):
- mode matrix after `_ready()` + 2 physics frames: NONE → hitbox monitorable false / monitoring false; COLLISION →
  unchanged (true/true); RAMMING, EXPLOSIVE → false/false; `is_armed()` false for all.
- RAMMING `set_armed(true)` + physics frames → true/true, `is_armed()`; `set_armed(false)` → false/false.
- **`set_armed(true)` on NONE and COLLISION is a no-op** (`is_armed()` false, NONE stays disabled).
- EXPLOSIVE armed: emitting `hit_box.area_entered(area)` → `contact_made` once with that area, `detonated` once.
- RAMMING armed: contact → `contact_made`, no `detonated`, no blast node.
- **Unarmed RAMMING / EXPLOSIVE contact → no `contact_made`.** COLLISION contact → `contact_made` (always on).
- `detonate()` twice → one `detonated`, one `ContactBlast` in the container.
- **`blast_frames = 1` → clamped to 2, with a push_error** (`assert_push_error`).
- The blast: parent is the owner's parent, `global_position` = owner's `global_position` (owner placed off-origin,
  container itself offset so a local/global mix-up fails), **still in the tree after the owner is freed**, gone after
  `blast_frames` physics frames. Frames are counted from the blast **entering the tree** (a `tree_entered` probe
  records `Engine.get_physics_frames()`), and "gone" is asserted as queued-for-deletion or freed, never as "still
  valid" (which lags `queue_free` by a frame): not queued after `blast_frames − 1` of its own frames, queued or freed
  after `blast_frames`.
- EXPLOSIVE death while armed → detonates; **death while unarmed → no `detonated`, no blast.**
- `detonate()` on a COLLISION profile → nothing.
- `detonate()` with an actor outside the tree → `assert_push_warning`, no emit, no blast.
- **Contact then death in one call** (a `contact_made` handler does `health.set_health(0)`, the Swarm's rule): one
  `detonated`, one blast.
- **Container freed before the flush** (detonate, free the container in the same frame, await frames): no error, the
  returned blast is freed; `check-test-leaks.sh` is the other half of this case.
- `suspend_ai()` arms a RAMMING profile; a COLLISION one stays unarmed and its hitbox untouched.
- **Engine pin (C5):** a RAMMING fixture enemy with its contact box already overlapping a real `HurtBox` (layer 128,
  mask 1281), disarmed for several physics frames (0 hits), then `set_armed(true)` → exactly 1 `received_damage`
  over the following frames.

`tests/integration/test_contact_blast_damage.gd` — player side is a real `HurtBox` (layer 128, mask 1281,
CircleShape r 12) whose `received_damage` drives a real `Health.decrease` (the `PlayerBase._apply_damage` path with
no shield / temp HP / i-frames). Everything sits **off-origin** (player at (300, 200), container offset too), so a
blast wrongly left at (0, 0) — the epic's original B1 bug — fails. Enemy: EXPLOSIVE fixture, contact box r 10
placed 40 px away (no contact overlap),
`blast_radius` 60, `blast_damage` 25:
- **armed + `health.set_health(0)` → player health drops by exactly 25**, blast gone afterwards;
- **unarmed + killed → 0**;
- armed, enemy 120 px away (outside radius + hurtbox) → 0;
- **detonation from inside an `area_entered` callback** (armed EXPLOSIVE touching the hurtbox so the real physics
  contact fires the detonation) → no engine error (`get_errors()` empty) and, after awaiting, the blast is a child
  of the container. It can fail: a direct `add_child` of an `Area2D` inside `area_entered` logs "Can't change this
  state while flushing queries", and GUT 9.7.1 fails a test on an unexpected engine error; the test comment says so;
- the blast survives its owner's free.

`tests/integration/test_base_enemy.gd` (extended, no existing assertion changed):
- every swept legacy enemy resolves a `contact_profile` in mode COLLISION, exactly one `ContactProfile` child;
- Bonus Drone resolves cleanly (COLLISION default, `contact_hit_box` null, no error), and the hurtbox mask pins are
  unchanged (already covered by the existing case);
- a scene-authored profile is used instead of a default (fixture).

Existing gates that must stay green untouched: `test_enemy_contact_damage`, `test_contact_hitbox_geometry`, the
station family, `test_drone_interceptor`, `test_enemy_mover_single_writer`, `test_signal_emit_arity`,
`test_project_load_integrity`, `test_suite_integrity`; plus `scripts/check-test-leaks.sh`.

## Risks
- **Area enable timing** (C5): pinned by the engine test rather than assumed; the default 3 blast frames give slack.
- **GUT fails on unexpected `push_error`/engine errors**: every intentional one is asserted.
- **Default profile adds a child to every enemy**: tests that count children? `test_base_enemy` checks named nodes
  only; the full suite run is the check.
- **Container freed while a blast is queued deferred** (GUT's `add_child_autofree` frees immediately; in game, a
  container freed the frame an enemy dies): `_attach()` frees the orphan, and a test covers it. Review round 1 B1
  corrected this plan's earlier claim that the engine simply drops it: the engine drops the *call* and leaks the node.

## Out of scope
- Moving the Kamikaze / Interceptor onto `contact_made` (t8b / t9), any enemy using RAMMING / EXPLOSIVE (t8b, t10),
  Armor collision (Ram Corvette phase), enemy friendly fire from the blast (epic §8).
