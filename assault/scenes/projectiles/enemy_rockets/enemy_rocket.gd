## EnemyRocket - the enemy rocket family's common contract (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.6,
## §2.7). One script; `kind` and the authored exports differ per scene, and **the tuning lives in those exports** (one
## source of truth per kind, whoever fires it; a difficulty tier sets exports before `launch()`).
##
## A sibling of `EnemyOrdnance`, not new kinds on it: a rocket has a heading, a nose-up rotation, a launch boost and an
## impact trigger. Never in group `enemies`, never scored.
##
## Contract with its launcher (a ship's `BulletPool`, or a fixture):
##   - `signal expired` - emitted exactly once per life: a detonation, a shoot-down or a lifetime fizzle. A pool
##     recycles on it; an unpooled rocket is freed by `expired -> queue_free`. Nothing here frees itself. A detonation
##     or a shoot-down emits it two physics ticks later (the rocket hidden meanwhile) - see `_end_after_overlaps()`.
##   - `reset()` restores the authored exports and a fresh, unlaunched state (`BulletPool.acquire()` calls it).
##   - `launch(dir, aim_point, launcher)` starts a life. The launcher passes nothing else; it may answer duck-typed
##     `launch_velocity() -> Vector2` (its component along `dir` is inherited) and `rocket_clear_radius() -> float`.
##
## Collision (no layer renamed):
##   - `HitBox` layer 32 (alone), mask 128 | 512, `ROCKET`. Closed until the rocket is clear of its launcher's CURRENT
##     position by `rocket_clear_radius() + body_radius + arm_clearance` - the rocket alone owns that rule. Enemy
##     hurtboxes (mask 1121), enemy ordnance, Ram plates and asteroids see it and take `impact_damage`; the player's and
##     allies' hurtboxes (mask 1281) never do - the HitBox only sees them and detonates the rocket, and the
##     `ContactBlast` (256) that follows is their only damage.
##   - `HurtBox` layer 512, mask 96: the shoot-down. Its `received_damage` is NOT connected; the rocket resolves every
##     area in its own `area_entered`: another rocket's HitBox and a `CONTACT` HitBox (the ally fighter's ram box on 64)
##     are ignored, anything else (a player bullet or missile) defuses it - a pop, no blast.
##
## It writes its own `global_position` and `rotation` (nose-up art: `rotation = heading.angle() + PI / 2`, the player
## missiles' convention, so `RocketTrail`'s local +Y exhaust leaves the tail) on ONE accumulated clock of physics deltas.
class_name EnemyRocket
extends Area2D

signal expired

enum Kind { DUMB, PURSUIT, CLUSTER, WARHEAD, SUBMUNITION }

@export var kind: Kind = Kind.DUMB

@export_group("Flight")
## Speed during the boost (plus the launcher's inherited speed along the launch direction).
@export var launch_speed: float = 140.0
@export var cruise_speed: float = 520.0
## Straight, unsteered flight at `launch_speed`: the visible launch.
@export var boost_seconds: float = 0.25
## px/s^2 from the boost speed to `cruise_speed` after the boost.
@export var accel: float = 900.0

@export_group("Guidance")
## rad/s. 0 = a straight (dumb) rocket.
@export var turn_rate: float = 0.0
## Seconds of steering after the boost; the heading freezes afterwards.
@export var guidance_seconds: float = 0.0
## Longest intercept (s) the rocket leads; beyond it, it aims at the player's position this far ahead.
@export var lead_max: float = 0.8

@export_group("Damage")
## What the impact deals to enemies, ordnance, plates and asteroids. The player never takes it.
@export var impact_damage: int = 16
@export var blast_radius: float = 36.0
## The player-facing number: the blast is the only thing that hurts the player or an ally.
@export var blast_damage: int = 16
@export var blast_frames: int = 3

@export_group("Body")
## Extra px past the launcher's clear radius and the rocket's own radius before the impact HitBox opens.
@export var arm_clearance: float = 8.0
@export var body_radius: float = 6.0

@export_group("Lifetime")
## Pushed into the `ProjectileLifetime` child; expiry by it is a fizzle (pop, no blast).
@export var max_time: float = 4.0
@export var max_distance: float = 1800.0

@export_group("Look")
@export var body_color: Color = Color(0.55, 0.12, 0.1)

## Properties `reset()` restores. Captured once in `_ready()`.
const _RESET_PROPS: Array[StringName] = [
	&"launch_speed", &"cruise_speed", &"boost_seconds", &"accel", &"turn_rate", &"guidance_seconds",
	&"lead_max", &"impact_damage", &"blast_radius", &"blast_damage", &"blast_frames", &"arm_clearance",
	&"body_radius", &"max_time", &"max_distance",
]

var _authored: Dictionary = {}
var _heading: Vector2 = Vector2.DOWN
var _speed: float = 0.0
var _aim: Vector2 = Vector2.ZERO
var _clock: float = 0.0
var _launched: bool = false
var _armed: bool = false
var _done: bool = false
## Set by a detonation or a shoot-down: physics ticks left before `expired` goes out (see `_end_after_overlaps()`).
var _expire_in: int = 0
var _launcher: Node = null
var _had_launcher: bool = false
var _clear_radius: float = 0.0
var _launch_point: Vector2 = Vector2.ZERO

@onready var _hit_box: HitBox = $HitBox as HitBox
@onready var _hit_shape: CollisionShape2D = $HitBox/CollisionShape2D as CollisionShape2D
@onready var _hurt_box: HurtBox = $HurtBox as HurtBox
@onready var _hurt_shape: CollisionShape2D = $HurtBox/CollisionShape2D as CollisionShape2D
@onready var _lifetime: ProjectileLifetime = $ProjectileLifetime as ProjectileLifetime
@onready var _pop: ExplosionEffect = get_node_or_null("Pop") as ExplosionEffect


func _ready() -> void:
	for prop in _RESET_PROPS:
		_authored[prop] = get(prop)
	# Scene instances share sub-resources; the radii are set per instance.
	_hit_shape.shape = _hit_shape.shape.duplicate()
	_hurt_shape.shape = _hurt_shape.shape.duplicate()
	_apply_exports()
	_hit_box.area_entered.connect(_on_hit_box_area_entered)
	_hurt_box.area_entered.connect(_on_hurt_box_area_entered)
	expired.connect(_on_expired)
	queue_redraw()


## Restores the authored exports and a fresh, unlaunched state. Called by `BulletPool.acquire()`.
func reset() -> void:
	for prop in _RESET_PROPS:
		set(prop, _authored[prop])
	_heading = Vector2.DOWN
	_speed = 0.0
	_aim = Vector2.ZERO
	_clock = 0.0
	_launched = false
	_armed = false
	_done = false
	_expire_in = 0
	_launcher = null
	_had_launcher = false
	_clear_radius = 0.0
	modulate = Color.WHITE
	show()
	_apply_exports()
	_hit_box.set_deferred("monitoring", false)
	_hit_box.set_deferred("monitorable", false)
	_hurt_box.set_deferred("monitoring", true)
	_hurt_box.set_deferred("monitorable", true)
	_hit_shape.set_deferred("disabled", false)
	_hurt_shape.set_deferred("disabled", false)
	_lifetime.set_physics_process(true)
	_lifetime.reset()
	queue_redraw()


## Starts a life. `launcher` may be null (a submunition): arming then measures from the launch point with radius 0.
func launch(dir: Vector2, aim_point: Vector2, launcher: Node) -> void:
	_heading = dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	var inherited := 0.0
	_launcher = launcher if is_instance_valid(launcher) else null
	_had_launcher = _launcher != null
	_clear_radius = 0.0
	if _launcher != null:
		if _launcher.has_method(&"launch_velocity"):
			inherited = maxf(0.0, (_launcher.launch_velocity() as Vector2).dot(_heading))
		if _launcher.has_method(&"rocket_clear_radius"):
			_clear_radius = float(_launcher.rocket_clear_radius())
	_speed = launch_speed + inherited
	_aim = aim_point
	_launch_point = global_position
	_clock = 0.0
	_launched = true
	# Exports set after `acquire()` (a difficulty tier) reach the children here.
	_apply_exports()
	rotation = _heading.angle() + PI / 2.0
	queue_redraw()


## The current unit heading.
func heading() -> Vector2:
	return _heading


func speed() -> float:
	return _speed


## True once the impact HitBox has been opened (it is clear of its launcher).
func is_armed() -> bool:
	return _armed


## True inside the steering window: after the boost, before `boost_seconds + guidance_seconds`.
func is_guiding() -> bool:
	return _launched and not _done and turn_rate > 0.0 \
			and _clock >= boost_seconds and _clock < boost_seconds + guidance_seconds


## The point the rocket is steering at: the launch aim until guidance replaces it.
func aim_point() -> Vector2:
	return _aim


func _physics_process(delta: float) -> void:
	_tick(delta)


## One flight step. Tests hand-tick it (physics process off) with a fixed delta.
func _tick(delta: float) -> void:
	if _expire_in > 0:
		_expire_in -= 1
		if _expire_in == 0:
			expired.emit()
		return
	if _done or not _launched:
		return
	if is_guiding():
		_steer(delta)
	if _clock >= boost_seconds:
		_speed = move_toward(_speed, cruise_speed, accel * delta)
	global_position += _heading * _speed * delta
	rotation = _heading.angle() + PI / 2.0
	_clock += delta
	if not _armed:
		_update_arming()
	queue_redraw()


## Lead pursuit with a turn cap: the intercept point, or the player's position `lead_max` ahead when the intercept
## fails or lies further out than that. No player: no turn at all (the heading is kept).
func _steer(delta: float) -> void:
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		return
	var result := target.intercept(global_position, _speed)
	if result.ok and float(result.time) <= lead_max:
		_aim = result.point
	else:
		_aim = target.predicted_position(lead_max)
	_heading = Steering.turn_toward(_heading, _aim - global_position, turn_rate, delta)


func _update_arming() -> void:
	var from := _launch_point
	var radius := 0.0
	if _had_launcher:
		if not is_instance_valid(_launcher) or not (_launcher as Node).is_inside_tree():
			_arm()
			return
		from = (_launcher as Node2D).global_position
		radius = _clear_radius
	if global_position.distance_to(from) >= radius + body_radius + arm_clearance:
		_arm()


func _arm() -> void:
	_armed = true
	_hit_box.set_deferred("monitoring", true)
	_hit_box.set_deferred("monitorable", true)


## The exports the children carry: impact damage, both radii and the lifetime caps.
func _apply_exports() -> void:
	_hit_box.damage = impact_damage
	_hit_box.damage_type = HitBox.DamageType.ROCKET
	(_hit_shape.shape as CircleShape2D).radius = body_radius
	(_hurt_shape.shape as CircleShape2D).radius = body_radius + 2.0
	_lifetime.max_time = max_time
	_lifetime.max_distance = max_distance


func _on_hit_box_area_entered(area: Area2D) -> void:
	if _done or not _armed:
		return
	if area.get_parent() is EnemyRocket:
		return
	if ArmorQuery.deflects(area, _hit_box):
		return
	_detonate()


func _on_hurt_box_area_entered(area: Area2D) -> void:
	if _done:
		return
	var hb := area as HitBox
	if hb == null or hb.get_parent() is EnemyRocket:
		return
	if hb.damage_type == HitBox.DamageType.CONTACT:
		return
	_defuse()


## Blasts into the parent and ends the life. Exactly once: `_done` latches before anything else.
func _detonate() -> void:
	if _done:
		return
	_mark_done()
	ContactBlast.spawn(get_parent(), global_position, blast_radius, blast_damage, blast_frames)
	_pop_here()
	_end_after_overlaps()


## Shot down: a pop, no blast, end of life.
func _defuse() -> void:
	if _done:
		return
	_mark_done()
	_pop_here()
	_end_after_overlaps()


## Ends the life two physics ticks later, hidden meanwhile. A detonation or a shoot-down happens inside a physics
## callback, while the impact HitBox (or the HurtBox) still overlaps what it met. A pool recycles on `expired` by
## re-parenting the rocket, and `Area2D` re-emits `area_entered` for an overlapping area that re-enters the tree while
## the physics server still reports the pair - so recycling at once hits the enemy a second time. `_mark_done()` closes
## the areas AND disables their shapes (deferred, at the end of this frame; switching `monitorable` off alone leaves
## the existing pair in place - measured), the server drops the pair in this frame's step, and the exit is delivered in
## the next frame's query flush, which Godot runs before that frame's `_physics_process`: so the second tick is the
## first clean one. Pinned by `test_enemy_rockets.gd` (the enemy takes `impact_damage` exactly once).
func _end_after_overlaps() -> void:
	hide()
	_expire_in = 2


## Any `expired` - ours or the `ProjectileLifetime` backstop's - ends the life. From the backstop it is a fizzle.
func _on_expired() -> void:
	if _done:
		return
	_mark_done()
	_pop_here()


func _pop_here() -> void:
	if _pop:
		_pop.explode(global_position, get_parent())


func _mark_done() -> void:
	if _done:
		return
	_done = true
	# Every area is closed deferred: this can run inside a physics callback.
	_hit_box.set_deferred("monitoring", false)
	_hit_box.set_deferred("monitorable", false)
	_hurt_box.set_deferred("monitoring", false)
	_hurt_box.set_deferred("monitorable", false)
	_hit_shape.set_deferred("disabled", true)
	_hurt_shape.set_deferred("disabled", true)
	# Keeps the backstop from emitting a second `expired` in the frame this life ended.
	_lifetime.set_physics_process(false)


## Placeholder look (t9 swaps in the sprite): a nose-up body along local -Y, fins at the tail.
func _draw() -> void:
	var r := body_radius
	var body := PackedVector2Array([
		Vector2(0.0, -r * 1.8), Vector2(r * 0.6, -r * 0.6), Vector2(r * 0.6, r * 1.2),
		Vector2(-r * 0.6, r * 1.2), Vector2(-r * 0.6, -r * 0.6)])
	draw_colored_polygon(body, body_color)
	draw_line(Vector2(-r, r * 1.4), Vector2(r, r * 1.4), body_color.lightened(0.3), 2.0)
	var tip := Color(1.0, 0.3, 0.15) if _armed else Color(0.6, 0.6, 0.65)
	draw_circle(Vector2(0.0, -r * 1.2), r * 0.35, tip)
