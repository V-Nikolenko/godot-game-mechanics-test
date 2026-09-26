## The Drone Interceptor's brain — the phase logic that used to live in
## `drone_interceptor.gd`'s own `_physics_process`, ported onto the brain/mover contracts as the
## Phase 1 architecture's proof consumer (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.11,
## P-8; task cmug33ldz00djm52wqu66uc4z).
##
## Kept 1:1 with the pre-port behaviour: the sibling `EnemyMover` runs with `acceleration = 0`
## (velocity is still assigned directly, exactly as the old `_phase_*` methods did),
## `turn_lerp = 7.0` (the old `ROTATION_LERP`), and `constraint_mode = NONE` — the port stays
## unconstrained in Assault (plan §2.5 "Phase 1 consumers"); Phase 2's Razor Drone turns the
## corridor on and re-pins.
##
## State mapping onto the IDEAS §4 vocabulary documented in `enemy_brain.gd`'s header:
##   ENTER (APPROACH) — `Steering.seek` straight at the player until within `orbit_radius`.
##   ORBIT (POSITION) — `Steering.orbit`; an `rng`-drawn 1-2s timer triggers DASH.
##   DASH  (ATTACK)   — direction locked once, to `TargetInfo.player().predicted_position(...)`,
##                       at `dash_speed`. Freed on leaving the world: the Assault provider's legacy
##                       cull rect (`EnemyWorld.cull_rect`) when there is one, else
##                       `dash_max_distance` from the dash's own start position (Open Space).
##
## Tuning is copied from `DroneInterceptorConfig` by `drone_interceptor.gd`'s `_ready()`, same as
## before the port — this script only owns the state machine and the movement/facing requests.
class_name DroneInterceptorBrain
extends EnemyBrain

enum Phase { ENTER, ORBIT, DASH }

@export_group("Movement")
## Preferred distance from the player while orbiting (px).
@export var orbit_radius: float = 130.0
## Angular velocity of the orbit anchor (rad/s). Positive = counter-clockwise.
@export var orbit_speed: float = 1.8
## Movement speed during ENTER (px/s).
@export var approach_speed: float = 200.0
## Maximum speed when correcting orbit position (px/s).
@export var orbit_correct_speed: float = 160.0

@export_group("Attack")
## Burst speed during the kamikaze dash (px/s).
@export var dash_speed: float = 480.0
## How far ahead to predict the player position for the dash target (seconds).
@export var dash_prediction_time: float = 0.2
## Open Space only (no Assault provider): the dash frees the drone this far from where it began
## (judgement call, plan §2.11 — a little more than a 1280 px screen width plus the orbit radius).
@export var dash_max_distance: float = 1600.0

var phase: Phase = Phase.ENTER

var _orbit_angle: float = 0.0
var _dash_timer: float = 0.0
var _dash_direction: Vector2 = Vector2.ZERO
var _dash_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	## Staggers groups so they don't all orbit/dash in lockstep — the same effect the pre-port
	## `randf_range` calls had, moved onto `rng` (plan review F10) so a seeded run is reproducible.
	_orbit_angle = rng.randf_range(0.0, TAU)
	_dash_timer = rng.randf_range(1.0, 2.0)


## Two passes, matching the pre-port `_physics_process`'s own two `match _phase:` blocks exactly:
## the first decides velocity (and may transition `phase` — e.g. ENTER reaching `orbit_radius`),
## the second faces using whatever `phase` is *after* that transition. So a tick that flips
## ENTER -> ORBIT still faces the player that same tick, even though it requests no velocity.
func tick(delta: float) -> void:
	var target := TargetInfo.player(get_tree())
	match phase:
		Phase.ENTER: _tick_enter(target)
		Phase.ORBIT: _tick_orbit(delta, target)
		Phase.DASH: _tick_dash()

	match phase:
		Phase.ENTER, Phase.ORBIT:
			if target.has_target:
				mover.face_toward(target.position)
		Phase.DASH:
			mover.face_toward(actor.global_position + _dash_direction)


func _tick_enter(target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	if actor.global_position.distance_to(target.position) <= orbit_radius:
		phase = Phase.ORBIT
		return
	mover.seek(target.position, approach_speed)


func _tick_orbit(delta: float, target: TargetInfo) -> void:
	_dash_timer -= delta
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	if _dash_timer <= 0.0:
		_begin_dash()
		return
	_orbit_angle += orbit_speed * delta
	mover.orbit(target.position, orbit_radius, _orbit_angle, orbit_correct_speed)


## Locks the dash direction from the current player prediction (or straight down with no target,
## the pre-port fallback) and enters DASH. Called from `tick()` on timer expiry; also exposed so a
## test can trigger a dash directly, isolating the direction formula from the random timer — the
## same technique `test_ram_ship.gd` uses for its own damage hook.
func _begin_dash() -> void:
	phase = Phase.DASH
	var target := TargetInfo.player(get_tree())
	var predicted: Vector2
	if target.has_target:
		predicted = target.predicted_position(dash_prediction_time)
	else:
		predicted = actor.global_position + Vector2(0.0, 200.0)
	_dash_direction = (predicted - actor.global_position).normalized()
	_dash_start = actor.global_position


func _tick_dash() -> void:
	mover.request_velocity(_dash_direction * dash_speed)
	_check_dash_end()


## Frees the drone once it has left the world: the Assault provider's legacy cull rect when there
## is one, else `dash_max_distance` from the dash's own start (Open Space — IDEAS §3.3/§38 reject a
## screen-visibility rule there, so distance travelled stands in for it; plan §2.11). Also callable
## directly, isolating the cull formula from the dash's own timing/direction (same technique as
## `_begin_dash()`, above).
##
## Deliberately explicit `<`/`>` comparisons, not `Rect2.has_point()`: Godot's `has_point()` treats
## a rect as half-open (inclusive min edge, EXCLUSIVE max edge), so it would cull a drone sitting
## exactly on the legacy cull rect's right/bottom edge — `_check_off_screen()` never did (same trap
## `ProjectileLifetime._physics_process()` avoids for the world-rect rule, plan review N6).
func _check_dash_end() -> void:
	var tree := get_tree()
	if EnemyWorld.has_cull_rect(tree):
		var rect := EnemyWorld.cull_rect(tree)
		var pos := actor.global_position
		var right := rect.position.x + rect.size.x
		var bottom := rect.position.y + rect.size.y
		if pos.x < rect.position.x or pos.x > right or pos.y < rect.position.y or pos.y > bottom:
			actor.queue_free()
		return
	if actor.global_position.distance_to(_dash_start) >= dash_max_distance:
		actor.queue_free()
