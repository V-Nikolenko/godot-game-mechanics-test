## EnemyOrdnance - the persistent enemy ordnance family: Gravity Bomb, Mine and Pursuit Bomb
## (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.3). One script; `kind` and the authored exports
## differ per scene. Not an `EnemyBullet` and not a `BaseEnemy`: it is a small area the player can
## shoot down, so it is never in group `enemies` (homing rockets, EMP and the beam ignore it) and
## never counts for the score.
##
## Contract with its dropper (a Bomber's `BulletPool`, or a fixture):
##   - `signal expired` - the one end-of-life signal, emitted exactly once per life, by a blast, a
##     defuse, a fizzle or the `ProjectileLifetime` backstop. A pool recycles on it; an unpooled
##     ordnance is freed by `expired -> queue_free`. Nothing here frees itself.
##   - `reset()` restores the authored exports, health and state (the `EnemyBullet._authored_*`
##     pattern) and re-arms the `ProjectileLifetime` child.
##   - `launch(dir, speed, target_point)` starts a life. The dropper sets damage, radii and timings
##     (`blast_*`, `trigger_radius`, `arm_delay`, `warning_time`, ...) from its config BEFORE it.
##
## It moves itself (`position +=`) like `EnemyBullet`, on ONE accumulated clock of `_physics_process`
## deltas, so it never needs a scheduled callback that could outlive a freed tree. It detonates
## through `ContactBlast.spawn()` into its parent (the level container, since a pool reparents an
## active round there), so the blast outlives the ordnance. A SHOT never blasts: any player hit on the
## `HurtBox` kills its one `Health` and the ordnance pops and expires (defuse).
##
## The trigger is a POLL of `ProximityArea.get_overlapping_areas()` each tick once armed, not an
## `area_entered` signal: arming counts from launch, and a player who is already inside the radius
## when it arms must still set it off (plan review round 2, B1b).
class_name EnemyOrdnance
extends Area2D

signal expired

enum Kind { GRAVITY_BOMB, MINE, PURSUIT_BOMB }

@export var kind: Kind = Kind.GRAVITY_BOMB

@export_group("Trigger")
## Seconds after launch before the ordnance can be set off. 0 = armed at once.
@export var arm_delay: float = 0.3
## Radius of the `ProximityArea` that notices the player's hurtbox.
@export var trigger_radius: float = 80.0
## Seconds between being set off and detonating (the blinking warning). 0 = detonate at once.
@export var warning_time: float = 1.0

@export_group("Blast")
@export var blast_radius: float = 48.0
@export var blast_damage: int = 40
## Physics frames the `ContactBlast` stays alive (it clamps to its own minimum).
@export var blast_frames: int = 3

@export_group("Gravity bomb")
## Extra distance past the aim point before it detonates on its own.
@export var max_travel_margin: float = 120.0

@export_group("Mine")
## Seconds the launch velocity decays to zero over; the mine is stationary afterwards.
@export var eject_time: float = 0.3
## Seconds after launch before the mine fizzles (no blast).
@export var mine_life: float = 8.0
## Seconds the fizzle fade takes before `expired`.
@export var fizzle_time: float = 0.3

@export_group("Pursuit bomb")
## Seconds the bomb steers toward the player's predicted position, then freezes its heading.
@export var steer_window: float = 1.5
@export var turn_rate: float = 1.2
## Seconds ahead of the player's velocity the bomb aims.
@export var steer_lead: float = 0.6
@export var final_speed: float = 380.0
## Acceleration from the launch speed to `final_speed` once the heading is frozen.
@export var accel: float = 600.0

@export_group("Look")
@export var body_radius: float = 9.0
@export var body_color: Color = Color(0.18, 0.18, 0.2)

## Properties `reset()` restores. Captured once in `_ready()`.
const _RESET_PROPS: Array[StringName] = [
	&"arm_delay", &"trigger_radius", &"warning_time", &"blast_radius", &"blast_damage",
	&"blast_frames", &"max_travel_margin", &"eject_time", &"mine_life", &"fizzle_time",
	&"steer_window", &"turn_rate", &"steer_lead", &"final_speed", &"accel",
]

var _authored: Dictionary = {}
var _heading: Vector2 = Vector2.DOWN
var _launch_speed: float = 0.0
var _speed: float = 0.0
var _target_point: Vector2 = Vector2.ZERO
var _max_travel: float = 0.0
var _travelled: float = 0.0
var _clock: float = 0.0
var _warning: bool = false
var _warning_clock: float = 0.0
var _fizzling: bool = false
var _fizzle_clock: float = 0.0
var _done: bool = false

@onready var _hurt_box: HurtBox = $HurtBox as HurtBox
@onready var _health: Health = $Health as Health
@onready var _proximity: Area2D = $ProximityArea as Area2D
@onready var _proximity_shape: CollisionShape2D = $ProximityArea/CollisionShape2D as CollisionShape2D
@onready var _lifetime: ProjectileLifetime = get_node_or_null("ProjectileLifetime") as ProjectileLifetime
@onready var _pop: ExplosionEffect = get_node_or_null("Pop") as ExplosionEffect


func _ready() -> void:
	for prop in _RESET_PROPS:
		_authored[prop] = get(prop)
	# Scene instances share sub-resources; the trigger radius is set per instance.
	_proximity_shape.shape = _proximity_shape.shape.duplicate()
	_hurt_box.received_damage.connect(_on_hurt)
	_health.amount_changed.connect(_on_health_changed)
	expired.connect(_on_expired)
	queue_redraw()


## Restores the authored exports and a fresh, unlaunched state. Called by `BulletPool.acquire()`.
func reset() -> void:
	for prop in _RESET_PROPS:
		set(prop, _authored[prop])
	_heading = Vector2.DOWN
	_launch_speed = 0.0
	_speed = 0.0
	_travelled = 0.0
	_clock = 0.0
	_warning = false
	_warning_clock = 0.0
	_fizzling = false
	_fizzle_clock = 0.0
	_done = false
	modulate = Color.WHITE
	_health.current_health = _health.max_health
	_hurt_box.set_deferred("monitorable", true)
	_proximity.set_deferred("monitoring", true)
	if _lifetime:
		_lifetime.set_physics_process(true)
		_lifetime.reset()
	queue_redraw()


func launch(dir: Vector2, speed: float, target_point: Vector2) -> void:
	_heading = dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	_launch_speed = speed
	_speed = speed
	_target_point = target_point
	_travelled = 0.0
	_clock = 0.0
	_max_travel = global_position.distance_to(target_point) + max_travel_margin
	(_proximity_shape.shape as CircleShape2D).radius = trigger_radius
	queue_redraw()


## The current unit heading.
func heading() -> Vector2:
	return _heading


func is_armed() -> bool:
	return _clock >= arm_delay


## True from the moment the player sets it off until it detonates.
func is_warning() -> bool:
	return _warning


func _physics_process(delta: float) -> void:
	if _done:
		return
	_clock += delta
	_move(delta)
	_update_trigger(delta)
	queue_redraw()


func _move(delta: float) -> void:
	match kind:
		Kind.GRAVITY_BOMB:
			var step := _heading * _speed * delta
			global_position += step
			_travelled += step.length()
		Kind.MINE:
			if _clock < eject_time:
				var decay := 1.0 - _clock / eject_time
				global_position += _heading * _launch_speed * decay * delta
		Kind.PURSUIT_BOMB:
			if _clock < steer_window:
				_heading = Steering.turn_toward(_heading, _aim_point() - global_position, turn_rate, delta)
				_speed = _launch_speed
			else:
				_speed = move_toward(_speed, final_speed, accel * delta)
			global_position += _heading * _speed * delta


## Where a pursuit bomb steers: the player's predicted position, else the point it was aimed at.
func _aim_point() -> Vector2:
	var target := TargetInfo.player(get_tree())
	return target.predicted_position(steer_lead) if target.has_target else _target_point


func _update_trigger(delta: float) -> void:
	if _fizzling:
		_fizzle_clock += delta
		modulate.a = clampf(1.0 - _fizzle_clock / maxf(fizzle_time, 0.001), 0.0, 1.0)
		if _fizzle_clock >= fizzle_time:
			_finish()
		return
	if _warning:
		_warning_clock += delta
		if _warning_clock >= warning_time:
			_detonate()
		return
	if kind == Kind.GRAVITY_BOMB and _travelled >= _max_travel:
		_detonate()
		return
	if kind == Kind.MINE and _clock >= mine_life:
		_fizzling = true
		return
	if _clock < arm_delay:
		return
	if _player_in_range():
		if warning_time <= 0.0:
			_detonate()
		else:
			_warning = true
			_warning_clock = 0.0


func _player_in_range() -> bool:
	for area in _proximity.get_overlapping_areas():
		if area.collision_layer & CollisionLayers.PLAYER_HURTBOX:
			return true
	return false


## Blasts into the parent and ends the life. Exactly once: `_done` latches before anything else.
func _detonate() -> void:
	if _done:
		return
	_mark_done()
	ContactBlast.spawn(get_parent(), global_position, blast_radius, blast_damage, blast_frames)
	expired.emit()


## A shot: pop, no blast, end of life.
func _defuse() -> void:
	if _done:
		return
	_mark_done()
	if _pop:
		_pop.explode(global_position, get_parent())
	expired.emit()


## A mine that outlived `mine_life`: faded out, no blast.
func _finish() -> void:
	if _done:
		return
	_mark_done()
	expired.emit()


func _on_hurt(damage: int) -> void:
	if _done:
		return
	_health.decrease(damage)


func _on_health_changed(current_health: int) -> void:
	if current_health <= 0:
		_defuse()


## Any `expired` - ours or the `ProjectileLifetime` backstop's - ends the life.
func _on_expired() -> void:
	_mark_done()


func _mark_done() -> void:
	if _done:
		return
	_done = true
	# Both areas are closed deferred: this can run inside a physics callback.
	_proximity.set_deferred("monitoring", false)
	_hurt_box.set_deferred("monitorable", false)
	if _lifetime:
		# Keeps the backstop from emitting a second `expired` in the frame this life ended.
		_lifetime.set_physics_process(false)


func _draw() -> void:
	draw_circle(Vector2.ZERO, body_radius, body_color)
	if kind == Kind.PURSUIT_BOMB:
		draw_line(Vector2.ZERO, _heading * body_radius * 1.7, Color(1.0, 0.55, 0.2), 3.0)
	var lit := _clock >= arm_delay and not _done
	if not lit:
		draw_arc(Vector2.ZERO, body_radius + 2.0, 0.0, TAU, 20, Color(0.45, 0.45, 0.5), 1.5)
		return
	# Armed: a slow red blink. Warning: a fast blink that speeds up and shows the blast radius.
	var hz := 1.5
	if _warning:
		hz = 4.0 + 8.0 * clampf(_warning_clock / maxf(warning_time, 0.001), 0.0, 1.0)
	var on := fmod(_clock * hz, 1.0) < 0.5
	if on:
		draw_circle(Vector2.ZERO, body_radius * 0.55, Color(1.0, 0.15, 0.1))
	draw_arc(Vector2.ZERO, body_radius + 2.0, 0.0, TAU, 20, Color(1.0, 0.25, 0.15), 2.0)
	if _warning:
		draw_arc(Vector2.ZERO, blast_radius, 0.0, TAU, 40, Color(1.0, 0.3, 0.1, 0.35), 1.5)
